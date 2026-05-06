const WebSocket = require('ws');
const jwt = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');
const DeletionEnforcer = require('./deletion');
const Group = require('../models/Group');
const PendingMessage = require('../models/PendingMessage');
const { sendOfflineNotification } = require('../services/fcm');
const logger = require('../utils/logger');

/**
 * WebSocket Connection Handler.
 * Manages real-time message relay between clients.
 * Supports both 1:1 and group messaging.
 * Server sees plaintext during transition.
 */
class WebSocketHandler {
  constructor(server) {
    this.wss = new WebSocket.Server({ server });
    // Map<userId, WebSocket>
    this.clients = new Map();
    // Map<messageId, { ciphertext, from, to, timestamp }> — in-memory only, 60s TTL
    this.pendingMessages = new Map();
    this.deletionEnforcer = new DeletionEnforcer();

    this.setupServer();
    this.startCleanupInterval();
  }

  setupServer() {
    this.wss.on('connection', (ws, req) => {
      this.handleConnection(ws, req);
    });

    logger.info('WebSocket server initialized');
  }

  /**
   * Handle new WebSocket connection.
   * Authenticates via JWT token in query string.
   */
  handleConnection(ws, req) {
    try {
      // Extract token from query string: ws://server?token=<jwt>
      const url = new URL(req.url, 'http://localhost');
      const token = url.searchParams.get('token');

      if (!token) {
        ws.close(4001, 'Authentication required');
        return;
      }

      let decoded;
      try {
        decoded = jwt.verify(token, process.env.JWT_SECRET);
      } catch (err) {
        ws.close(4001, 'Invalid token');
        return;
      }

      const userId = decoded.userId;

      // Close existing connection if any (single device only)
      if (this.clients.has(userId)) {
        const existing = this.clients.get(userId);
        existing.close(4002, 'Connected from another device');
      }

      // Register client
      this.clients.set(userId, ws);
      ws.userId = userId;
      ws.isAlive = true;

      logger.info(`Client connected: ${userId}`);

      // Send pending offline deletions
      const offlineDeletions = this.deletionEnforcer.getOfflineDeletions(userId);
      if (offlineDeletions.length > 0) {
        this.sendToClient(userId, {
          type: 'pending_deletions',
          messageIds: offlineDeletions,
        });
      }

      // Deliver pending messages from MongoDB
      this.deliverPendingMessages(userId);

      // Notify all users who have this user in a chat that they're online
      // (useful for delivery receipts of queued messages)
      this.broadcastOnlineStatus(userId, true);

      // Setup heartbeat
      ws.on('pong', () => {
        ws.isAlive = true;
      });

      // Handle incoming messages
      ws.on('message', (data) => {
        this.handleMessage(userId, data);
      });

      // Handle disconnect
      ws.on('close', () => {
        logger.info(`Client disconnected: ${userId}`);
        if (this.clients.get(userId) === ws) {
          this.clients.delete(userId);
        }
      });

      ws.on('error', (error) => {
        logger.error(`WebSocket error for ${userId}:`, error.message);
      });
    } catch (error) {
      logger.error('Connection handling error:', error.message);
      ws.close(4000, 'Server error');
    }
  }

  /**
   * Handle incoming WebSocket message.
   * Routes based on message type.
   */
  handleMessage(fromUserId, rawData) {
    try {
      const data = JSON.parse(rawData.toString());

      switch (data.type) {
        case 'ping':
          // App-level heartbeat — reply immediately to keep connection alive
          this.sendToClient(fromUserId, { type: 'pong' });
          // Also mark the connection as alive for the server-side heartbeat
          const pingWs = this.clients.get(fromUserId);
          if (pingWs) pingWs.isAlive = true;
          break;
        case 'message':
          this.handlePlaintextMessage(fromUserId, data);
          break;
        case 'read_receipt':
          this.handleReadReceipt(fromUserId, data);
          break;
        case 'delete_ack':
          this.handleDeleteAck(fromUserId, data);
          break;
        case 'typing_indicator':
          this.handleTypingIndicator(fromUserId, data);
          break;
        case 'delivery_ack':
          this.handleDeliveryAck(fromUserId, data);
          break;
        case 'get_missed_messages':
          this.deliverPendingMessages(fromUserId);
          break;
        // --- Group message types ---
        case 'group_message':
          this.handleGroupMessage(fromUserId, data);
          break;
        case 'group_read_receipt':
          this.handleGroupReadReceipt(fromUserId, data);
          break;
        case 'group_typing_indicator':
          this.handleGroupTypingIndicator(fromUserId, data);
          break;
        case 'delete_media':
          this.handleDeleteMedia(fromUserId, data);
          break;
        default:
          logger.warn(`Unknown message type: ${data.type}`);
      }
    } catch (error) {
      logger.error('Message handling error:', error.message);
    }
  }

  /**
   * Handle plaintext message relay (1:1).
   */
  handlePlaintextMessage(fromUserId, data) {
    const { to, content, messageId, mediaUrl, mediaType, originalName, encryptedKey, voiceDuration } = data;
    const msgId = messageId || uuidv4();

    if (!to || (!content && !mediaUrl)) {
      return;
    }

    const message = {
      type: 'message',
      messageId: msgId,
      from: fromUserId,
      content: content || '', // Plaintext or caption
      mediaUrl: mediaUrl || null,
      mediaType: mediaType || null,
      originalName: originalName || null,
      encryptedKey: encryptedKey || null,
      voiceDuration: voiceDuration || null,
      timestamp: Date.now(),
    };

    // Try to deliver immediately
    if (this.sendToClient(to, message)) {
      logger.debug(`Message relayed: ${fromUserId} -> ${to} (${msgId})`);
      // Notify sender that message was delivered
      this.sendToClient(fromUserId, {
        type: 'delivery_receipt',
        messageId: msgId,
      });
    } else {
      // Recipient offline — persist to MongoDB (24h TTL)
      this.savePendingMessage({
        messageId: msgId,
        from: fromUserId,
        to,
        type: 'message',
        content: content || '',
        mediaUrl: mediaUrl || null,
        mediaType: mediaType || null,
        originalName: originalName || null,
        encryptedKey: encryptedKey || null,
        voiceDuration: voiceDuration || null,
        timestamp: message.timestamp,
      });
      sendOfflineNotification(to, fromUserId, 'message');
      logger.debug(`Message saved to MongoDB for offline user: ${to} (${msgId})`);
    }

    // Confirm to sender that server received it
    this.sendToClient(fromUserId, {
      type: 'message_sent',
      messageId: msgId,
      timestamp: message.timestamp,
    });
  }

  /**
   * Handle group message — fan out to all members except sender.
   */
  async handleGroupMessage(fromUserId, data) {
    const { groupId, content, messageId, mediaUrl, mediaType, originalName, encryptedKey, voiceDuration } = data;
    const msgId = messageId || uuidv4();

    if (!groupId || (!content && !mediaUrl)) {
      return;
    }

    // Look up group members from DB
    let group;
    try {
      group = await Group.findOne({ groupId });
    } catch (err) {
      logger.error(`Group lookup error: ${err.message}`);
      return;
    }

    if (!group) {
      logger.warn(`Group not found: ${groupId}`);
      this.sendToClient(fromUserId, {
        type: 'error',
        message: 'Group not found.',
      });
      return;
    }

    if (!group.members.includes(fromUserId)) {
      logger.warn(`User ${fromUserId} is not a member of group ${groupId}`);
      return;
    }

    // Check if sendMessages is restricted to admins
    const settings = group.settings || { sendMessages: 'all' };
    if (settings.sendMessages === 'admins') {
      const isAdmin = group.admins && group.admins.includes(fromUserId);
      if (!isAdmin) {
        logger.warn(`User ${fromUserId} is not an admin and cannot send messages to group ${groupId}`);
        this.sendToClient(fromUserId, {
          type: 'error',
          message: 'Only admins can send messages in this group.',
        });
        return;
      }
    }

    const message = {
      type: 'group_message',
      messageId: msgId,
      groupId,
      from: fromUserId,
      content: content || '',
      mediaUrl: mediaUrl || null,
      mediaType: mediaType || null,
      originalName: originalName || null,
      encryptedKey: encryptedKey || null,
      voiceDuration: voiceDuration || null,
      timestamp: Date.now(),
    };

    // Fan out to all members except sender
    let deliveredCount = 0;
    for (const memberId of group.members) {
      if (memberId === fromUserId) continue;

      if (this.sendToClient(memberId, message)) {
        deliveredCount++;
      } else {
        // Persist for offline member in MongoDB
        this.savePendingMessage({
          messageId: msgId,
          from: fromUserId,
          to: memberId,
          type: 'group_message',
          groupId,
          content: content || '',
          mediaUrl: mediaUrl || null,
          mediaType: mediaType || null,
          originalName: originalName || null,
          encryptedKey: encryptedKey || null,
          voiceDuration: voiceDuration || null,
          timestamp: message.timestamp,
        });
        sendOfflineNotification(memberId, fromUserId, 'group_message', groupId);
      }
    }

    logger.debug(`Group message relayed: ${fromUserId} -> ${groupId} (${msgId}) [${deliveredCount}/${group.members.length - 1} online]`);

    // Confirm to sender
    this.sendToClient(fromUserId, {
      type: 'message_sent',
      messageId: msgId,
      groupId,
      timestamp: message.timestamp,
    });
  }

  /**
   * Handle read receipt — triggers deletion timer (1:1).
   */
  handleReadReceipt(fromUserId, data) {
    const { messageId, to } = data;

    if (!messageId || !to) return;

    // Forward read receipt to sender
    this.sendToClient(to, {
      type: 'read_receipt',
      messageId,
      from: fromUserId,
    });

    // Start server-side 7-second deletion timer
    this.deletionEnforcer.startTimer(messageId, to, fromUserId, (msgId, senderId, receiverId) => {
      this.forceDelete(msgId, senderId, receiverId);
    });

    logger.debug(`Read receipt: ${fromUserId} read ${messageId}`);
  }

  /**
   * Handle group read receipt — per-user deletion.
   * Only starts a deletion timer for the specific reader's copy.
   */
  handleGroupReadReceipt(fromUserId, data) {
    const { messageId, groupId, senderId } = data;

    if (!messageId || !groupId) return;

    // Notify the original sender that this user read the message
    if (senderId) {
      this.sendToClient(senderId, {
        type: 'group_read_receipt',
        messageId,
        groupId,
        from: fromUserId,
      });
    }

    // Start per-user deletion timer — only deletes for this reader
    this.deletionEnforcer.startGroupTimer(messageId, fromUserId, (msgId, readerId) => {
      this.forceDeleteForUser(msgId, readerId);
    });

    logger.debug(`Group read receipt: ${fromUserId} read ${messageId} in ${groupId}`);
  }

  /**
   * Force delete a message from both clients (1:1).
   * Called when server-side 7-second timer expires.
   */
  forceDelete(messageId, senderId, receiverId) {
    const deleteMsg = {
      type: 'force_delete',
      messageId,
      timestamp: Date.now(),
    };

    // Send to sender
    if (!this.sendToClient(senderId, deleteMsg)) {
      this.deletionEnforcer.addOfflineDeletion(senderId, messageId);
    }

    // Send to receiver
    if (!this.sendToClient(receiverId, deleteMsg)) {
      this.deletionEnforcer.addOfflineDeletion(receiverId, messageId);
    }

    // Remove from pending messages
    this.pendingMessages.delete(messageId);

    logger.debug(`Force delete sent: ${messageId}`);
  }

  /**
   * Force delete a message for a single user (group per-user deletion).
   */
  forceDeleteForUser(messageId, userId) {
    const deleteMsg = {
      type: 'force_delete',
      messageId,
      timestamp: Date.now(),
    };

    if (!this.sendToClient(userId, deleteMsg)) {
      this.deletionEnforcer.addOfflineDeletion(userId, messageId);
    }

    logger.debug(`Group force delete sent: ${messageId} for user ${userId}`);
  }

  /**
   * Handle delete acknowledgment from client.
   */
  handleDeleteAck(fromUserId, data) {
    const { messageId } = data;
    if (messageId) {
      this.deletionEnforcer.acknowledgeDelete(messageId, fromUserId);
    }
  }

  /**
   * Handle typing indicator relay (1:1).
   */
  handleTypingIndicator(fromUserId, data) {
    const { to, isTyping } = data;
    if (!to) return;

    this.sendToClient(to, {
      type: 'typing_indicator',
      from: fromUserId,
      isTyping: !!isTyping,
    });
  }

  /**
   * Handle group typing indicator — broadcast to all members except sender.
   */
  async handleGroupTypingIndicator(fromUserId, data) {
    const { groupId, isTyping } = data;
    if (!groupId) return;

    let group;
    try {
      group = await Group.findOne({ groupId });
    } catch (err) {
      return;
    }

    if (!group || !group.members.includes(fromUserId)) return;

    for (const memberId of group.members) {
      if (memberId === fromUserId) continue;
      this.sendToClient(memberId, {
        type: 'group_typing_indicator',
        groupId,
        from: fromUserId,
        isTyping: !!isTyping,
      });
    }
  }
  /**
   * Broadcast online status to connected clients.
   * Lightweight — just tells other connected users this user is online.
   */
  broadcastOnlineStatus(userId, isOnline) {
    // Notify all connected clients (they can filter by chat partner)
    for (const [clientId, ws] of this.clients.entries()) {
      if (clientId !== userId && ws.readyState === WebSocket.OPEN) {
        try {
          ws.send(JSON.stringify({
            type: 'user_status',
            userId,
            isOnline,
          }));
        } catch (_) {}
      }
    }
  }

  /**
   * Send a message to a connected client.
   * @returns {boolean} true if message was sent, false if client is offline.
   */
  sendToClient(userId, data) {
    const client = this.clients.get(userId);
    if (client && client.readyState === WebSocket.OPEN) {
      client.send(JSON.stringify(data));
      return true;
    }
    return false;
  }

  /**
   * Save a message to MongoDB for offline delivery.
   */
  async savePendingMessage(msgData) {
    try {
      await PendingMessage.create(msgData);
    } catch (err) {
      logger.error(`Failed to save pending message: ${err.message}`);
    }
  }

  /**
   * Handle delivery acknowledgment — delete from MongoDB + notify sender.
   */
  async handleDeliveryAck(fromUserId, data) {
    const { messageId, senderId } = data;
    if (!messageId) return;

    try {
      await PendingMessage.deleteOne({ messageId, to: fromUserId });
    } catch (err) {
      logger.error(`Failed to delete delivered message: ${err.message}`);
    }

    // Notify original sender that message was delivered
    if (senderId) {
      this.sendToClient(senderId, {
        type: 'delivery_receipt',
        messageId,
      });
    }
  }

  /**
   * Deliver all pending messages from MongoDB to a newly connected user.
   */
  async deliverPendingMessages(userId) {
    try {
      const pending = await PendingMessage.find({ to: userId }).sort({ createdAt: 1 }).lean();
      if (pending.length === 0) return;

      logger.info(`Delivering ${pending.length} pending messages to ${userId}`);

      for (const msg of pending) {
        const payload = {
          type: msg.type || 'message',
          messageId: msg.messageId,
          from: msg.from,
          content: msg.content || '',
          mediaUrl: msg.mediaUrl || null,
          mediaType: msg.mediaType || null,
          originalName: msg.originalName || null,
          encryptedKey: msg.encryptedKey || null,
          voiceDuration: msg.voiceDuration || null,
          timestamp: msg.timestamp,
        };

        if (msg.type === 'group_message') {
          payload.groupId = msg.groupId;
        }

        if (this.sendToClient(userId, payload)) {
          // Delete from MongoDB after successful delivery
          await PendingMessage.deleteOne({ _id: msg._id });
          logger.debug(`Pending message delivered: ${msg.messageId} -> ${userId}`);

          // Notify original sender that their message was delivered
          this.sendToClient(msg.from, {
            type: 'delivery_receipt',
            messageId: msg.messageId,
          });
        }
      }
    } catch (err) {
      logger.error(`Failed to deliver pending messages: ${err.message}`);
    }
  }

  /**
   * Cleanup expired pending messages every 30 seconds.
   */
  startCleanupInterval() {
    // Cleanup expired messages every 30s
    setInterval(() => {
      const now = Date.now();
      let cleaned = 0;
      for (const [msgId, msg] of this.pendingMessages.entries()) {
        if (msg.expiry <= now) {
          this.pendingMessages.delete(msgId);
          cleaned++;
        }
      }
      if (cleaned > 0) {
        logger.debug(`Cleaned ${cleaned} expired pending messages`);
      }
    }, 30000);

    // Server-side heartbeat ping — runs every 60s
    // Very tolerant of mobile clients: allows 5 missed pongs (5 min grace)
    // Mobile apps can't respond to WS pongs when backgrounded by the OS
    setInterval(() => {
      for (const [userId, ws] of this.clients.entries()) {
        if (!ws.isAlive) {
          if (ws._missedPongs === undefined) ws._missedPongs = 0;
          ws._missedPongs++;
          // Only terminate after 5 missed pongs (5 minutes of no response)
          if (ws._missedPongs >= 5) {
            ws.terminate();
            this.clients.delete(userId);
            logger.debug(`Terminated stale connection: ${userId} (missed ${ws._missedPongs} pongs)`);
            continue;
          }
        } else {
          ws._missedPongs = 0;
        }
        ws.isAlive = false;
        ws.ping();
      }
    }, 60000);
  }

  /**
   * Complete Zero-Knowledge E2EE scrub from Host.
   * Hard-deletes the AES encrypted media blob from server harddrive.
   */
  handleDeleteMedia(fromUserId, data) {
    try {
      const { mediaUrl } = data;
      if (!mediaUrl) return;

      const fs = require('fs');
      const path = require('path');
      
      const safeFilename = path.basename(mediaUrl.replace('/uploads/media/', ''));
      if (!safeFilename) return;

      const uploadDir = process.env.UPLOAD_DIR || './uploads';
      const targetPath = path.join(uploadDir, 'media', safeFilename);

      if (fs.existsSync(targetPath)) {
        fs.unlinkSync(targetPath);
        const logger = require('../utils/logger');
        logger.info(`E2EE Expiration: Hard-deleted secure blob ${safeFilename}`);
      }
    } catch (e) {
      const logger = require('../utils/logger');
      logger.error(`Media delete error: ${e.message}`);
    }
  }

  /**
   * Get server stats.
   */
  getStats() {
    return {
      connectedClients: this.clients.size,
      pendingMessages: this.pendingMessages.size,
      ...this.deletionEnforcer.getStats(),
    };
  }
}

module.exports = WebSocketHandler;
