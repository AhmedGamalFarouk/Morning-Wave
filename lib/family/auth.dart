import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

/// Who is signed in, and the two ways in: Google for the grown child, and
/// an anonymous account for the parent, who never types a password.
abstract interface class Auth {
  bool get isSignedIn;

  /// Parents sign in without an account of their own.
  bool get isParentAccount;

  /// The grown child's first name from their Google account, if known.
  String? get childFirstName;

  /// Returns false when the person closed Google's sheet without choosing.
  Future<bool> signInWithGoogle();

  Future<void> signInAsParent();
}

class SupabaseAuth implements Auth {
  SupabaseAuth(this._auth);

  final GoTrueClient _auth;
  Future<void>? _googleReady;

  @override
  bool get isSignedIn => _auth.currentUser != null;

  @override
  bool get isParentAccount => _auth.currentUser?.isAnonymous ?? false;

  @override
  String? get childFirstName {
    final name = _auth.currentUser?.userMetadata?['full_name'] as String?;
    return name?.trim().split(' ').first;
  }

  @override
  Future<bool> signInWithGoogle() async {
    final google = GoogleSignIn.instance;
    // Supabase checks the ID token against the web client ID.
    try {
      await (_googleReady ??= google.initialize(
        serverClientId: AppConfig.googleWebClientId,
      ));
    } catch (_) {
      _googleReady = null;
      rethrow;
    }
    final GoogleSignInAccount account;
    try {
      account = await google.authenticate();
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) return false;
      rethrow;
    }
    final idToken = account.authentication.idToken;
    if (idToken == null) throw StateError('Google returned no ID token.');
    await _auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
    );
    return true;
  }

  @override
  Future<void> signInAsParent() async {
    // A parent who typed a wrong code the first time keeps the same account.
    if (!isSignedIn) await _auth.signInAnonymously();
  }
}
