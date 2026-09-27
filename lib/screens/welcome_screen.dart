import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../widgets/paper_card.dart';
import '../widgets/sun_painter.dart';

/// The first screen on both phones. The grown child sets the family up
/// with Google; the parent only ever needs the code their family gives them.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    super.key,
    required this.onSetUpForParent,
    required this.onHaveCode,
    this.busy = false,
  });

  final VoidCallback onSetUpForParent;
  final VoidCallback onHaveCode;

  /// True while Google sign-in is open, so it can't be started twice.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
          children: [
            const Center(child: SunMark(size: 104)),
            const SizedBox(height: 20),
            Semantics(
              header: true,
              child: Text(
                'Morning Wave',
                textAlign: TextAlign.center,
                style: text.displayMedium,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'A good morning from Mom or Dad, every day.',
              textAlign: TextAlign.center,
              style: text.bodyLarge?.copyWith(color: Palette.inkSoft),
            ),
            const SizedBox(height: 36),
            _Path(
              title: 'Did your family give you a code?',
              line: 'Type it in once and you’re all set.',
              action: 'I have a code',
              onPressed: busy ? null : onHaveCode,
            ),
            const SizedBox(height: 20),
            _Path(
              title: 'Setting this up for your mom or dad?',
              line: 'Start here with your Google account.',
              action: busy ? 'Opening Google…' : 'Continue with Google',
              onPressed: busy ? null : onSetUpForParent,
            ),
          ],
        ),
      ),
    );
  }
}

class _Path extends StatelessWidget {
  const _Path({
    required this.title,
    required this.line,
    required this.action,
    required this.onPressed,
  });

  final String title;
  final String line;
  final String action;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: text.headlineSmall),
          const SizedBox(height: 8),
          Text(line, style: text.bodyMedium?.copyWith(color: Palette.inkSoft)),
          const SizedBox(height: 20),
          FilledButton(onPressed: onPressed, child: Text(action)),
        ],
      ),
    );
  }
}
