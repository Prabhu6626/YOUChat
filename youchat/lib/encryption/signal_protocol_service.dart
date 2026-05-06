import 'dart:convert';
import 'dart:typed_data';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'key_storage.dart';

/// Core Signal Protocol encryption service.
/// Handles key generation, session establishment, message encryption/decryption.
/// Implements the Double Ratchet algorithm for perfect forward secrecy.
class SignalProtocolService {
  final SecureKeyStorage _store = SecureKeyStorage();

  SecureKeyStorage get store => _store;

  /// Check if encryption keys have been generated.
  Future<bool> get hasKeys => _store.hasIdentityKeyPair();

  /// Initialize the Signal Protocol — generate all required keys.
  /// Called once during registration.
  Future<Map<String, dynamic>> generateKeys() async {
    // Generate identity key pair
    final identityKeyPair = generateIdentityKeyPair();
    await _store.saveIdentityKeyPair(identityKeyPair);

    // Generate registration ID
    final registrationId = generateRegistrationId(false);
    await _store.saveRegistrationId(registrationId);

    // Generate signed pre-key
    final signedPreKey = generateSignedPreKey(identityKeyPair, 0);
    await _store.storeSignedPreKey(signedPreKey.id, signedPreKey);

    // Generate batch of one-time pre-keys
    final preKeys = generatePreKeys(0, 100);
    for (final preKey in preKeys) {
      await _store.storePreKey(preKey.id, preKey);
    }

    // Return public keys to upload to server
    return _buildKeyBundle(
      identityKeyPair: identityKeyPair,
      registrationId: registrationId,
      signedPreKey: signedPreKey,
      preKeys: preKeys,
    );
  }

  /// Build the public key bundle for upload to server.
  Map<String, dynamic> _buildKeyBundle({
    required IdentityKeyPair identityKeyPair,
    required int registrationId,
    required SignedPreKeyRecord signedPreKey,
    required List<PreKeyRecord> preKeys,
  }) {
    return {
      'identityPublicKey':
          base64Encode(identityKeyPair.getPublicKey().serialize()),
      'registrationId': registrationId,
      'signedPreKey': {
        'keyId': signedPreKey.id,
        'publicKey':
            base64Encode(signedPreKey.getKeyPair().publicKey.serialize()),
        'signature': base64Encode(signedPreKey.signature),
      },
      'preKeys': preKeys.map((pk) {
        return {
          'keyId': pk.id,
          'publicKey': base64Encode(pk.getKeyPair().publicKey.serialize()),
        };
      }).toList(),
    };
  }

  /// Establish a session with a remote user using their pre-key bundle.
  /// Called before sending the first message to a new contact.
  Future<void> establishSession(
      String remoteUserId, Map<String, dynamic> remoteBundleJson) async {
    final remoteAddress = SignalProtocolAddress(remoteUserId, 1);

    final registrationId = remoteBundleJson['registrationId'] as int;
    final identityPublicKey = IdentityKey.fromBytes(
      Uint8List.fromList(
          base64Decode(remoteBundleJson['identityPublicKey'] as String)),
      0,
    );

    final signedPreKeyData =
        remoteBundleJson['signedPreKey'] as Map<String, dynamic>;
    final signedPreKeyPublic = Curve.decodePoint(
      Uint8List.fromList(
          base64Decode(signedPreKeyData['publicKey'] as String)),
      0,
    );

    ECPublicKey? preKeyPublic;
    int? preKeyId;
    if (remoteBundleJson['preKey'] != null) {
      final preKeyData = remoteBundleJson['preKey'] as Map<String, dynamic>;
      preKeyPublic = Curve.decodePoint(
        Uint8List.fromList(
            base64Decode(preKeyData['publicKey'] as String)),
        0,
      );
      preKeyId = preKeyData['keyId'] as int;
    }

    final preKeyBundle = PreKeyBundle(
      registrationId,
      1, // deviceId
      preKeyId ?? 0,
      preKeyPublic,
      signedPreKeyData['keyId'] as int,
      signedPreKeyPublic,
      Uint8List.fromList(
          base64Decode(signedPreKeyData['signature'] as String)),
      identityPublicKey,
    );

    final sessionBuilder = SessionBuilder(_store, _store, _store, _store, remoteAddress);
    await sessionBuilder.processPreKeyBundle(preKeyBundle);
  }

  /// Check if a session already exists with a remote user.
  Future<bool> hasSession(String remoteUserId) async {
    final address = SignalProtocolAddress(remoteUserId, 1);
    return await _store.containsSession(address);
  }

  /// Encrypt a plaintext message for a specific recipient.
  /// Returns a map with 'type' and 'body' (base64 encoded ciphertext).
  Future<Map<String, dynamic>> encryptMessage(
      String recipientUserId, String plaintext) async {
    final address = SignalProtocolAddress(recipientUserId, 1);
    final cipher = SessionCipher(_store, _store, _store, _store, address);

    final ciphertext = await cipher.encrypt(
      Uint8List.fromList(utf8.encode(plaintext)),
    );

    return {
      'type': ciphertext.getType(),
      'body': base64Encode(ciphertext.serialize()),
    };
  }

  /// Decrypt a received ciphertext message.
  /// Returns the plaintext string.
  Future<String> decryptMessage(
      String senderUserId, Map<String, dynamic> cipherData) async {
    final address = SignalProtocolAddress(senderUserId, 1);
    final cipher = SessionCipher(_store, _store, _store, _store, address);

    final type = cipherData['type'] as int;
    final body = base64Decode(cipherData['body'] as String);

    Uint8List plaintext;
    if (type == CiphertextMessage.prekeyType) {
      plaintext = await cipher.decrypt(
        PreKeySignalMessage(Uint8List.fromList(body)),
      );
    } else {
      plaintext = await cipher.decryptFromSignal(
        SignalMessage.fromSerialized(Uint8List.fromList(body)),
      );
    }

    return utf8.decode(plaintext);
  }

  /// Clear all sessions and keys (logout).
  Future<void> clearAll() async {
    await _store.clearAll();
  }
}
