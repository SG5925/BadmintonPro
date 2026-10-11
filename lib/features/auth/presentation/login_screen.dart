import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/router/app_routes.dart';
import '../../../shared/models/user_role.dart';

/// Entry point: pick Coach, Student or Guest. Long-pressing the logo opens
/// the hidden developer login.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GestureDetector(
                    key: const Key('app-logo'),
                    onLongPress: () =>
                        context.push(AppRoutes.loginFor(UserRole.developer)),
                    child: Icon(
                      Icons.sports_tennis,
                      size: 64,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    AppConstants.appName,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'How are you signing in?',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),
                  const _RoleCard(
                    role: UserRole.coach,
                    icon: Icons.sports,
                    subtitle: 'Manage your academy',
                  ),
                  const SizedBox(height: 12),
                  const _RoleCard(
                    role: UserRole.student,
                    icon: Icons.school_outlined,
                    subtitle: 'Attendance, fees and updates',
                  ),
                  const SizedBox(height: 12),
                  const _RoleCard(
                    role: UserRole.guest,
                    icon: Icons.person_outline,
                    subtitle: 'Visiting or trying out a session',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.role,
    required this.icon,
    required this.subtitle,
  });

  final UserRole role;
  final IconData icon;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.surfaceContainerHighest,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: colors.primaryContainer,
          foregroundColor: colors.onPrimaryContainer,
          child: Icon(icon),
        ),
        title: Text(role.label),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(AppRoutes.loginFor(role)),
      ),
    );
  }
}
