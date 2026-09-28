import 'package:flutter/material.dart';

import '../family/auth.dart';
import '../family/family_repository.dart';
import '../placeholder/family.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../widgets/sun_painter.dart';
import 'child_home_screen.dart';
import 'join_family_screen.dart';
import 'parent_home_screen.dart';
import 'start_family_screen.dart';
import 'welcome_screen.dart';

/// Picks the screen from who is signed in and which families they're in:
/// welcome, a family code, the child's family setup, or a home.
class AppGate extends StatefulWidget {
  const AppGate({
    super.key,
    required this.auth,
    required this.families,
    required this.cache,
    this.requestNotificationPermission,
    this.notificationsEnabled,
  });

  final Auth auth;
  final FamilyRepository families;
  final FamilyCache cache;
  final Future<bool> Function()? requestNotificationPermission;
  final Future<bool> Function()? notificationsEnabled;

  @override
  State<AppGate> createState() => _AppGateState();
}

/// Said when the network or server is out of reach. Never blames anyone.
const _cantReach =
    'We can’t reach Morning Wave just now. Try again in a moment.';

class _AppGateState extends State<AppGate> {
  /// Null until known; empty when the person isn't in a family yet.
  List<Membership>? _families;
  var _loading = false;
  var _unreachable = false;
  var _signingIn = false;
  var _enteringCode = false;
  var _addingParent = false;

  Auth get _auth => widget.auth;

  /// How this person appears to the rest of the family.
  String get _myName => _auth.childFirstName ?? 'Family member';

  @override
  void initState() {
    super.initState();
    if (_auth.isSignedIn) _start();
  }

  /// Opens on the families seen last time, then checks in the background,
  /// so a parent with no signal still lands on their Morning Sun.
  Future<void> _start() async {
    setState(() => _loading = true);
    List<Membership>? cached;
    try {
      cached = await widget.cache.read();
    } catch (error) {
      debugPrint('Reading saved families: $error');
    }
    if (!mounted) return;
    setState(() {
      _families = cached;
      _loading = cached == null;
    });
    await _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _unreachable = false);
    try {
      final families = await widget.families.myFamilies();
      if (!mounted) return;
      setState(() => _families = families);
      await widget.cache.write(families);
    } catch (error) {
      debugPrint('Loading families: $error');
      // Without knowing the families, setup could make a duplicate. With
      // saved ones, keep showing them and say nothing.
      if (mounted && _families == null) setState(() => _unreachable = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _say(String words) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(words)));
  }

  Future<void> _continueWithGoogle() async {
    setState(() => _signingIn = true);
    try {
      if (await _auth.signInWithGoogle()) {
        setState(() => _loading = true);
        await _refresh();
      }
    } catch (error) {
      debugPrint('Google sign-in: $error');
      _say('Google sign-in didn’t finish. Try again?');
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Future<String?> _join(String code) async {
    final before = _families?.length ?? 0;
    try {
      await _auth.signInAsParent();
      await widget.families.joinFamily(code, myName: _myName);
    } on UnknownInviteCode {
      // A retry after a lost answer also lands here: the first try may
      // have joined already.
      if (await _joinedSince(before)) return null;
      return 'That code isn’t one we know yet. Check it with your family '
          'and try once more.';
    } on AlreadyInFamily {
      // Also what a retry after a lost answer gets.
      if (await _joinedSince(before)) return null;
      return 'You’re already in this family. Go back to see them.';
    } on TooManyCodes {
      return 'Let’s take a little break. Try the code again in an hour.';
    } catch (error) {
      debugPrint('Joining a family: $error');
      return _cantReach;
    }
    await _refresh();
    if (!mounted) return null;
    setState(() => _enteringCode = false);
    return null;
  }

  /// True when a fresh look finds more than [before] families, so a request
  /// whose answer was lost isn't repeated.
  Future<bool> _joinedSince(int before) async {
    await _refresh();
    final found = (_families?.length ?? 0) > before;
    if (found && mounted) {
      setState(() {
        _enteringCode = false;
        _addingParent = false;
      });
    }
    return found;
  }

  /// Back from the code screen. A parent account that never joined a family
  /// is dropped, so a child who took the wrong path can still reach Google.
  Future<void> _leaveCode() async {
    if (_auth.isParentAccount && (_families?.isEmpty ?? true)) {
      await _auth.signOut();
      await widget.cache.write(null);
      if (!mounted) return;
      setState(() => _families = null);
    }
    setState(() => _enteringCode = false);
  }

  Future<String?> _startFamily(String parentName) async {
    final before = _families?.length ?? 0;
    try {
      await widget.families.createFamily(
        parentName: parentName,
        myName: _myName,
      );
    } catch (error) {
      debugPrint('Creating a family: $error');
      // The family may exist even though the answer never arrived.
      return await _joinedSince(before) ? null : _cantReach;
    }
    await _joinedSince(before);
    return null;
  }

  Future<void> _newParentCode(Membership family) async {
    try {
      await widget.families.newParentCode(family.familyId);
      await _refresh();
    } catch (error) {
      debugPrint('New parent code: $error');
      _say(_cantReach);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (key, screen, back) = _screen();
    return PopScope(
      // Android's back key does what the on-screen Back does.
      canPop: back == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) back?.call();
      },
      child: AnimatedSwitcher(
        duration: Motion.crossfade,
        switchInCurve: Motion.fadeIn,
        switchOutCurve: Motion.fadeOut,
        child: KeyedSubtree(key: ValueKey(key), child: screen),
      ),
    );
  }

  /// The screen to show, a key for crossfading, and what Back does.
  (String, Widget, VoidCallback?) _screen() {
    if (_loading) return ('dawn', const _Dawn(), null);
    if (_unreachable) return ('retry', _Dawn(onRetry: _start), null);
    final families = _families ?? const [];
    final parentOf = families.where((f) => f.role == FamilyRole.parent);
    if (parentOf.isNotEmpty) {
      return (
        'parent',
        ParentHomeScreen(
          parentName: parentOf.first.parentName,
          requestNotificationPermission: widget.requestNotificationPermission,
          notificationsEnabled: widget.notificationsEnabled,
        ),
        null,
      );
    }
    if (_enteringCode || (_auth.isParentAccount && families.isEmpty)) {
      return (
        'code',
        JoinFamilyScreen(onJoin: _join, onBack: _leaveCode),
        _leaveCode,
      );
    }
    final googleChild = _auth.isSignedIn && !_auth.isParentAccount;
    if (googleChild && (families.isEmpty || _addingParent)) {
      final back = families.isEmpty
          ? null
          : () => setState(() => _addingParent = false);
      return (
        'start',
        StartFamilyScreen(
          childName: _auth.childFirstName,
          onStart: _startFamily,
          onBack: back,
          onHaveCode: () => setState(() => _enteringCode = true),
        ),
        back,
      );
    }
    if (families.isNotEmpty) {
      return (
        'child',
        ChildHomeScreen(
          view: ChildView.connected,
          childName: _auth.childFirstName,
          parents: [
            for (final family in families)
              (
                name: family.parentName,
                joined: family.parentJoined,
                parentCode: family.parentCode,
                childCode: family.childCode,
                onNewPhone: () => _newParentCode(family),
              ),
          ],
          onAddParent: googleChild
              ? () => setState(() => _addingParent = true)
              : null,
          onRefresh: _refresh,
        ),
        null,
      );
    }
    return (
      'welcome',
      WelcomeScreen(
        busy: _signingIn,
        onSetUpForParent: _continueWithGoogle,
        onHaveCode: () => setState(() => _enteringCode = true),
      ),
      null,
    );
  }
}

/// A quiet sun while the family loads, never a spinner. With [onRetry] it
/// says the app is out of reach and offers to look again.
class _Dawn extends StatelessWidget {
  const _Dawn({this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SunMark(size: 96, warmth: 0.6),
                if (onRetry != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    _cantReach,
                    textAlign: TextAlign.center,
                    style: text.bodyLarge,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: onRetry,
                    style: parentPrimaryButton(context),
                    child: const Text('Try again'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
