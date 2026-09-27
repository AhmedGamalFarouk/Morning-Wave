import 'package:flutter/material.dart';

import '../family/auth.dart';
import '../family/family_repository.dart';
import '../widgets/sun_painter.dart';
import 'child_home_screen.dart';
import 'join_family_screen.dart';
import 'parent_home_screen.dart';
import 'start_family_screen.dart';
import 'welcome_screen.dart';

/// Picks the screen from who is signed in and which family they're in:
/// welcome, the parent's code, the child's family setup, or a home.
class AppGate extends StatefulWidget {
  const AppGate({
    super.key,
    required this.auth,
    required this.families,
    this.requestNotificationPermission,
    this.notificationsEnabled,
  });

  final Auth auth;
  final FamilyRepository families;
  final Future<bool> Function()? requestNotificationPermission;
  final Future<bool> Function()? notificationsEnabled;

  @override
  State<AppGate> createState() => _AppGateState();
}

/// Said when the network or server is out of reach. Never blames anyone.
const _cantReach =
    'We can’t reach Morning Wave just now. Try again in a moment.';

class _AppGateState extends State<AppGate> {
  Membership? _membership;
  var _loading = false;
  var _unreachable = false;
  var _signingIn = false;
  var _enteringCode = false;

  @override
  void initState() {
    super.initState();
    if (widget.auth.isSignedIn) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _unreachable = false;
    });
    try {
      final membership = await widget.families.myMembership();
      if (mounted) setState(() => _membership = membership);
    } catch (error) {
      debugPrint('Loading the family: $error');
      // Without knowing the family, setup could make a second one.
      if (mounted) setState(() => _unreachable = true);
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
      if (await widget.auth.signInWithGoogle()) await _load();
    } catch (error) {
      debugPrint('Google sign-in: $error');
      _say('Google sign-in didn’t finish. Try again?');
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Future<String?> _join(String code) async {
    try {
      await widget.auth.signInAsParent();
      final membership = await widget.families.joinFamily(code);
      if (mounted) setState(() => _membership = membership);
      return null;
    } on UnknownInviteCode {
      return 'That code isn’t one we know yet. Check it with your family '
          'and try once more.';
    } catch (error) {
      debugPrint('Joining a family: $error');
      return _cantReach;
    }
  }

  Future<String?> _startFamily(String parentName) async {
    try {
      final membership = await widget.families.createFamily(
        parentName: parentName,
      );
      if (mounted) setState(() => _membership = membership);
      return null;
    } catch (error) {
      debugPrint('Creating a family: $error');
      return _cantReach;
    }
  }

  @override
  Widget build(BuildContext context) {
    final membership = _membership;
    if (_loading) return const _Dawn();
    if (_unreachable) return _Dawn(onRetry: _load);
    if (membership != null) {
      return switch (membership.role) {
        FamilyRole.parent => ParentHomeScreen(
          parentName: membership.parentName,
          requestNotificationPermission: widget.requestNotificationPermission,
          notificationsEnabled: widget.notificationsEnabled,
        ),
        FamilyRole.child => ChildHomeScreen(
          parentName: membership.parentName,
          childName: widget.auth.childFirstName,
          inviteCode: membership.parentJoined ? null : membership.inviteCode,
          onRefresh: _load,
        ),
      };
    }
    // Signed in without a family: the child sets one up, and a parent
    // whose code didn't go through yet goes back to their code.
    if (widget.auth.isSignedIn && !widget.auth.isParentAccount) {
      return StartFamilyScreen(
        childName: widget.auth.childFirstName,
        onStart: _startFamily,
      );
    }
    if (_enteringCode || widget.auth.isSignedIn) {
      return JoinFamilyScreen(
        onJoin: _join,
        onBack: widget.auth.isSignedIn
            ? null
            : () => setState(() => _enteringCode = false),
      );
    }
    return WelcomeScreen(
      busy: _signingIn,
      onSetUpForParent: _continueWithGoogle,
      onHaveCode: () => setState(() => _enteringCode = true),
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
