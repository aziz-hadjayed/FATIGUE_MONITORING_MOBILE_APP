// models/user.dart
class User {
  final String id;
  final String mail;
  final String fullName;
  final String token;

  User({
    required this.id,
    required this.mail,
    required this.fullName,
    required this.token,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'].toString(),
      mail: json['mail'] ?? '',
      fullName: json['fullname'] ?? json['fullName'] ?? '',
      token: json['access_token'] ?? json['token'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'mail': mail,
      'fullname': fullName,
      'access_token': token,
    };
  }
}
