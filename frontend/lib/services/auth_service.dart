// services/auth_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../utils/constants.dart';

class AuthService {
  static const String _tokenKey = 'user_token';
  static const String _userKey = 'user_data';

  // ============================================================
  // MÉTHODES PRIVÉES
  // ============================================================

  Future<void> _saveUser(User user, String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userKey, jsonEncode(user.toJson()));
  }

  Future<void> _clearStorage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<void> saveUserData(User user) async {
    await _saveUser(user, user.token);
  }

  // ============================================================
  // AUTHENTIFICATION
  // ============================================================

  // ─── LOGIN ───
  Future<User> login(String email, String password) async {
    final response = await http
        .post(
          Uri.parse(ApiConstants.login),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'mail': email, 'password': password}),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body);
      final token = data['access_token'] ?? data['token'];

      if (token == null) {
        throw Exception('Token manquant dans la réponse');
      }

      final user = User.fromJson({...data, 'access_token': token});

      await _saveUser(user, token);
      return user;
    } else {
      try {
        final error = jsonDecode(response.body);
        throw Exception(
          error['detail'] ??
              error['message'] ??
              'Email ou mot de passe incorrect',
        );
      } catch (_) {
        throw Exception('Erreur de connexion au serveur');
      }
    }
  }

  // ─── SIGNUP ───
  Future<User> signup(String email, String password, String? fullName) async {
    final String finalFullName = (fullName == null || fullName.trim().isEmpty)
        ? email.split('@')[0]
        : fullName;

    final response = await http
        .post(
          Uri.parse(ApiConstants.signup),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'mail': email,
            'password': password,
            'fullname': finalFullName,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body);
      final token = data['access_token'] ?? data['token'];

      if (token == null) {
        throw Exception('Token manquant dans la réponse');
      }

      final user = User.fromJson({...data, 'access_token': token});

      await _saveUser(user, token);
      return user;
    } else {
      try {
        final error = jsonDecode(response.body);
        throw Exception(
          error['detail'] ??
              error['message'] ??
              'Erreur lors de l\'inscription',
        );
      } catch (_) {
        throw Exception('Erreur de connexion au serveur');
      }
    }
  }

  // ─── LOGOUT ───
  Future<void> logout() async {
    final token = await _getToken();
    if (token != null) {
      try {
        await http
            .post(
              Uri.parse(ApiConstants.logout),
              headers: {'Authorization': 'Bearer $token'},
            )
            .timeout(const Duration(seconds: 10));
      } catch (e) {
        // Ignorer les erreurs
      }
    }
    await _clearStorage();
  }

  // ─── GET STORED USER ───
  Future<User?> getStoredUser() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    if (token == null) return null;

    final userJson = prefs.getString(_userKey);
    if (userJson == null) return null;

    try {
      final data = jsonDecode(userJson);
      return User.fromJson({...data, 'access_token': token});
    } catch (e) {
      return null;
    }
  }

  // ─── GET PROFILE ───
  Future<User> getProfile() async {
    final token = await _getToken();
    if (token == null) throw Exception('Non authentifié');

    final response = await http
        .get(
          Uri.parse(ApiConstants.profile),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return User.fromJson({...data, 'access_token': token});
    } else {
      throw Exception('Erreur lors de la récupération du profil');
    }
  }

  // ─── UPDATE PROFILE ───
  Future<User> updateProfile({String? fullName, String? mail}) async {
    final token = await _getToken();
    if (token == null) throw Exception('Non authentifié');

    final Map<String, dynamic> body = {};
    if (fullName != null) body['fullname'] = fullName;
    if (mail != null) body['mail'] = mail;

    final response = await http
        .put(
          Uri.parse(ApiConstants.profile),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final newToken = data['access_token'] ?? data['token'] ?? token;

      final user = User.fromJson({...data, 'access_token': newToken});

      await _saveUser(user, newToken);
      return user;
    } else {
      try {
        final error = jsonDecode(response.body);
        throw Exception(
          error['detail'] ??
              error['message'] ??
              'Erreur lors de la mise à jour',
        );
      } catch (_) {
        throw Exception('Erreur de connexion au serveur');
      }
    }
  }

  // ============================================================
  // FORGOT PASSWORD
  // ============================================================

  /// Envoie un lien de réinitialisation à l'email
  Future<void> forgotPassword(String email) async {
    final response = await http
        .post(
          Uri.parse(ApiConstants.forgotPassword),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'mail': email}),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      return;
    } else {
      try {
        final error = jsonDecode(response.body);
        throw Exception(
          error['detail'] ?? error['message'] ?? 'Email non trouvé',
        );
      } catch (_) {
        throw Exception('Erreur de connexion au serveur');
      }
    }
  }

  // ============================================================
  // RESET PASSWORD
  // ============================================================

  /// Réinitialise le mot de passe avec le token reçu par email
  Future<void> resetPassword(String token, String newPassword) async {
    final response = await http
        .post(
          Uri.parse(ApiConstants.resetPassword),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'token': token, 'new_password': newPassword}),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      // Succès - mot de passe réinitialisé
      return;
    } else {
      try {
        final error = jsonDecode(response.body);
        throw Exception(
          error['detail'] ?? error['message'] ?? 'Token invalide ou expiré',
        );
      } catch (_) {
        throw Exception('Erreur de connexion au serveur');
      }
    }
  }

  // ============================================================
  // CHANGE PASSWORD (authentifié)
  // ============================================================

  /// Change le mot de passe pour un utilisateur authentifié
  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    final token = await _getToken();
    if (token == null) throw Exception('Non authentifié');

    final response = await http
        .post(
          Uri.parse(ApiConstants.changePassword),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'current_password': currentPassword,
            'new_password': newPassword,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      return;
    } else {
      try {
        final error = jsonDecode(response.body);
        throw Exception(
          error['detail'] ?? error['message'] ?? 'Erreur lors du changement',
        );
      } catch (_) {
        throw Exception('Erreur de connexion au serveur');
      }
    }
  }
}
