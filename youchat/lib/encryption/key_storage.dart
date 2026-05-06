import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

/// Implements Signal Protocol store interfaces backed by flutter_secure_storage.
/// All private keys are stored in the platform's secure enclave (Keychain/Keystore).
class SecureKeyStorage implements IdentityKeyStore, PreKeyStore, SignedPreKeyStore, SessionStore {
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  static const String _prefix = 'signal_';
  IdentityKeyPair? _identityKeyPair;
  int? _localRegistrationId;

  // ==================== Identity Key Store ====================

  @override
  Future<IdentityKeyPair> getIdentityKeyPair() async {
    if (_identityKeyPair != null) return _identityKeyPair!;

    final data = await _storage.read(key: '${_prefix}identity_key_pair');
    if (data != null) {
      final bytes = base64Decode(data);
      _identityKeyPair = IdentityKeyPair.fromSerialized(Uint8List.fromList(bytes));
      return _identityKeyPair!;
    }
    throw StateError('Identity key pair not found');
  }

  @override
  Future<int> getLocalRegistrationId() async {
    if (_localRegistrationId != null) return _localRegistrationId!;

    final data = await _storage.read(key: '${_prefix}registration_id');
    if (data != null) {
      _localRegistrationId = int.parse(data);
      return _localRegistrationId!;
    }
    throw StateError('Registration ID not found');
  }

  @override
  Future<bool> isTrustedIdentity(SignalProtocolAddress address,
      IdentityKey? identityKey, Direction? direction) async {
    if (identityKey == null) return false;

    final stored = await _storage.read(
        key: '${_prefix}trusted_identity_${address.getName()}');
    if (stored == null) return true; // Trust on first use (TOFU)

    final storedKey = IdentityKey.fromBytes(Uint8List.fromList(base64Decode(stored)), 0);
    return storedKey.getFingerprint() == identityKey.getFingerprint();
  }

  @override
  Future<bool> saveIdentity(
      SignalProtocolAddress address, IdentityKey? identityKey) async {
    if (identityKey == null) return false;

    final existing = await _storage.read(
        key: '${_prefix}trusted_identity_${address.getName()}');

    await _storage.write(
      key: '${_prefix}trusted_identity_${address.getName()}',
      value: base64Encode(identityKey.serialize()),
    );

    return existing != null; // true = key was replaced
  }

  @override
  Future<IdentityKey?> getIdentity(SignalProtocolAddress address) async {
    final data = await _storage.read(
        key: '${_prefix}trusted_identity_${address.getName()}');
    if (data != null) {
      return IdentityKey.fromBytes(Uint8List.fromList(base64Decode(data)), 0);
    }
    return null;
  }

  // ==================== Pre Key Store ====================

  @override
  Future<PreKeyRecord> loadPreKey(int preKeyId) async {
    final data = await _storage.read(key: '${_prefix}pre_key_$preKeyId');
    if (data != null) {
      return PreKeyRecord.fromBuffer(Uint8List.fromList(base64Decode(data)));
    }
    throw InvalidKeyIdException('PreKey $preKeyId not found');
  }

  @override
  Future<void> storePreKey(int preKeyId, PreKeyRecord record) async {
    await _storage.write(
      key: '${_prefix}pre_key_$preKeyId',
      value: base64Encode(record.serialize()),
    );
  }

  @override
  Future<bool> containsPreKey(int preKeyId) async {
    final data = await _storage.read(key: '${_prefix}pre_key_$preKeyId');
    return data != null;
  }

  @override
  Future<void> removePreKey(int preKeyId) async {
    await _storage.delete(key: '${_prefix}pre_key_$preKeyId');
  }

  // ==================== Signed Pre Key Store ====================

  @override
  Future<SignedPreKeyRecord> loadSignedPreKey(int signedPreKeyId) async {
    final data =
        await _storage.read(key: '${_prefix}signed_pre_key_$signedPreKeyId');
    if (data != null) {
      return SignedPreKeyRecord.fromSerialized(
          Uint8List.fromList(base64Decode(data)));
    }
    throw InvalidKeyIdException('Signed PreKey $signedPreKeyId not found');
  }

  @override
  Future<List<SignedPreKeyRecord>> loadSignedPreKeys() async {
    final data = await _storage.read(key: '${_prefix}signed_pre_key_current_id');
    if (data != null) {
      final id = int.parse(data);
      final record = await loadSignedPreKey(id);
      return [record];
    }
    return [];
  }

  @override
  Future<void> storeSignedPreKey(
      int signedPreKeyId, SignedPreKeyRecord record) async {
    await _storage.write(
      key: '${_prefix}signed_pre_key_$signedPreKeyId',
      value: base64Encode(record.serialize()),
    );
    await _storage.write(
      key: '${_prefix}signed_pre_key_current_id',
      value: signedPreKeyId.toString(),
    );
  }

  @override
  Future<bool> containsSignedPreKey(int signedPreKeyId) async {
    final data =
        await _storage.read(key: '${_prefix}signed_pre_key_$signedPreKeyId');
    return data != null;
  }

  @override
  Future<void> removeSignedPreKey(int signedPreKeyId) async {
    await _storage.delete(key: '${_prefix}signed_pre_key_$signedPreKeyId');
  }

  // ==================== Session Store ====================

  @override
  Future<SessionRecord> loadSession(SignalProtocolAddress address) async {
    final data = await _storage.read(
        key: '${_prefix}session_${address.getName()}_${address.getDeviceId()}');
    if (data != null) {
      return SessionRecord.fromSerialized(
          Uint8List.fromList(base64Decode(data)));
    }
    return SessionRecord();
  }

  @override
  Future<List<int>> getSubDeviceSessions(String name) async {
    return [1];
  }

  @override
  Future<void> storeSession(
      SignalProtocolAddress address, SessionRecord record) async {
    await _storage.write(
      key: '${_prefix}session_${address.getName()}_${address.getDeviceId()}',
      value: base64Encode(record.serialize()),
    );
  }

  @override
  Future<bool> containsSession(SignalProtocolAddress address) async {
    final data = await _storage.read(
        key: '${_prefix}session_${address.getName()}_${address.getDeviceId()}');
    return data != null;
  }

  @override
  Future<void> deleteSession(SignalProtocolAddress address) async {
    await _storage.delete(
        key: '${_prefix}session_${address.getName()}_${address.getDeviceId()}');
  }

  @override
  Future<void> deleteAllSessions(String name) async {
    await _storage.delete(key: '${_prefix}session_${name}_1');
  }

  // ==================== Key Management Helpers ====================

  Future<void> saveIdentityKeyPair(IdentityKeyPair keyPair) async {
    _identityKeyPair = keyPair;
    await _storage.write(
      key: '${_prefix}identity_key_pair',
      value: base64Encode(keyPair.serialize()),
    );
  }

  Future<void> saveRegistrationId(int registrationId) async {
    _localRegistrationId = registrationId;
    await _storage.write(
      key: '${_prefix}registration_id',
      value: registrationId.toString(),
    );
  }

  Future<bool> hasIdentityKeyPair() async {
    return await _storage.read(key: '${_prefix}identity_key_pair') != null;
  }

  /// Wipe all keys — used on logout/account deletion
  Future<void> clearAll() async {
    await _storage.deleteAll();
    _identityKeyPair = null;
    _localRegistrationId = null;
  }
}
