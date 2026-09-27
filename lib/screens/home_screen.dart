import 'package:flutter/material.dart';

import '../placeholder/family.dart';
import 'child_home_screen.dart';
import 'parent_home_screen.dart';

/// Which home to show. Until sign-in exists this comes from the `PREVIEW`
/// build define: `parent` (default), `child`, `child-waiting`, `child-away`.
enum HomePreview { parent, child, childWaiting, childAway }

HomePreview parseHomePreview(String value) => switch (value) {
  'child' => HomePreview.child,
  'child-waiting' => HomePreview.childWaiting,
  'child-away' => HomePreview.childAway,
  _ => HomePreview.parent,
};

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.requestNotificationPermission,
    this.preview = HomePreview.parent,
  });

  final Future<bool> Function() requestNotificationPermission;
  final HomePreview preview;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    widget.requestNotificationPermission();
  }

  @override
  Widget build(BuildContext context) {
    return switch (widget.preview) {
      HomePreview.parent => const ParentHomeScreen(),
      HomePreview.child => const ChildHomeScreen(),
      HomePreview.childWaiting => const ChildHomeScreen(
        view: ChildView.waiting,
      ),
      HomePreview.childAway => const ChildHomeScreen(view: ChildView.away),
    };
  }
}
