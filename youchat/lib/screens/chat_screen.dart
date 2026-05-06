import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'media_preview_screen.dart';
import '../auth/auth_manager.dart';
import '../services/chat_service.dart';
import '../widgets/message_bubble.dart';
import '../widgets/voice_recorder_widget.dart';
import '../services/notification_service.dart';
import 'user_profile_screen.dart';
import '../models/conversation_model.dart';
import '../widgets/connection_banner.dart';
import '../utils/constants.dart';

/// Chat screen — one-to-one encrypted messaging.
/// Features: encrypted messages, read receipts, 7-second deletion countdown,
/// typing indicator, no copy/forward.
class ChatScreen extends StatefulWidget {
  final String peerId;

  const ChatScreen({super.key, required this.peerId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _typingTimer;
  bool _isTyping = false;
  bool _hasText = false;
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Mark this chat as active so notifications are suppressed
    NotificationService().setActiveChat(widget.peerId);
    NotificationService().cancelForChat(widget.peerId);

    // Mark messages as read when opening chat
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatService>().markAsRead(widget.peerId);

      // Listen for errors from ChatService
      context.read<ChatService>().addListener(_checkForErrors);
    });
  }

  void _checkForErrors() {
    final chatService = context.read<ChatService>();
    final error = chatService.lastError;
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: const Color(0xFFFF3B3B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 4),
        ),
      );
      chatService.clearError();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();

    // Clear active chat so notifications resume
    NotificationService().clearActiveChat();

    // Remove error listener
    try {
      context.read<ChatService>().removeListener(_checkForErrors);
    } catch (_) {}

    // Stop typing indicator
    if (_isTyping) {
      try {
        context.read<ChatService>().setTyping(widget.peerId, false);
      } catch (_) {}
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-mark as read when returning to chat
      context.read<ChatService>().markAsRead(widget.peerId);
    }
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    context.read<ChatService>().sendMessage(widget.peerId, text);
    _messageController.clear();
    _stopTyping();

    // Scroll to bottom
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 60,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onTextChanged(String text) {
    final hasContent = text.trim().isNotEmpty;
    if (hasContent != _hasText) {
      setState(() => _hasText = hasContent);
    }

    if (text.isNotEmpty && !_isTyping) {
      _isTyping = true;
      context.read<ChatService>().setTyping(widget.peerId, true);
    }

    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), _stopTyping);
  }

  void _stopTyping() {
    if (_isTyping) {
      _isTyping = false;
      context.read<ChatService>().setTyping(widget.peerId, false);
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 60,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Handle media inserted from keyboard (GIFs, stickers from Gboard etc.)
  void _handleKeyboardMedia(KeyboardInsertedContent content) {
    debugPrint('[ChatScreen] Keyboard media: ${content.mimeType}, hasData: ${content.hasData}');

    if (content.hasData) {
      // Keyboard sent raw bytes — determine type from MIME
      final isGif = content.mimeType == 'image/gif';
      final mediaType = isGif ? 'gif' : 'sticker';
      final ext = isGif ? 'gif' : 'png';
      final fileName = '${mediaType}_${DateTime.now().millisecondsSinceEpoch}.$ext';

      context.read<ChatService>().sendKeyboardMedia(
        widget.peerId,
        content.data!,
        fileName,
        mediaType,
      );
      _scrollToBottom();
    } else if (content.uri != null) {
      // Keyboard sent a URI — send as image media
      final isGif = content.mimeType == 'image/gif';
      final mediaType = isGif ? 'gif' : 'sticker';
      context.read<ChatService>().sendMediaMessage(
        widget.peerId,
        content.uri!,
        '',
        mediaType: mediaType,
      );
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = context.read<AuthManager>().userId ?? '';

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0A0A0C),
              Color(0xFF160A0A),
              Color(0xFF0A0A0C),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // App bar
              _buildAppBar(),
              const ConnectionBanner(),

              // Messages
              Expanded(
                child: Consumer<ChatService>(
                  builder: (context, chatService, _) {
                    final messages = chatService.getMessages(widget.peerId);

                    // Mark as read when new messages appear
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      chatService.markAsRead(widget.peerId);
                    });

                    if (messages.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                shape: BoxShape.rectangle,
                                borderRadius: BorderRadius.circular(8),
                                color: const Color(0xFF141416),
                                border: Border.all(
                                  color: const Color(0xFF8B0000).withOpacity(0.3),
                                ),
                              ),
                              child: const Icon(
                                Icons.security_rounded,
                                size: 40,
                                color: Color(0xFF8B0000),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'S E C U R E   M E S S A G I N G',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF8B0000),
                                letterSpacing: 2,
                              ),
                            ),
                            const SizedBox(height: 4),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final msg = messages[index];
                        return MessageBubble(
                          message: msg,
                          isSentByMe: msg.senderId == currentUserId,
                        );
                      },
                    );
                  },
                ),
              ),

              // Typing indicator
              Consumer<ChatService>(
                builder: (context, chatService, _) {
                  if (chatService.isTyping(widget.peerId)) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 4),
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          _buildDot(0),
                          _buildDot(1),
                          _buildDot(2),
                          const SizedBox(width: 6),
                          Text(
                            '${widget.peerId} is typing',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.white38,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),

              // Input bar / Voice recorder
              if (_isRecording)
                VoiceRecorderWidget(
                  onRecordingComplete: (result) {
                    setState(() => _isRecording = false);
                    context.read<ChatService>().sendVoiceMessage(
                      widget.peerId,
                      result.filePath,
                      result.durationMs,
                    );
                    // Scroll to bottom
                    Future.delayed(const Duration(milliseconds: 100), () {
                      if (_scrollController.hasClients) {
                        _scrollController.animateTo(
                          _scrollController.position.maxScrollExtent + 60,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                      }
                    });
                  },
                  onCancel: () => setState(() => _isRecording = false),
                )
              else
                _buildInputBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0C).withOpacity(0.9),
        border: Border(
          bottom: BorderSide(
            color: const Color(0xFF8B0000).withOpacity(0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(
              Icons.arrow_back_ios_rounded,
              color: Colors.white70,
              size: 20,
            ),
          ),
          // Avatar
          Consumer<ChatService>(
            builder: (context, chatService, _) {
              final convData = chatService.conversations.firstWhere(
                  (c) => c.peerId == widget.peerId,
                  orElse: () => ConversationModel(peerId: widget.peerId));
              return Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.rectangle,
                  borderRadius: BorderRadius.circular(4),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4A0000), Color(0xFF8B0000)],
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: convData.peerProfilePictureUrl.isNotEmpty
                      ? Image.network(
                          '${AppConstants.serverUrl}${convData.peerProfilePictureUrl}',
                          fit: BoxFit.cover,
                          headers: const {'ngrok-skip-browser-warning': 'true'},
                          errorBuilder: (ctx, err, stack) => Center(
                            child: Text(
                              widget.peerId.isNotEmpty ? widget.peerId[0].toUpperCase() : '?',
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                        )
                      : Center(
                          child: Text(
                            widget.peerId.isNotEmpty ? widget.peerId[0].toUpperCase() : '?',
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                ),
              );
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UserProfileScreen(userId: widget.peerId),
                  ),
                );
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.peerId,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(
                        Icons.lock,
                        size: 10,
                        color: Color(0xFF8B0000),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Secure',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: const Color(0xFF8B0000),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0C),
        border: Border(
          top: BorderSide(
            color: const Color(0xFF8B0000).withOpacity(0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          // Attachment button
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: const Color(0xFF141416),
            ),
            child: IconButton(
              onPressed: _showMediaPicker,
              icon: const Icon(Icons.attach_file_rounded,
                  color: Color(0xFF8B0000), size: 20),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF141416),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF8B0000).withOpacity(0.2)),
              ),
              child: TextField(
                controller: _messageController,
                onChanged: _onTextChanged,
                onSubmitted: (_) => _sendMessage(),
                enableInteractiveSelection: false,
                contentInsertionConfiguration: ContentInsertionConfiguration(
                  allowedMimeTypes: const ['image/gif', 'image/png', 'image/jpeg', 'image/webp'],
                  onContentInserted: _handleKeyboardMedia,
                ),
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 15,
                ),
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  hintStyle: GoogleFonts.inter(color: Colors.white30),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                maxLines: null,
              ),
            ),
          ),
          const SizedBox(width: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
            child: _hasText
                ? Container(
                    key: const ValueKey('send'),
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF8B0000), Color(0xFF4A0000)],
                      ),
                    ),
                    child: IconButton(
                      onPressed: _sendMessage,
                      icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                    ),
                  )
                : Container(
                    key: const ValueKey('mic'),
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF8B0000), Color(0xFF4A0000)],
                      ),
                    ),
                    child: IconButton(
                      onPressed: () => setState(() => _isRecording = true),
                      icon: const Icon(Icons.mic_rounded, color: Colors.white, size: 22),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _showMediaPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141416),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B0000).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.photo_rounded,
                      color: Color(0xFF8B0000)),
                ),
                title: Text('Photo',
                    style: GoogleFonts.inter(
                        color: Colors.white, fontWeight: FontWeight.w500)),
                subtitle: Text('Send a photo from gallery',
                    style: GoogleFonts.inter(
                        color: Colors.white38, fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndSendMedia(ImageSource.gallery, isVideo: false);
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B0000).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.videocam_rounded,
                      color: Color(0xFF8B0000)),
                ),
                title: Text('Video',
                    style: GoogleFonts.inter(
                        color: Colors.white, fontWeight: FontWeight.w500)),
                subtitle: Text('Send a video from gallery',
                    style: GoogleFonts.inter(
                        color: Colors.white38, fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndSendMedia(ImageSource.gallery, isVideo: true);
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B0000).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.camera_alt_rounded,
                      color: Color(0xFF8B0000)),
                ),
                title: Text('Camera',
                    style: GoogleFonts.inter(
                        color: Colors.white, fontWeight: FontWeight.w500)),
                subtitle: Text('Take a photo with camera',
                    style: GoogleFonts.inter(
                        color: Colors.white38, fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndSendMedia(ImageSource.camera, isVideo: false);
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B0000).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.insert_drive_file_rounded,
                      color: Color(0xFF8B0000)),
                ),
                title: Text('Document',
                    style: GoogleFonts.inter(
                        color: Colors.white, fontWeight: FontWeight.w500)),
                subtitle: Text('Send a document or file',
                    style: GoogleFonts.inter(
                        color: Colors.white38, fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndSendFile();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndSendFile() async {
    final result = await FilePicker.platform.pickFiles(withData: kIsWeb);
    if (result == null || (result.files.single.path == null && !kIsWeb)) return;
    if (!mounted) return;

    final file = File(result.files.single.path!);
    final originalName = result.files.single.name;

    final ext = originalName.split('.').last.toLowerCase();
    String detectedType = 'file';
    if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) detectedType = 'image';
    if (['mp4', 'mov', 'avi', 'mkv'].contains(ext)) detectedType = 'video';

    final caption = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => MediaPreviewScreen(
          path: file.path,
          mediaType: detectedType,
          originalName: originalName,
          fileSize: result.files.single.size,
          fileBytes: kIsWeb ? result.files.single.bytes : null,
        ),
      ),
    );

    if (caption != null && mounted) {
      context.read<ChatService>().sendMediaMessage(
        widget.peerId, 
        file.path, 
        caption,
        fileBytes: kIsWeb ? result.files.single.bytes : null,
        fileName: originalName,
        mediaType: detectedType,
      );
    }
  }

  Future<void> _pickAndSendMedia(ImageSource source,
      {required bool isVideo}) async {
    final picker = ImagePicker();
    XFile? file;

    if (isVideo) {
      file = await picker.pickVideo(source: source);
    } else {
      file = await picker.pickImage(source: source, imageQuality: 85);
    }

    if (file == null) return;
    if (!mounted) return;

    final mediaFile = File(file.path);
    final originalName = file.name;

    final isWeb = kIsWeb;
    Uint8List? bytes;
    if (isWeb) {
      bytes = await file.readAsBytes();
    }

    final caption = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => MediaPreviewScreen(
          path: file!.path,
          mediaType: isVideo ? 'video' : 'image',
          originalName: originalName,
          fileBytes: bytes,
        ),
      ),
    );

    if (caption != null && mounted) {
      context.read<ChatService>().sendMediaMessage(
        widget.peerId, 
        file!.path, 
        caption,
        fileBytes: bytes,
        fileName: originalName,
        mediaType: isVideo ? 'video' : 'image',
      );
    }
  }

  Widget _buildDot(int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 600 + (index * 200)),
      builder: (context, value, child) {
        return Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFFF1E1E).withOpacity(0.3 + (value * 0.4)),
          ),
        );
      },
    );
  }
}
