import 'package:flutter/material.dart';
import '../../core/ui/settings_widgets.dart';

import '../../core/theme/app_colors.dart';
import '../../core/ui/developer_card.dart';

/// Credits page — the people behind the app. Modeled on Sozo Read's
/// Developers screen: a centered title and a single credits card.
class DevelopersScreen extends StatelessWidget {
  const DevelopersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: settingsAppBar('Developers'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: const [DeveloperCard()],
      ),
    );
  }
}
