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
  /// Null until loaded; empty when the person isn't in a family yet.
  List<Membership>? _families;
  var _loading = false;
  var _unreachable = false;
  var _signingIn = false;
  var _enteringCode = false;
  var _addingParent = false;

  @override
  void initState() {
    super.initState();
    if (widget.auth.isSignedIn) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _families == null;
      _unreachable = false;
    });
    try {
      final families = await widget.families.myFamilies();
      if (mounted) setState(() => _families = families);
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
      await widget.families.joinFamily(code);
      await _load();
      return null;
    } on UnknownInviteCode {
      return 'That code isn’t one we know yet. Check it with your family '
          'and try once more.';
    } catch (error) {
      debugPrint('Joining a family: $error');
      return _cantReach;
    }
  }

  /// From the code screen back to welcome. A parent account that never
  /// joined a family is dropped, so a child who tapped the wrong path can
  /// still reach Google sign-in.
  Future<void> _leaveCode() async {
    if (widget.auth.isSignedIn) await widget.auth.signOut();
    if (mounted) {
      setState(() {
        _enteringCode = false;
        _families = null;
      });
    }
  }

  Future<String?> _startFamily(String parentName) async {
    try {
      await widget.families.createFamily(parentName: parentName);
      await _load();
      if (mounted) setState(() => _addingParent = false);
      return null;
    } catch (error) {
      debugPrint('Creating a family: $error');
      return _cantReach;
    }
  }

  Future<void> _newParentCode(Membership family) async {
    try {
      await widget.families.newParentCode(family.familyId);
      await _load();
    } catch (error) {
      debugPrint('New parent code: $error');
      _say(_cantReach);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _Dawn();
    if (_unreachable) return _Dawn(onRetry: _load);
    final families = _families ?? const [];
    final parentOf = families.where((f) => f.role == FamilyRole.parent);
    if (parentOf.isNotEmpty) {
      return ParentHomeScreen(
        parentName: parentOf.first.parentName,
        requestNotificationPermission: widget.requestNotificationPermission,
        notificationsEnabled: widget.notificationsEnabled,
      );
    }
    final signedInChild =
        widget.auth.isSignedIn && !widget.auth.isParentAccount;
    if (signedInChild && (families.isEmpty || _addingParent)) {
      return StartFamilyScreen(
        childName: widget.auth.childFirstName,
        onStart: _startFamily,
        onBack: families.isEmpty
            ? null
            : () => setState(() => _addingParent = false),
      );
    }
    if (signedInChild) {
      return ChildHomeScreen(
        childName: widget.auth.childFirstName,
        parents: [
          for (final family in families)
            (
              name: family.parentName,
              inviteCode: family.parentJoined ? null : family.inviteCode,
              onNewPhone: () => _newParentCode(family),
            ),
        ],
        onAddParent: () => setState(() => _addingParent = true),
        onRefresh: _load,
      );
    }
    if (_enteringCode || widget.auth.isSignedIn) {
      return JoinFamilyScreen(onJoin: _join, onBack: _leaveCode);
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
