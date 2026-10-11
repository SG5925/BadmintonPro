import 'package:flutter/material.dart';

import '../../../shared/widgets/role_home_scaffold.dart';

class DeveloperPanelScreen extends StatelessWidget {
  const DeveloperPanelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return RoleHomeScaffold(
      title: 'Super Admin',
      icon: Icons.admin_panel_settings_outlined,
      body: (context, user) => const FeatureTiles(
        items: [
          (Icons.store_outlined, 'Tenants'),
          (Icons.badge_outlined, 'Coach codes'),
          (Icons.payments_outlined, 'Subscriptions'),
          (Icons.support_agent, 'Tickets'),
        ],
      ),
    );
  }
}
