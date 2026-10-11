import 'user_role.dart';

/// The signed-in user's `public.users` row plus their academy's display info.
class AppUser {
  const AppUser({
    required this.id,
    required this.role,
    required this.isActive,
    this.tenantId,
    this.fullName,
    this.email,
    this.phone,
    this.academyName,
    this.coachCode,
  });

  final String id;
  final UserRole role;
  final bool isActive;
  final String? tenantId;
  final String? fullName;
  final String? email;
  final String? phone;
  final String? academyName;
  final String? coachCode;

  /// True once the account is attached to an academy (or is the developer).
  /// A fresh OTP account starts as an unlinked guest until a claim succeeds.
  bool get isLinked =>
      isActive && (role == UserRole.developer || tenantId != null);

  String get displayName => fullName ?? email ?? phone ?? role.label;

  factory AppUser.fromMap(Map<String, dynamic> map) {
    final tenant = map['tenants'] as Map<String, dynamic>?;
    return AppUser(
      id: map['id'] as String,
      role: UserRole.tryParse(map['role'] as String?) ?? UserRole.guest,
      isActive: map['is_active'] as bool? ?? false,
      tenantId: map['tenant_id'] as String?,
      fullName: map['full_name'] as String?,
      email: map['email'] as String?,
      phone: map['phone'] as String?,
      academyName:
          tenant?['academy_name'] as String? ?? tenant?['name'] as String?,
      coachCode: tenant?['coach_code'] as String?,
    );
  }
}
