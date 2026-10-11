import 'package:badminton_pro/core/utils/validators.dart';
import 'package:badminton_pro/shared/models/app_user.dart';
import 'package:badminton_pro/shared/models/user_role.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('email validation', () {
    expect(Validators.emailError('coach@academy.in'), isNull);
    expect(Validators.emailError('  coach@academy.in  '), isNull);
    expect(Validators.emailError(''), 'Enter your email');
    expect(Validators.emailError('coach@academy'), 'Enter a valid email');
    expect(Validators.emailError('not an email'), 'Enter a valid email');
  });

  test('coach code accepts full and short forms', () {
    expect(Validators.isCoachCode('BP-COACH-0042'), isTrue);
    expect(Validators.isCoachCode('bp-coach-42'), isTrue);
    expect(Validators.isCoachCode('42'), isTrue);
    expect(Validators.isCoachCode('COACH-42'), isFalse);
    expect(Validators.isCoachCode('BP-COACH-'), isFalse);
  });

  test('otp is 6-10 digits', () {
    expect(Validators.isOtp('123456'), isTrue);
    expect(Validators.isOtp('12345'), isFalse);
    expect(Validators.isOtp('12345a'), isFalse);
  });

  group('AppUser.fromMap', () {
    test('parses a linked coach with embedded tenant', () {
      final u = AppUser.fromMap({
        'id': 'u1',
        'role': 'coach',
        'tenant_id': 't1',
        'is_active': true,
        'full_name': 'Asha',
        'tenants': {
          'name': 'A',
          'academy_name': 'Smash Academy',
          'coach_code': 'BP-COACH-0001',
        },
      });
      expect(u.role, UserRole.coach);
      expect(u.isLinked, isTrue);
      expect(u.academyName, 'Smash Academy');
      expect(u.coachCode, 'BP-COACH-0001');
    });

    test('new OTP account is an unlinked guest', () {
      final u = AppUser.fromMap({
        'id': 'u2',
        'role': 'guest',
        'tenant_id': null,
        'is_active': true,
        'tenants': null,
      });
      expect(u.isLinked, isFalse);
    });

    test('developer is linked without a tenant', () {
      final u = AppUser.fromMap({
        'id': 'u3',
        'role': 'developer',
        'tenant_id': null,
        'is_active': true,
      });
      expect(u.isLinked, isTrue);
    });
  });
}
