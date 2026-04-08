import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce/hive.dart';

class SecureStorageService {
  static const _storage = FlutterSecureStorage();
  static const _keyName = 'hive_encryption_key_v1';

  /// Returns the encryption key as a Uint8List.
  /// If no key exists, it generates a new one and saves it.
  static Future<Uint8List> getOrGenerateKey() async {
    final encryptionKeyString = await _storage.read(key: _keyName);
    
    if (encryptionKeyString == null) {
      final key = Hive.generateSecureKey();
      await _storage.write(
        key: _keyName,
        value: base64UrlEncode(key),
      );
      return Uint8List.fromList(key);
    }

    return base64Url.decode(encryptionKeyString);
  }

  /// Clears the encryption key. 
  /// CAUTION: This will make all existing encrypted data unreadable.
  static Future<void> clearKey() async {
    await _storage.delete(key: _keyName);
  }
}
