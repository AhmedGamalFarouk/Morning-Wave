import 'package:flutter/material.dart';

/// Placeholder until the check-in screens are designed.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.requestNotificationPermission});

  final Future<bool> Function() requestNotificationPermission;

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
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Good morning',
            style: Theme.of(context).textTheme.displaySmall,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
