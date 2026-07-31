// providers/auth_provider.dart
import 'package:flutter/foundation.dart';
import '../models/user.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  User? _user;
  bool _isLoading = false;
  String? _error;

  // ─── Getters ───
  User? get user => _user;
  bool get isLoggedIn => _user != null && _user!.token.isNotEmpty;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // ─── CHECK LOGIN STATUS ───
  Future<void> checkLoginStatus() async {
    _isLoading = true;
    notifyListeners();

    _user = await _authService.getStoredUser();

    // Si token existe, charger le profil frais
    if (_user != null && _user!.token.isNotEmpty) {
      try {
        final freshUser = await _authService.getProfile();
        _user = freshUser;
        await _authService.saveUserData(
          _user!,
        ); // Sauvegarder les données fraîches
      } catch (e) {
        // Si erreur, token invalide
        await _authService.logout();
        _user = null;
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  // ─── LOGIN ───
  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _user = await _authService.login(email, password);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // ─── SIGNUP ───
  Future<bool> signup(String email, String password, String? fullName) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _user = await _authService.signup(email, password, fullName);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // ─── LOGOUT ───
  Future<void> logout() async {
    await _authService.logout();
    _user = null;
    notifyListeners();
  }

  // ─── FORGOT PASSWORD ───
  Future<bool> forgotPassword(String email) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _authService.forgotPassword(email);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // ─── RESET PASSWORD ───
  Future<bool> resetPassword(String token, String newPassword) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _authService.resetPassword(token, newPassword);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // ─── CHANGE PASSWORD (authentifié) ───
  Future<bool> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _authService.changePassword(currentPassword, newPassword);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // ─── UPDATE PROFILE ───
  Future<bool> updateProfile({String? fullName, String? mail}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _user = await _authService.updateProfile(fullName: fullName, mail: mail);
      await refreshProfile();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // ─── REFRESH PROFILE ───
  Future<bool> refreshProfile() async {
    _isLoading = true;
    notifyListeners();

    try {
      _user = await _authService.getProfile();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // ─── CLEAR ERROR ───
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
