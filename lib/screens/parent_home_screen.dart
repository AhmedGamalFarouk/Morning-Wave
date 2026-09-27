import 'package:flutter/material.dart';

import '../placeholder/family.dart';
import '../theme/motion.dart';
import '../theme/palette.dart';
import '../widgets/morning_sun.dart';
import '../widgets/paper_card.dart';
import '../widgets/sun_painter.dart';

enum ParentMorning { ready, sent, away }

/// The parent's whole app: a greeting, the sun, and what the family sent.
/// Nothing here ever talks about checks, misses or status.
class ParentHomeScreen extends StatefulWidget {
  const ParentHomeScreen({super.key, this.initial = ParentMorning.ready});

  final ParentMorning initial;

  @override
  State<ParentHomeScreen> createState() => _ParentHomeScreenState();
}

class _ParentHomeScreenState extends State<ParentHomeScreen> {
  late var _morning = widget.initial;

  void _set(ParentMorning morning) => setState(() => _morning = morning);

  Future<void> _askAboutAway() async {
    final away = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Palette.paper,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => const _AwaySheet(),
    );
    if (away == true) _set(ParentMorning.away);
  }

  @override
  Widget build(BuildContext context) {
    const name = PlaceholderFamily.parentName;
    final (title, line) = switch (_morning) {
      ParentMorning.ready => ('Good morning, $name', 'Ready to say hello?'),
      ParentMorning.sent => (
        'Good morning, $name',
        'Your family knows you’re okay.',
      ),
      ParentMorning.away => ('You’re away', 'Your family knows.'),
    };

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 36, 24, 32),
          children: [
            _Greeting(title: title, line: line),
            const SizedBox(height: 8),
            Center(
              child: switch (_morning) {
                ParentMorning.ready => MorningSun(
                  label: 'Say good\nmorning',
                  semanticLabel: 'Say good morning to your family',
                  onPressed: () => _set(ParentMorning.sent),
                ),
                ParentMorning.sent => const MorningSun(
                  label: 'Hello\nsent',
                  semanticLabel: 'Your good morning was sent',
                ),
                ParentMorning.away => MorningSun(
                  label: 'I’m\nback',
                  semanticLabel: 'Tell your family you’re back',
                  warmth: 0.55,
                  onPressed: () => _set(ParentMorning.ready),
                ),
              },
            ),
            AnimatedSize(
              duration: Motion.crossfade,
              curve: Motion.settle,
              child: AnimatedSwitcher(
                duration: Motion.crossfade,
                child: _morning == ParentMorning.sent
                    ? const Padding(
                        padding: EdgeInsets.only(top: 8, bottom: 24),
                        child: _FamilyNote(),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ),
            const SizedBox(height: 8),
            const _FamilyPhoto(),
            if (_morning != ParentMorning.away) ...[
              const SizedBox(height: 20),
              Center(
                child: TextButton(
                  onPressed: _askAboutAway,
                  child: const Text('Going somewhere?'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.title, required this.line});

  final String title;
  final String line;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AnimatedSwitcher(
      duration: Motion.crossfade,
      switchInCurve: Motion.fadeIn,
      switchOutCurve: Motion.fadeOut,
      child: Column(
        key: ValueKey('$title$line'),
        children: [
          Text(title, textAlign: TextAlign.center, style: text.displayMedium),
          const SizedBox(height: 10),
          Text(
            line,
            textAlign: TextAlign.center,
            style: text.bodyLarge?.copyWith(color: Palette.inkSoft),
          ),
        ],
      ),
    );
  }
}

/// The reward for saying good morning: a few words from the family.
class _FamilyNote extends StatelessWidget {
  const _FamilyNote();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const HeartMark(),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Your ${PlaceholderFamily.childRelation} sent you some love',
                  style: text.bodyMedium?.copyWith(color: Palette.inkSoft),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text('“${PlaceholderFamily.note}”', style: text.headlineSmall),
          const SizedBox(height: 10),
          Text(
            PlaceholderFamily.childName,
            style: text.titleMedium?.copyWith(color: Palette.sageDeep),
          ),
        ],
      ),
    );
  }
}

/// A photo on the fridge. Until the family shares one, the frame says
/// where it will appear instead of showing a stock picture.
class _FamilyPhoto extends StatelessWidget {
  const _FamilyPhoto();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return PaperCard(
      padding: const EdgeInsets.all(14),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Palette.sky, Palette.paperDeep],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SunMark(size: 72),
                const SizedBox(height: 12),
                Text(
                  'Photos from your family will sit right here.',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AwaySheet extends StatelessWidget {
  const _AwaySheet();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Going somewhere?', style: text.headlineMedium),
            const SizedBox(height: 12),
            Text(
              'Let your family know you’re away, so they won’t expect '
              'your good morning.',
              style: text.bodyLarge,
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Let my family know'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    );
  }
}
