import 'dart:async';

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
  const ParentHomeScreen({
    super.key,
    this.initial = ParentMorning.ready,
    this.today,
    this.requestNotificationPermission,
    this.notificationsEnabled,
    this.parentName = PlaceholderFamily.parentName,
  });

  final ParentMorning initial;

  /// What the family calls the parent; the greeting uses it.
  final String parentName;

  /// Asked only after the first good morning, behind a warm invitation,
  /// never as a system dialog on first open.
  final Future<bool> Function()? requestNotificationPermission;

  /// When this says notifications are already allowed, the invitation
  /// never shows.
  final Future<bool> Function()? notificationsEnabled;

  /// Fixed date for tests and previews; the real clock otherwise.
  final DateTime? today;

  /// How long an accidental tap can be taken back. Sending to the family
  /// will wait for this window once the backend is wired.
  static const undoWindow = Duration(seconds: 10);

  @override
  State<ParentHomeScreen> createState() => _ParentHomeScreenState();
}

class _ParentHomeScreenState extends State<ParentHomeScreen> {
  late var _morning = widget.initial;
  DateTime? _backOn;
  Timer? _undoTimer;
  var _notesAsked = false;

  @override
  void initState() {
    super.initState();
    widget.notificationsEnabled?.call().then((enabled) {
      if (enabled && mounted) setState(() => _notesAsked = true);
    });
  }

  @override
  void dispose() {
    _undoTimer?.cancel();
    super.dispose();
  }

  void _set(ParentMorning morning) {
    _undoTimer?.cancel();
    _undoTimer = null;
    setState(() => _morning = morning);
  }

  void _sayGoodMorning() {
    _set(ParentMorning.sent);
    _undoTimer = Timer(ParentHomeScreen.undoWindow, () {
      if (mounted) setState(() => _undoTimer = null);
    });
  }

  void _answerNotes({required bool allow}) {
    setState(() => _notesAsked = true);
    if (allow) widget.requestNotificationPermission!();
  }

  Future<void> _askAboutAway() async {
    final backOn = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: Palette.paper,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _AwaySheet(today: widget.today ?? DateTime.now()),
    );
    if (backOn == null) return;
    _backOn = backOn;
    _set(ParentMorning.away);
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.parentName;
    final (title, line) = switch (_morning) {
      ParentMorning.ready => ('Good morning, $name', 'Ready to say hello?'),
      ParentMorning.sent => (
        'Good morning, $name',
        'Your family knows you’re okay.',
      ),
      ParentMorning.away => (
        'You’re away',
        _backOn == null
            ? 'Your family knows.'
            : 'Back ${_dayName(context, _backOn!, widget.today ?? DateTime.now())}. '
                  'Your family knows.',
      ),
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
                  onPressed: _sayGoodMorning,
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
              child: _undoTimer == null
                  ? const SizedBox(width: double.infinity)
                  : Center(
                      child: TextButton(
                        onPressed: () => _set(ParentMorning.ready),
                        child: const Text('Oops, not yet'),
                      ),
                    ),
            ),
            AnimatedSize(
              duration: Motion.crossfade,
              curve: Motion.settle,
              child: AnimatedSwitcher(
                duration: Motion.crossfade,
                child: _morning == ParentMorning.sent
                    ? Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 24),
                        child: Column(
                          children: [
                            const _FamilyNote(),
                            if (!_notesAsked &&
                                widget.requestNotificationPermission !=
                                    null) ...[
                              const SizedBox(height: 16),
                              _NotesInvitation(onAnswer: _answerNotes),
                            ],
                          ],
                        ),
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

/// Asks for notification permission the way a family member would, after
/// the parent has already felt why it matters.
class _NotesInvitation extends StatelessWidget {
  const _NotesInvitation({required this.onAnswer});

  final void Function({required bool allow}) onAnswer;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('So your family’s love reaches you', style: text.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Let Morning Wave bring you their notes when they send one.',
            style: text.bodyMedium?.copyWith(color: Palette.inkSoft),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => onAnswer(allow: true),
            child: const Text('Yes, bring me notes'),
          ),
          TextButton(
            onPressed: () => onAnswer(allow: false),
            child: const Text('Maybe later'),
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
      // A minimum height instead of a fixed ratio, so large system text
      // grows the frame rather than spilling out of it.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 260),
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
                const SizedBox(height: 24),
                const SunMark(size: 72),
                const SizedBox(height: 12),
                Text(
                  'Photos from your family will sit right here.',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "tomorrow", "on Friday", "next Monday" for a week from today, or the
/// date itself further out.
String _dayName(BuildContext context, DateTime day, DateTime today) {
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  final gap = DateUtils.dateOnly(day).difference(DateUtils.dateOnly(today));
  final weekday = weekdays[day.weekday - 1];
  if (gap.inDays == 1) return 'tomorrow';
  if (gap.inDays < 7) return 'on $weekday';
  if (gap.inDays == 7) return 'next $weekday';
  return 'on ${MaterialLocalizations.of(context).formatMediumDate(day)}';
}

/// Asks which day the parent will be back. That day is a rest day too;
/// mornings resume on their own the day after, so nothing needs switching
/// back on.
class _AwaySheet extends StatefulWidget {
  const _AwaySheet({required this.today});

  final DateTime today;

  @override
  State<_AwaySheet> createState() => _AwaySheetState();
}

class _AwaySheetState extends State<_AwaySheet> {
  late final _today = DateUtils.dateOnly(widget.today);
  late final _days = [
    for (var i = 1; i <= 7; i++) _today.add(Duration(days: i)),
  ];

  /// Tomorrow is chosen from the start, so the main button always works.
  late var _backOn = _days.first;

  /// Longer trips: a calendar for any day after next week.
  Future<void> _pickLater() async {
    final later = await showDatePicker(
      context: context,
      initialDate: _backOn.isAfter(_days.last)
          ? _backOn
          : _today.add(const Duration(days: 14)),
      firstDate: _today.add(const Duration(days: 8)),
      lastDate: _today.add(const Duration(days: 365)),
      helpText: 'When will you be back?',
      confirmText: 'That’s the day',
    );
    if (later != null) setState(() => _backOn = later);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final isLater = _backOn.isAfter(_days.last);

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
              'When will you be back? Your family won’t expect a good '
              'morning while you’re away, or on the day you get home.',
              style: text.bodyLarge,
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final day in _days)
                  _DayChoice(
                    label: _capitalize(_dayName(context, day, _today)),
                    selected: _backOn == day,
                    onTap: () => setState(() => _backOn = day),
                  ),
                _DayChoice(
                  label: isLater
                      ? _capitalize(_dayName(context, _backOn, _today))
                      : 'Later…',
                  selected: isLater,
                  onTap: _pickLater,
                ),
              ],
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: () => Navigator.pop(context, _backOn),
              child: const Text('Let my family know'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    );
  }

  static String _capitalize(String words) {
    final plain = words.startsWith('on ') ? words.substring(3) : words;
    return plain[0].toUpperCase() + plain.substring(1);
  }
}

/// A large, forgiving day button: warm fill when chosen.
class _DayChoice extends StatelessWidget {
  const _DayChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? Palette.sun : Palette.card,
        shape: StadiumBorder(
          side: BorderSide(color: selected ? Palette.sunEdge : Palette.peach),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56, minWidth: 96),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
