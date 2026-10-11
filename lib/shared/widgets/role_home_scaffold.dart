import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_providers.dart';
import '../models/app_user.dart';

/// Common shell for each role's home: title, signed-in user card, sign out.
class RoleHomeScaffold extends ConsumerWidget {
  const RoleHomeScaffold({
    super.key,
    required this.title,
    required this.icon,
    required this.body,
  });

  final String title;
  final IconData icon;
  final Widget Function(BuildContext context, AppUser user) body;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authServiceProvider).signOut(),
          ),
        ],
      ),
      body: user == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: CircleAvatar(child: Icon(icon)),
                    title: Text(user.displayName),
                    subtitle: Text(
                      [
                        user.role.label,
                        if (user.academyName != null) user.academyName!,
                        if (user.coachCode != null) user.coachCode!,
                      ].join(' · '),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                body(context, user),
                const SizedBox(height: 24),
                Text(
                  'Placeholder — features arrive in later phases.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
    );
  }
}

/// Grid of "coming soon" feature tiles for the placeholder dashboards.
class FeatureTiles extends StatelessWidget {
  const FeatureTiles({super.key, required this.items});

  final List<(IconData, String)> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final (icon, label) in items)
          SizedBox(
            width: 160,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon),
                    const SizedBox(height: 8),
                    Text(label),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
