import 'package:flutter/material.dart';

import 'app_logo.dart';

/// EcoLoop-branded AppBar used across the main screens so the product name is
/// visible on every screen. Mirrors the Home screen header.
class BrandAppBar extends StatelessWidget implements PreferredSizeWidget {
  final List<Widget>? actions;

  const BrandAppBar({super.key, this.actions});

  @override
  Size get preferredSize => const Size.fromHeight(58);

  @override
  Widget build(BuildContext context) => AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 58,
        titleSpacing: 0,
        title: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: AppLogo(size: 22, showWordmark: true),
        ),
        actions: actions,
      );
}
