/// The authenticated user, mirroring the API's user payload.
class User {
  const User({
    required this.id,
    required this.firstName,
    this.middleName,
    required this.lastName,
    required this.username,
    required this.email,
    this.phoneNumber,
    required this.fullName,
    this.avatarUrl,
    this.incomeBracket,
    this.declaredIncomeBracket,
    this.roles = const [],
  });

  final String id;
  final String firstName;
  final String? middleName;
  final String lastName;
  final String username;
  final String email;
  final String? phoneNumber;
  final String fullName;
  final String? avatarUrl;
  final String? incomeBracket;
  final String? declaredIncomeBracket;
  final List<String> roles;

  bool get isAdmin => roles.contains('admin') || roles.contains('super-admin');

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'].toString(),
      firstName: json['first_name']?.toString() ?? '',
      middleName: json['middle_name']?.toString(),
      lastName: json['last_name']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      phoneNumber: json['phone_number']?.toString(),
      fullName: json['full_name']?.toString() ?? '',
      avatarUrl: json['avatar_url']?.toString(),
      incomeBracket: json['income_bracket']?.toString(),
      declaredIncomeBracket: json['declared_income_bracket']?.toString(),
      roles: (json['roles'] as List?)?.map((r) => r.toString()).toList() ?? const [],
    );
  }
}
