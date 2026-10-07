import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../family/checkin_repository.dart';
import '../family/family_repository.dart';
import '../placeholder/family.dart';
import '../services/subscription.dart';
import '../theme/palette.dart';
import '../widgets/paper_card.dart';
import '../widgets/sun_painter.dart';
import '../widgets/voice_note_recorder_sheet.dart';
import '../widgets/whole_words_text.dart';
import 'paywall_screen.dart';

/// One parent on the child's home. Until [joined], the card is the invite
/// with [parentCode]. After that, a [parentCode] is a pending code for a
/// reinstalled or new phone. [childCode] lets brothers and sisters in.
typedef ChildParent = ({
  String name,
  bool joined,
  String? parentCode,
  String? childCode,
  VoidCallback? onNewPhone,

  /// Moves when this parent's mornings usually start by. Null hides the
  /// change, such as in the design preview.
  Future<void> Function(int hour, int minute)? onSetUsualBy,

  /// Sends a heart for today's good morning. Null keeps "Send love" local
  /// only, such as in the design preview.
  Future<void> Function()? onSendLove,

  /// Sends a photo to sit in this parent's photo frame. Null hides "Send a
  /// photo", such as in the design preview.
  Future<void> Function(Uint8List jpegBytes)? onSendPhoto,

  /// Sends a short voice note for this parent to play. Null hides "Send a
  /// voice note", such as in the design preview.
  Future<void> Function(Uint8List aacBytes)? onSendVoiceNote,

  /// Reads this parent's real morning, once, when their card appears.
  /// Overrides [ChildHomeScreen.view] for this card. Null keeps that
  /// screen-level view, as in the design preview.
  Future<FamilyStatus?> Function()? loadStatus,
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
        onSendLove: null,
        onSetUsualBy: null,
        onSendPhoto: null,
        onSendVoiceNote: null,
        loadStatus: null,
      ),
    ],
    this.childName = PlaceholderFamily.childName,
    this.onAddParent,
    this.onRefresh,
    this.onDeleteAccount,
    this.subscription,
  });

  final ChildView view;
  final List<ChildParent> parents;
  final String? childName;

  /// Sets up another parent who lives apart, such as Dad.
  final VoidCallback? onAddParent;

  /// Pull down to look again, for example once the parent has joined.
  final Future<void> Function()? onRefresh;

  /// Deletes this person's account, after they confirm. Null hides it, such
  /// as in the design preview.
  final Future<void> Function()? onDeleteAccount;

  /// Lets this screen offer the family plan. Null hides that link, such as
  /// in the design preview.
  final SubscriptionService? subscription;

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
            _ParentHero(view: view, parent: parent, subscription: subscription)
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
        if (subscription != null) ...[
          const SizedBox(height: 4),
          Center(
            child: ValueListenableBuilder<bool>(
              valueListenable: subscription!.isEntitled,
              builder: (context, entitled, _) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => PaywallScreen(
                      subscription: subscription!,
                      parentName: parents.firstOrNull?.name,
                    ),
                  ),
                ),
                child: Text(entitled ? 'Family plan' : 'Get the family plan'),
              ),
            ),
          ),
        ],
        if (onDeleteAccount != null) ...[
          const SizedBox(height: 4),
          Center(
            child: TextButton(
              onPressed: () => _confirmDelete(context),
              style: TextButton.styleFrom(foregroundColor: Palette.inkSoft),
              child: const Text('Delete my account'),
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

  Future<void> _confirmDelete(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Palette.paper,
        title: const Text('Delete your account?'),
        content: const Text(
          'Your photos and voice notes go with it. If you’re the last one '
          'in a family, that family goes too, and its phone stops saying '
          'good morning. If you pay for the family plan, cancel it in '
          'Google Play as well.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes ?? false) await onDeleteAccount!();
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
            child: WholeWordsText(
              'Now, $parent’s phone',
              style: text.displayMedium,
            ),
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
  const _ParentHero({
    required this.view,
    required this.parent,
    this.subscription,
  });

  final ChildView view;
  final ChildParent parent;

  /// Gates "Send a photo" behind the family plan. Null hides the button.
  final SubscriptionService? subscription;

  @override
  State<_ParentHero> createState() => _ParentHeroState();
}

class _ParentHeroState extends State<_ParentHero> {
  var _loveSent = false;
  var _sendingPhoto = false;
  var _sendingVoiceNote = false;
  ChildView? _liveView;
  DateTime? _checkedInAt;
  DateTime? _awayUntil;
  (int, int)? _usualBy;

  @override
  void initState() {
    super.initState();
    widget.parent.loadStatus
        ?.call()
        .catchError((Object error) {
          debugPrint('Loading ${widget.parent.name}’s morning: $error');
          return null;
        })
        .then((status) {
          if (status == null || !mounted) return;
          setState(() {
            _checkedInAt = status.checkedInAt;
            _awayUntil = status.awayUntil;
            _usualBy = status.usualByHour == null
                ? null
                : (status.usualByHour!, status.usualByMinute!);
            _liveView = status.away
                ? ChildView.away
                : status.checkedInToday
                ? ChildView.heard
                : ChildView.waiting;
          });
        });
  }

  Future<void> _sendLove() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _loveSent = true);
    try {
      await widget.parent.onSendLove?.call();
    } catch (error) {
      debugPrint('Sending love: $error');
      if (mounted) setState(() => _loveSent = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('That didn’t go through. Try again?')),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(content: Text('${widget.parent.name} will see your love.')),
    );
  }

  Future<void> _sendPhoto() async {
    final subscription = widget.subscription;
    if (subscription == null) return;
    if (!subscription.isEntitled.value) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => PaywallScreen(
            subscription: subscription,
            parentName: widget.parent.name,
          ),
        ),
      );
      return;
    }
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 70,
    );
    if (picked == null || !mounted) return;
    setState(() => _sendingPhoto = true);
    try {
      await widget.parent.onSendPhoto!(await picked.readAsBytes());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.parent.name} will see it.')),
      );
    } catch (error) {
      debugPrint('Sending a family photo: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That didn’t go through. Try again?')),
      );
    } finally {
      if (mounted) setState(() => _sendingPhoto = false);
    }
  }

  Future<void> _sendVoiceNote() async {
    final subscription = widget.subscription;
    if (subscription == null) return;
    if (!subscription.isEntitled.value) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => PaywallScreen(
            subscription: subscription,
            parentName: widget.parent.name,
          ),
        ),
      );
      return;
    }
    final recorded = await showModalBottomSheet<Uint8List>(
      context: context,
      backgroundColor: Palette.paper,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) =>
          VoiceNoteRecorderSheet(parentName: widget.parent.name),
    );
    if (recorded == null || !mounted) return;
    setState(() => _sendingVoiceNote = true);
    try {
      await widget.parent.onSendVoiceNote!(recorded);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.parent.name} will hear it.')),
      );
    } catch (error) {
      debugPrint('Sending a family voice note: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That didn’t go through. Try again?')),
      );
    } finally {
      if (mounted) setState(() => _sendingVoiceNote = false);
    }
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
              WholeWordsText(
                'For brothers and sisters',
                style: text.headlineMedium,
              ),
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

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final parent = widget.parent.name;
    final newPhoneCode = widget.parent.parentCode;
    final childCode = widget.parent.childCode;

    // No parent in the family and no code waiting: say what's needed.
    final needsCode = !widget.parent.joined;
    final view = _liveView ?? widget.view;
    final (warmth, top, title, line) = switch (view) {
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
        _checkedInAt == null
            ? 'Today'
            : 'Today · ${_clock(context, _checkedInAt!)}',
      ),
      ChildView.waiting => (
        0.6,
        Palette.sky,
        'Haven’t heard from $parent yet',
        _usualBy == null
            ? 'You’ll hear when they say good morning.'
            : '$parent’s mornings usually start by '
                  '${_clock(context, DateTime(0, 1, 1, _usualBy!.$1, _usualBy!.$2))}.',
      ),
      ChildView.away => (
        0.45,
        Palette.paperDeep,
        '$parent is away',
        _awayUntil == null
            ? 'Morning hellos start again when they’re home.'
            : 'Back on ${MaterialLocalizations.of(context).formatMediumDate(_awayUntil!)}. '
                  'Morning hellos start again the day after.',
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
            child: WholeWordsText(title, style: text.displayMedium),
          ),
          const SizedBox(height: 10),
          Text(line, style: text.bodyLarge?.copyWith(color: Palette.inkSoft)),
          if (view == ChildView.heard) ...[
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _loveSent ? null : _sendLove,
              icon: const HeartMark(color: Palette.peach),
              label: WholeWordsText(_loveSent ? 'Love sent' : 'Send love'),
            ),
          ],
          if (widget.parent.onSendPhoto != null) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: _sendingPhoto ? null : _sendPhoto,
              child: Text(
                _sendingPhoto ? 'Sending…' : 'Send a photo for $parent’s frame',
              ),
            ),
          ],
          if (widget.parent.onSendVoiceNote != null) ...[
            const SizedBox(height: 4),
            TextButton(
              onPressed: _sendingVoiceNote ? null : _sendVoiceNote,
              child: Text(
                _sendingVoiceNote ? 'Sending…' : 'Send $parent a voice note',
              ),
            ),
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
          if (widget.parent.onSetUsualBy != null &&
              widget.parent.joined &&
              _usualBy != null)
            TextButton(
              onPressed: _changeUsualBy,
              child: Text(
                '$parent’s mornings start by '
                '${_clock(context, DateTime(0, 1, 1, _usualBy!.$1, _usualBy!.$2))}. Change?',
              ),
            ),
          if (childCode != null)
            TextButton(
              onPressed: () => _showChildCode(childCode),
              child: const Text('Invite a brother or sister'),
            ),
        ],
      ),
    );
  }

  /// The family hears if the parent hasn't said good morning by this time,
  /// so a late riser needs a later one.
  Future<void> _changeUsualBy() async {
    final parent = widget.parent.name;
    final messenger = ScaffoldMessenger.of(context);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _usualBy!.$1, minute: _usualBy!.$2),
      helpText: '$parent’s mornings usually start by',
    );
    if (picked == null || !mounted) return;
    // window_start sits at midnight, so the end must come after it.
    if (picked.hour == 0) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Pick a time after 1 AM.')),
      );
      return;
    }
    try {
      await widget.parent.onSetUsualBy!(picked.hour, picked.minute);
    } catch (error) {
      debugPrint('Changing the morning time: $error');
      messenger.showSnackBar(
        const SnackBar(content: Text('That didn’t go through. Try again?')),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _usualBy = (picked.hour, picked.minute));
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Done. You’ll only hear if $parent hasn’t said good morning by then.',
        ),
      ),
    );
  }

  /// Follows the phone's 12 or 24-hour setting.
  static String _clock(BuildContext context, DateTime time) {
    // Server times come back as UTC; toLocal() is a no-op on the wall-clock
    // DateTime built for the schedule's usual-by time.
    return MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(time.toLocal()),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
  }
}
