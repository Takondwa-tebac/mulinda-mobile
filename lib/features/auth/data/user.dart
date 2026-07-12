import '../../subscription/data/subscription_models.dart';

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
    this.displayCurrency = 'MWK',
    this.roles = const [],
    this.subscription = const SubscriptionInfo.none(),
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
  final String displayCurrency;
  final List<String> roles;
  final SubscriptionInfo subscription;

  bool get isAdmin => roles.contains('admin') || roles.contains('super-admin');

  /// Whether the user currently holds a premium entitlement (see [Entitlements]).
  bool can(String entitlement) => subscription.can(entitlement);

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
      displayCurrency: json['display_currency']?.toString() ?? 'MWK',
      roles: (json['roles'] as List?)?.map((r) => r.toString()).toList() ?? const [],
      subscription: json['subscription'] is Map
          ? SubscriptionInfo.fromJson(
              (json['subscription'] as Map).cast<String, dynamic>())
          : const SubscriptionInfo.none(),
    );
  }
}
