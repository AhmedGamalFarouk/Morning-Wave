import 'package:flutter/material.dart';

import '../placeholder/family.dart';
import '../theme/palette.dart';
import '../widgets/paper_card.dart';
import '../widgets/sun_painter.dart';

/// The child's home answers one question before anything else:
/// "How is Mom?"
class ChildHomeScreen extends StatelessWidget {
  const ChildHomeScreen({super.key, this.view = ChildView.heard});

  final ChildView view;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Morning, ${PlaceholderFamily.childName}',
                style: text.titleLarge?.copyWith(color: Palette.inkSoft),
              ),
            ),
            const SizedBox(height: 18),
            _ParentHero(view: view),
          ],
        ),
      ),
    );
  }
}

class _ParentHero extends StatefulWidget {
  const _ParentHero({required this.view});

  final ChildView view;

  @override
  State<_ParentHero> createState() => _ParentHeroState();
}

class _ParentHeroState extends State<_ParentHero> {
  var _loveSent = false;

  void _sendLove() {
    setState(() => _loveSent = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('${PlaceholderFamily.parentName} will see your love.'),
      ),
    );
  }

  void _call() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Calling isn’t set up yet.')));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    const parent = PlaceholderFamily.parentName;

    final (warmth, top, title, line) = switch (widget.view) {
      ChildView.heard => (
        1.0,
        Palette.glow,
        '$parent said good morning',
        'Today · ${_clock(context, PlaceholderFamily.checkedInAt)}',
      ),
      ChildView.waiting => (
        0.6,
        Palette.sky,
        'Haven’t heard from $parent yet',
        '$parent’s mornings usually start by '
            '${PlaceholderFamily.usualMorningBy}.',
      ),
      ChildView.away => (
        0.45,
        Palette.paperDeep,
        '$parent is away',
        'Back on ${PlaceholderFamily.awayUntil}. Morning hellos start again '
            'the day after.',
      ),
    };

    return PaperCard(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [top, Palette.card],
        stops: const [0, 0.7],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SunMark(size: 96, warmth: warmth),
          const SizedBox(height: 16),
          Semantics(
            header: true,
            child: Text(title, style: text.displayMedium),
          ),
          const SizedBox(height: 10),
          Text(line, style: text.bodyLarge?.copyWith(color: Palette.inkSoft)),
          if (widget.view == ChildView.heard) ...[
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _loveSent ? null : _sendLove,
              icon: const HeartMark(color: Palette.peach),
              label: Text(_loveSent ? 'Love sent' : 'Send love'),
            ),
          ],
          if (widget.view == ChildView.waiting) ...[
            const SizedBox(height: 28),
            FilledButton(onPressed: _call, child: const Text('Call $parent')),
          ],
        ],
      ),
    );
  }

  /// Follows the phone's 12 or 24-hour setting.
  static String _clock(BuildContext context, DateTime time) {
    return MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(time),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
  }
}
