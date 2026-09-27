import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../family/family_repository.dart';
import '../placeholder/family.dart';
import '../theme/palette.dart';
import '../widgets/paper_card.dart';
import '../widgets/sun_painter.dart';

/// One parent on the child's home. Until [joined], the card is the invite
/// with [parentCode]. After that, a [parentCode] is a pending code for a
/// reinstalled or new phone. [childCode] lets brothers and sisters in.
typedef ChildParent = ({
  String name,
  bool joined,
  String? parentCode,
  String? childCode,
  VoidCallback? onNewPhone,
});

/// The child's home answers one question before anything else:
/// "How is Mom?" A child looking after both parents in separate homes sees
/// one card for each.
class ChildHomeScreen extends StatelessWidget {
  const ChildHomeScreen({
    super.key,
    this.view = ChildView.heard,
    this.parents = const [
      (
        name: PlaceholderFamily.parentName,
        joined: true,
        parentCode: null,
        childCode: null,
        onNewPhone: null,
      ),
    ],
    this.childName = PlaceholderFamily.childName,
    this.onAddParent,
    this.onRefresh,
  });

  final ChildView view;
  final List<ChildParent> parents;
  final String? childName;

  /// Sets up another parent who lives apart, such as Dad.
  final VoidCallback? onAddParent;

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
        for (final parent in parents) ...[
          const SizedBox(height: 18),
          // A family whose parent code was used up without a parent row
          // falls back to the hero, whose "New phone" makes a fresh one.
          if (parent.joined || parent.parentCode == null)
            _ParentHero(view: view, parent: parent)
          else
            _InviteCard(code: parent.parentCode!, parent: parent.name),
        ],
        if (onAddParent != null) ...[
          const SizedBox(height: 20),
          Center(
            child: TextButton(
              onPressed: onAddParent,
              child: const Text('Add a parent who lives apart'),
            ),
          ),
        ],
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
          _CodeBlock(code: code),
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

/// A code to read out or send: large, in two groups of four, with a copy
/// button. Scales down rather than wrapping, so it reads as one line.
class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.code});

  final String code;

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Code copied')));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: SelectableText(
            displayInviteCode(code),
            semanticsLabel: 'Family code ${code.split('').join(' ')}',
            style: text.displayMedium?.copyWith(fontSize: 44, letterSpacing: 4),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => _copy(context),
          child: const Text('Copy the code'),
        ),
      ],
    );
  }
}

class _ParentHero extends StatefulWidget {
  const _ParentHero({required this.view, required this.parent});

  final ChildView view;
  final ChildParent parent;

  @override
  State<_ParentHero> createState() => _ParentHeroState();
}

class _ParentHeroState extends State<_ParentHero> {
  var _loveSent = false;

  void _sendLove() {
    setState(() => _loveSent = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${widget.parent.name} will see your love.')),
    );
  }

  /// Kept off the card so nobody reads the parent this code by mistake.
  void _showChildCode(String code) {
    final text = Theme.of(context).textTheme;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Palette.paper,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('For brothers and sisters', style: text.headlineMedium),
              const SizedBox(height: 10),
              Text(
                'They sign in with Google, tap “I have a code from my family” '
                'and type this. It’s not for ${widget.parent.name}’s phone.',
                style: text.bodyLarge?.copyWith(color: Palette.inkSoft),
              ),
              const SizedBox(height: 20),
              _CodeBlock(code: code),
            ],
          ),
        ),
      ),
    );
  }

  /// The old phone stops once the new one joins, so ask first.
  Future<void> _confirmNewPhone() async {
    final parent = widget.parent.name;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Palette.paper,
        title: Text('A new phone for $parent?'),
        content: Text(
          'You’ll get a new code for it. Once $parent types it there, '
          'the old phone stops saying good morning.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Get a code'),
          ),
        ],
      ),
    );
    if (yes ?? false) widget.parent.onNewPhone!();
  }

  void _call() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Calling isn’t set up yet.')));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final parent = widget.parent.name;
    final newPhoneCode = widget.parent.parentCode;
    final childCode = widget.parent.childCode;

    // No parent in the family and no code waiting: say what's needed.
    final needsCode = !widget.parent.joined;
    final (warmth, top, title, line) = switch (widget.view) {
      _ when needsCode => (
        0.6,
        Palette.sky,
        '$parent’s phone needs a new code',
        'Get one below and type it on $parent’s phone.',
      ),
      ChildView.connected => (
        0.8,
        Palette.glow,
        '$parent is all set',
        'Their good mornings will show up here.',
      ),
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
            FilledButton(onPressed: _call, child: Text('Call $parent')),
          ],
          if (newPhoneCode != null) ...[
            const SizedBox(height: 28),
            Text(
              'For $parent’s new phone: tap “I have a code” and type',
              style: text.bodyMedium?.copyWith(color: Palette.inkSoft),
            ),
            const SizedBox(height: 12),
            _CodeBlock(code: newPhoneCode),
          ] else if (widget.parent.onNewPhone != null) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: _confirmNewPhone,
              child: Text('New phone for $parent?'),
            ),
          ],
          if (childCode != null)
            TextButton(
              onPressed: () => _showChildCode(childCode),
              child: const Text('Invite a brother or sister'),
            ),
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
