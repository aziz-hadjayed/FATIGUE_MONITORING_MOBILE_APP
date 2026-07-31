// services/api_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/employee.dart';
import '../utils/constants.dart';

class ApiService {
  // Récupère le token stocké
  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_token');
  }

  // Headers avec authentification
  Future<Map<String, String>> _getHeaders() async {
    final token = await _getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ========== EMPLOYÉS ==========
  Future<List<Employee>> fetchEmployees() async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse(ApiConstants.employees),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => Employee.fromJson(json)).toList();
    } else if (response.statusCode == 401) {
      throw Exception('Session expirée, reconnectez-vous');
    } else {
      throw Exception('Erreur ${response.statusCode}: ${response.body}');
    }
  }

  Future<Employee> addEmployee(
    String id,
    String firstName,
    String lastName,
    String role,
  ) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse(ApiConstants.employees),
      headers: headers,
      body: jsonEncode({
        'id_bracelet': id,
        'firstName': firstName,
        'lastName': lastName,
        'role': role,
      }),
    );
    print("📡 URL: ${ApiConstants.employees}");
    print("📦 Status: ${response.statusCode}");
    print("📦 Body: ${response.body}");

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body);
      return Employee.fromJson(data);
    } else if (response.statusCode == 401) {
      throw Exception('Session expirée, reconnectez-vous');
    } else {
      throw Exception('Erreur ${response.statusCode}: ${response.body}');
    }
  }

  Future<void> deleteEmployee(String id) async {
    final headers = await _getHeaders();
    final url = ApiConstants.employeeDetail(id);

    print("🗑️ DELETE URL: $url");

    final response = await http.delete(Uri.parse(url), headers: headers);

    print("📦 Status: ${response.statusCode}");

    if (response.statusCode == 200 || response.statusCode == 204) {
      return;
    } else if (response.statusCode == 401) {
      throw Exception('Session expirée, reconnectez-vous');
    } else if (response.statusCode == 404) {
      throw Exception('Employé non trouvé');
    } else {
      throw Exception('Erreur ${response.statusCode}: ${response.body}');
    }
  }
}
