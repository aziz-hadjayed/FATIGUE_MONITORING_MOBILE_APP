// utils/constants.dart
import 'package:flutter/material.dart';

class AppColors {
  static const Color darkBlue = Color(0xFF2B2D42); // Texte, icônes
  static const Color turquoise = Color(0xFF92DCE5); // Boutons, accents
  static const Color lightGray = Color(0xFFF8F7F9); // Fonds, champs

  static const Color white = Colors.white;

  static const Color green = Color(0xFF22C55E);
  static const Color yellow = Color(0xFFF59E0B);
  static const Color red = Color(0xFFEF4444);
}

// ============================================================
// API ENDPOINTS
// ============================================================
class ApiConstants {
  // ──────────────────────────────────────────────────────────
  // BASE URL
  // ──────────────────────────────────────────────────────────
  static const String baseUrl = 'https://conduit-heavily-kudos.ngrok-free.dev';
  static const String wsUrl = 'wss://conduit-heavily-kudos.ngrok-free.dev/ws';

  // ──────────────────────────────────────────────────────────
  // AUTHENTIFICATION
  // ──────────────────────────────────────────────────────────
  static const String login = '$baseUrl/auth/login';
  static const String signup = '$baseUrl/auth/signup';
  static const String logout = '$baseUrl/auth/logout';
  static const String profile = '$baseUrl/auth/profile'; // GET + PUT

  // ──────────────────────────────────────────────────────────
  // EMPLOYÉS
  // ──────────────────────────────────────────────────────────
  static const String employees = '$baseUrl/employees/';
  static String employeeDetail(String id) => '$employees$id';

  // ──────────────────────────────────────────────────────────
  // Forgot Password
  // ──────────────────────────────────────────────────────────
  static const String forgotPassword = '$baseUrl/auth/forgot-password';
  static const String resetPassword = '$baseUrl/auth/reset-password';
  static const String changePassword = '$baseUrl/auth/change-password';
}

// ============================================================
// PAS DU PEIGNE DE DIRAC (Zoom)
// ============================================================
enum DiracStep {
  step30sec(Duration(seconds: 30), '30 sec'),
  step1min(Duration(minutes: 1), '1 min'),
  step5min(Duration(minutes: 5), '5 min'),
  step10min(Duration(minutes: 10), '10 min'),
  step15min(Duration(minutes: 15), '15 min'),
  step20min(Duration(minutes: 20), '20 min'),
  step30min(Duration(minutes: 30), '30 min'),
  step1hour(Duration(hours: 1), '1 heure');

  final Duration duration;
  final String label;

  const DiracStep(this.duration, this.label);
}
