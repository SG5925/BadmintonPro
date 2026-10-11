/// Mirrors the `public.user_role` enum in the database.
enum UserRole {
  developer,
  coach,
  student,
  guest;

  static UserRole? tryParse(String? value) {
    for (final role in values) {
      if (role.name == value) return role;
    }
    return null;
  }

  String get label => switch (this) {
    UserRole.developer => 'Developer',
    UserRole.coach => 'Coach',
    UserRole.student => 'Student',
    UserRole.guest => 'Guest',
  };
}
