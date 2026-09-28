import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Family voice notes: a child records one, the parent plays the latest.
/// A paid extra (family_plan) — screens check
/// [SubscriptionService.isEntitled] before calling [send], the same way the
/// paywall and photos already gate.
abstract interface class VoiceNoteRepository {
  /// Uploads [aacBytes] as the family's newest voice note. Only a signed-in
  /// child of [familyId] can do this; the server rejects anyone else.
  Future<void> send({required String familyId, required Uint8List aacBytes});

  /// A short-lived URL for the family's most recent voice note, or null if
  /// the family hasn't sent one yet.
  Future<String?> latest(String familyId);
}

class SupabaseVoiceNoteRepository implements VoiceNoteRepository {
  SupabaseVoiceNoteRepository(this._db);

  final SupabaseClient _db;

  static const _bucket = 'family-voice-notes';

  /// How long a fetched voice note URL stays valid; long enough for one
  /// open of the parent's home screen.
  static const _urlLifetime = Duration(hours: 1);

  @override
  Future<void> send({
    required String familyId,
    required Uint8List aacBytes,
  }) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Sign in to send a voice note.');
    }
    final member = await _db
        .from('members')
        .select('id')
        .eq('family_id', familyId)
        .eq('user_id', userId)
        .eq('role', 'child')
        .single();
    final memberId = member['id'] as String;

    // Only the newest voice note is ever heard, so the older ones are
    // cleared out rather than left to run up the storage bill.
    final older = await _db
        .from('family_voice_notes')
        .select('id, storage_path')
        .eq('family_id', familyId);

    final path = '$familyId/${DateTime.now().microsecondsSinceEpoch}.aac';
    await _db.storage
        .from(_bucket)
        .uploadBinary(
          path,
          aacBytes,
          fileOptions: const FileOptions(contentType: 'audio/aac'),
        );
    await _db.from('family_voice_notes').insert({
      'family_id': familyId,
      'member_id': memberId,
      'storage_path': path,
    });

    if (older.isNotEmpty) {
      try {
        await _db.storage.from(_bucket).remove([
          for (final row in older) row['storage_path'] as String,
        ]);
        await _db.from('family_voice_notes').delete().inFilter('id', [
          for (final row in older) row['id'] as String,
        ]);
      } catch (error) {
        // The new voice note is already sent; a leftover old one just
        // means one extra object until the next send cleans it up.
        debugPrint('Clearing older family voice notes: $error');
      }
    }
  }

  @override
  Future<String?> latest(String familyId) async {
    final row = await _db
        .from('family_voice_notes')
        .select('storage_path')
        .eq('family_id', familyId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    final path = row?['storage_path'] as String?;
    if (path == null) return null;
    return _db.storage
        .from(_bucket)
        .createSignedUrl(path, _urlLifetime.inSeconds);
  }
}
