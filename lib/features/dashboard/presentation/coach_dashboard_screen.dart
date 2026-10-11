import 'package:flutter/material.dart';

import '../../../shared/widgets/role_home_scaffold.dart';

class CoachDashboardScreen extends StatelessWidget {
  const CoachDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return RoleHomeScaffold(
      title: 'Coach Dashboard',
      icon: Icons.sports,
      body: (context, user) => const FeatureTiles(
        items: [
          (Icons.groups_outlined, 'Members'),
          (Icons.fact_check_outlined, 'Attendance'),
          (Icons.payments_outlined, 'Finance'),
          (Icons.inventory_2_outlined, 'Inventory'),
          (Icons.person_add_alt, 'Guests'),
          (Icons.support_agent, 'Tickets'),
        ],
      ),
    );
  }
}
