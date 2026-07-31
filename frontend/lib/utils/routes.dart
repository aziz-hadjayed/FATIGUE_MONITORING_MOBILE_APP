// utils/routes.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';
  static const String signup = '/signup';
  static const String home = '/home';
  static const String employee = '/employee';
  static const String forgotPassword = '/forgot-password';
  static const String profilAdmin = '/profil-admin';
  static const String resetPassword = '/reset-password';

  // Helper pour naviguer avec go_router
  static void goTo(BuildContext context, String route, {Object? extra}) {
    context.go(route, extra: extra);
  }

  static void pushTo(BuildContext context, String route, {Object? extra}) {
    context.push(route, extra: extra);
  }

  static void replaceTo(BuildContext context, String route, {Object? extra}) {
    context.replace(route, extra: extra);
  }

  static void goBack(BuildContext context) {
    context.pop();
  }

  static void goToLoginAndClearHistory(BuildContext context) {
    context.go(login);
  }

  static void goToHomeAndClearHistory(BuildContext context) {
    context.go(home);
  }

  static void goToResetPassword(BuildContext context, String token) {
    context.go('$resetPassword?token=$token');
  }
}
