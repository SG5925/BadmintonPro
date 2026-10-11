import '../../shared/models/user_role.dart';

abstract final class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';
  static const String coachLogin = '/login/coach';
  static const String studentLogin = '/login/student';
  static const String guestLogin = '/login/guest';
  static const String developerLogin = '/login/developer';

  static const String coachDashboard = '/dashboard';
  static const String studentDashboard = '/student';
  static const String guestView = '/guest';
  static const String developerPanel = '/developer';

  static String loginFor(UserRole role) => switch (role) {
    UserRole.coach => coachLogin,
    UserRole.student => studentLogin,
    UserRole.guest => guestLogin,
    UserRole.developer => developerLogin,
  };

  static String homeFor(UserRole role) => switch (role) {
    UserRole.developer => developerPanel,
    UserRole.coach => coachDashboard,
    UserRole.student => studentDashboard,
    UserRole.guest => guestView,
  };
}
