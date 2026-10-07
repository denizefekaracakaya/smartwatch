import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/models.dart';

enum AuthStatus { unknown, signedOut, signedIn }

class AuthState extends ChangeNotifier {
  AuthState(this.api) {
    api.onSessionExpired = () {
      if (status == AuthStatus.signedIn) _signOutLocally();
    };
  }

  final ApiClient api;
  AuthStatus status = AuthStatus.unknown;
  User? user;

  Future<void> bootstrap() async {
    try {
      user = await api.restoreSession();
    } on ApiException {
      user = null;
    }
    status = user == null ? AuthStatus.signedOut : AuthStatus.signedIn;
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    user = await api.login(email.trim(), password);
    status = AuthStatus.signedIn;
    notifyListeners();
  }

  String get serverUrl => api.baseUrl;

  /// Switches to another backend; only offered while signed out.
  Future<void> changeServer(String url) async {
    await api.setBaseUrl(url);
    await api.tokenStore.writeServerUrl(api.baseUrl);
    notifyListeners();
  }

  Future<void> register(String email, String password, String displayName) =>
      api.register(email.trim(), password, displayName.trim());

  Future<void> updateDisplayName(String name) async {
    user = await api.updateDisplayName(name.trim());
    notifyListeners();
  }

  Future<void> changePassword(String current, String next) async {
    user = await api.changePassword(current, next);
    notifyListeners();
  }

  Future<void> deleteAccount(String password) async {
    await api.deleteAccount(password);
    _signOutLocally();
  }

  Future<void> logout() async {
    await api.logout();
    _signOutLocally();
  }

  void _signOutLocally() {
    user = null;
    status = AuthStatus.signedOut;
    notifyListeners();
  }
}
