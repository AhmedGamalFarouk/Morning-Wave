import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Family photos: a child sends one, the parent sees the latest in their
/// photo frame. A paid extra (family_plan) — screens check
/// [SubscriptionService.isEntitled] before calling [send], the same way the
/// paywall already gates purchase.
abstract interface class PhotoRepository {
  /// Uploads [jpegBytes] as the family's newest photo. Only a signed-in
  /// child of [familyId] can do this; the server rejects anyone else.
  Future<void> send({required String familyId, required Uint8List jpegBytes});

  /// A short-lived URL for the family's most recent photo, or null if the
  /// family hasn't sent one yet.
  Future<String?> latest(String familyId);
}

class SupabasePhotoRepository implements PhotoRepository {
  SupabasePhotoRepository(this._db);

  final SupabaseClient _db;

  static const _bucket = 'family-photos';

  /// How long a fetched photo URL stays valid; long enough for one open of
  /// the parent's home screen.
  static const _urlLifetime = Duration(hours: 1);

  @override
  Future<void> send({
    required String familyId,
    required Uint8List jpegBytes,
  }) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return;
    final member = await _db
        .from('members')
        .select('id')
        .eq('family_id', familyId)
        .eq('user_id', userId)
        .eq('role', 'child')
        .single();
    final memberId = member['id'] as String;
    final path = '$familyId/${DateTime.now().microsecondsSinceEpoch}.jpg';
    await _db.storage
        .from(_bucket)
        .uploadBinary(
          path,
          jpegBytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
    await _db.from('family_photos').insert({
      'family_id': familyId,
      'member_id': memberId,
      'storage_path': path,
    });
  }

  @override
  Future<String?> latest(String familyId) async {
    final row = await _db
        .from('family_photos')
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
