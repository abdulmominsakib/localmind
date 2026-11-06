import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalApiConfiguration {
  const LocalApiConfiguration({this.port = 8000, this.lan = false});
  final int port;
  final bool lan;
}

class LocalApiConfigurationRepository {
  LocalApiConfigurationRepository(
    this._prefs, {
    this.storage = const FlutterSecureStorage(),
  });

  final SharedPreferences _prefs;
  final FlutterSecureStorage storage;

  static const _port = 'localApiPort';
  static const _lan = 'localApiLan';
  static const _key = 'localApiBearerKey';

  LocalApiConfiguration read() {
    final port = _prefs.getInt(_port);
    return LocalApiConfiguration(
      port: port != null && port >= 1024 && port <= 65535 ? port : 8000,
      lan: _prefs.getBool(_lan) ?? false,
    );
  }

  Future<void> save(LocalApiConfiguration config) async {
    await _prefs.setInt(_port, config.port);
    await _prefs.setBool(_lan, config.lan);
  }

  Future<String> key() async => await storage.read(key: _key) ?? rotateKey();

  Future<String> rotateKey() async {
    final random = Random.secure();
    final key =
        'lm_${base64UrlEncode(List.generate(32, (_) => random.nextInt(256))).replaceAll('=', '')}';
    await storage.write(key: _key, value: key);
    return key;
  }
}
