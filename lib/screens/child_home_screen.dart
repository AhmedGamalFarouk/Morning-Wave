import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../placeholder/family.dart';
import '../theme/palette.dart';
import '../widgets/paper_card.dart';
import '../widgets/sun_painter.dart';

/// The child's home answers one question before anything else:
/// "How is Mom?"
class ChildHomeScreen extends StatelessWidget {
  const ChildHomeScreen({
    super.key,
    this.view = ChildView.heard,
    this.parentName = PlaceholderFamily.parentName,
    this.childName = PlaceholderFamily.childName,
    this.inviteCode,
    this.onRefresh,
  });

  final ChildView view;
  final String parentName;
  final String? childName;

  /// Set until the parent's phone has joined; the invite then leads.
  final String? inviteCode;

  /// Pull down to look again, for example once the parent has joined.
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            childName == null ? 'Good morning' : 'Morning, $childName',
            style: text.titleLarge?.copyWith(color: Palette.inkSoft),
          ),
        ),
        const SizedBox(height: 18),
        if (inviteCode == null)
          _ParentHero(view: view, parent: parentName)
        else
          _InviteCard(code: inviteCode!, parent: parentName),
      ],
    );
    return Scaffold(
      body: SafeArea(
        child: onRefresh == null
            ? list
            : RefreshIndicator(
                onRefresh: onRefresh!,
                color: Palette.sunEdge,
                child: list,
              ),
      ),
    );
  }
}

/// Before the parent's phone joins, the child's whole job is this code.
class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.code, required this.parent});

  final String code;
  final String parent;

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Code copied')));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return PaperCard(
      padding: const EdgeInsets.all(28),
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Palette.glow, Palette.card],
        stops: [0, 0.7],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SunMark(size: 80, warmth: 0.8),
          const SizedBox(height: 16),
          Semantics(
            header: true,
            child: Text('Now, $parent’s phone', style: text.displayMedium),
          ),
          const SizedBox(height: 12),
          Text(
            'Install Morning Wave on $parent’s phone, tap “I have a code” '
            'and type:',
            style: text.bodyLarge?.copyWith(color: Palette.inkSoft),
          ),
          const SizedBox(height: 20),
          Center(
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.4,
              child: SelectableText(
                code,
                semanticsLabel: 'Family code ${code.split('').join(' ')}',
                style: text.displayMedium?.copyWith(
                  fontSize: 44,
                  letterSpacing: 8,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => _copy(context),
            child: const Text('Copy the code'),
          ),
          const SizedBox(height: 12),
          Text(
            'You’ll see $parent’s good mornings right here.',
            style: text.bodyMedium?.copyWith(color: Palette.inkSoft),
          ),
        ],
      ),
    );
  }
}

class _ParentHero extends StatefulWidget {
  const _ParentHero({required this.view, required this.parent});

  final ChildView view;
  final String parent;

  @override
  State<_ParentHero> createState() => _ParentHeroState();
}

class _ParentHeroState extends State<_ParentHero> {
  var _loveSent = false;

  void _sendLove() {
    setState(() => _loveSent = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${widget.parent} will see your love.')),
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
    final parent = widget.parent;

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
        'Back on ${PlaceholderFamily.awayUntil}. No morning hellos until then.',
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
            FilledButton(onPressed: _call, child: Text('Call $parent')),
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
