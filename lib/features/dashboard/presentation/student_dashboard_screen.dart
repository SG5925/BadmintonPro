import 'package:flutter/material.dart';

import '../../../shared/widgets/role_home_scaffold.dart';

class StudentDashboardScreen extends StatelessWidget {
  const StudentDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return RoleHomeScaffold(
      title: 'My Training',
      icon: Icons.school_outlined,
      body: (context, user) => const FeatureTiles(
        items: [
          (Icons.event_available_outlined, 'My attendance'),
          (Icons.receipt_long_outlined, 'My fees'),
          (Icons.support_agent, 'Help'),
        ],
      ),
    );
  }
}
