import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;

class EncryptedMediaPayload {
  final Uint8List encryptedBytes;
  final String keyBase64;

  EncryptedMediaPayload(this.encryptedBytes, this.keyBase64);
}

class MediaEncryptionService {
  /// Encrypt generic bytes before securely transmitting to unblinded host server
  static EncryptedMediaPayload encryptBytes(Uint8List rawBytes) {
    // Generate fresh Key and IV for every single upload (True Zero Knowledge)
    final keySource = encrypt.Key.fromSecureRandom(32);
    final ivSource = encrypt.IV.fromSecureRandom(16);
    
    final encrypter = encrypt.Encrypter(encrypt.AES(keySource, mode: encrypt.AESMode.cbc, padding: 'PKCS7'));
    
    // Scramble the payload
    final encrypted = encrypter.encryptBytes(rawBytes, iv: ivSource);
    
    // Distill key material into transport base64 
    final packedKey = '${keySource.base64}:${ivSource.base64}';
    
    return EncryptedMediaPayload(encrypted.bytes, packedKey);
  }

  /// Locally decrypt the downloaded payload locally inside secure memory zone
  static Uint8List decryptBytes(Uint8List encryptedData, String packedKey) {
    if (!packedKey.contains(':')) {
      throw Exception('Invalid Zero-Knowledge Key formatting');
    }
    
    final parts = packedKey.split(':');
    final keySource = encrypt.Key.fromBase64(parts[0]);
    final ivSource = encrypt.IV.fromBase64(parts[1]);
    
    final encrypter = encrypt.Encrypter(encrypt.AES(keySource, mode: encrypt.AESMode.cbc, padding: 'PKCS7'));
    
    final decryptedList = encrypter.decryptBytes(encrypt.Encrypted(encryptedData), iv: ivSource);
    return Uint8List.fromList(decryptedList);
  }

  /// Top-level helper for compute decryption
  static Uint8List decryptBytesCompute(Map<String, dynamic> args) {
    final encryptedData = args['encryptedData'] as Uint8List;
    final packedKey = args['packedKey'] as String;
    return decryptBytes(encryptedData, packedKey);
  }
}
