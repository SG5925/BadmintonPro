import 'package:flutter/material.dart';

import '../../../shared/widgets/role_home_scaffold.dart';

class GuestViewScreen extends StatelessWidget {
  const GuestViewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return RoleHomeScaffold(
      title: 'Welcome',
      icon: Icons.person_outline,
      body: (context, user) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Your visits to ${user.academyName ?? 'this academy'} will appear here.',
          ),
        ),
      ),
    );
  }
}
