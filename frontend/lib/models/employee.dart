// models/employee.dart
enum EmployeeStatus { online, away, offline }

class Employee {
  final String id;
  final String firstName;
  final String lastName;
  final String role;
  final EmployeeStatus status;
  final DateTime? lastSeen;

  Employee({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.role,
    this.status = EmployeeStatus.offline,
    this.lastSeen,
  });

  // Nom complet calculé
  String get fullName => '$firstName $lastName';

  // Convertir JSON de l'API → Objet Dart
  factory Employee.fromJson(Map<String, dynamic> json) {
    return Employee(
      id: json['id_bracelet']?.toString() ?? '',
      firstName: json['firstName'] ?? '',
      lastName: json['lastName'] ?? '',
      role: json['role'] ?? '',
      status: _parseStatus(json['status']),
      lastSeen: _parseLastSeen(json['last_seen']),
    );
  }

  // helper parsing
  static EmployeeStatus _parseStatus(dynamic value) {
    switch (value?.toString()) {
      case 'online':
        return EmployeeStatus.online;
      case 'away':
        return EmployeeStatus.away;
      case 'offline':
      default:
        return EmployeeStatus.offline;
    }
  }

  // helper parsing
  static DateTime? _parseLastSeen(dynamic value) {
    if (value == null) return null;
    try {
      return DateTime.parse(value.toString());
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id_bracelet': id,
      'firstName': firstName,
      'lastName': lastName,
      'role': role,
      'status': status.name,
      'last_seen': lastSeen?.toIso8601String(),
    };
  }
}
