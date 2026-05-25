import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/api_service.dart';

const _kUrl = 'drilex_api_url';
const _kKey = 'drilex_api_key';

class AuthProvider extends ChangeNotifier {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  String? _apiUrl;
  String? _apiKey;
  bool _loading = true;
  ApiService? _service;

  String? get apiUrl => _apiUrl;
  String? get apiKey => _apiKey;
  bool get isLoading => _loading;
  bool get isAuthenticated => _apiUrl != null && _apiKey != null;
  ApiService? get apiService => _service;

  Future<void> load() async {
    _apiUrl = await _storage.read(key: _kUrl);
    _apiKey = await _storage.read(key: _kKey);
    if (_apiUrl != null && _apiKey != null) {
      _service = ApiService(baseUrl: _apiUrl!, apiKey: _apiKey!);
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> save(String url, String key) async {
    await _storage.write(key: _kUrl, value: url);
    await _storage.write(key: _kKey, value: key);
    _apiUrl = url;
    _apiKey = key;
    _service = ApiService(baseUrl: url, apiKey: key);
    notifyListeners();
  }

  Future<void> clear() async {
    await _storage.delete(key: _kUrl);
    await _storage.delete(key: _kKey);
    _apiUrl = null;
    _apiKey = null;
    _service = null;
    notifyListeners();
  }
}
