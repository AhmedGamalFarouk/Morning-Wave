import 'package:supabase_flutter/supabase_flutter.dart';

/// A family's morning, from `family_status` (see the migrations): whether
/// the parent has said good morning today, in the family's own day, and
/// whether they're away.
class FamilyStatus {
  const FamilyStatus({
    required this.checkedInToday,
    this.checkedInAt,
    required this.away,
    this.awayUntil,
    this.usualByHour,
    this.usualByMinute,
  });

  final bool checkedInToday;
  final DateTime? checkedInAt;
  final bool away;

  /// The day the parent said they'd be back, inclusive.
  final DateTime? awayUntil;

  /// The family's schedule window end (schedules.window_end), for "usually
  /// starts by 9:00 AM". Null only if the family has no schedule.
  final int? usualByHour;
  final int? usualByMinute;
}

/// Every call the app makes about today's check-in. `family_status` owns the
/// "checked in / away" logic; this only reads it and records taps.
abstract interface class CheckinRepository {
  /// This family's morning right now.
  Future<FamilyStatus> status(String familyId);

  /// Records a good morning. Only the signed-in parent of [familyId] may
  /// call this; the server rejects anyone else.
  Future<void> checkIn(String familyId);

  /// Tells the family the parent will be away through [backOn], inclusive.
  /// Null clears away mode.
  Future<void> setAway(String familyId, DateTime? backOn);
}

class SupabaseCheckinRepository implements CheckinRepository {
  SupabaseCheckinRepository(this._db);

  final SupabaseClient _db;

  @override
  Future<FamilyStatus> status(String familyId) async {
    final row = await _db
        .from('family_status')
        .select()
        .eq('family_id', familyId)
        .single();
    final usualBy = (row['usual_by'] as String?)?.split(':');
    final checkedInAt = row['checked_in_at'] as String?;
    final awayUntil = row['away_until'] as String?;
    return FamilyStatus(
      checkedInToday: row['checked_in_today'] as bool,
      checkedInAt: checkedInAt == null ? null : DateTime.parse(checkedInAt),
      away: row['away'] as bool,
      awayUntil: awayUntil == null ? null : DateTime.parse(awayUntil),
      usualByHour: usualBy == null ? null : int.parse(usualBy[0]),
      usualByMinute: usualBy == null ? null : int.parse(usualBy[1]),
    );
  }

  @override
  Future<void> checkIn(String familyId) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Sign in to say good morning.');
    }
    final member = await _db
        .from('members')
        .select('id')
        .eq('family_id', familyId)
        .eq('user_id', userId)
        .eq('role', 'parent')
        .single();
    await _db.from('checkins').insert({
      'family_id': familyId,
      'member_id': member['id'],
      'source': 'tap',
    });
  }

  @override
  Future<void> setAway(String familyId, DateTime? backOn) async {
    // Noon on the chosen day, in whatever zone this phone is in. The parent's
    // own phone set the family's time zone (see joinFamily), so this lands
    // on the intended calendar day once the server reads it back in that
    // zone.
    final pausedUntil = backOn == null
        ? null
        : DateTime(
            backOn.year,
            backOn.month,
            backOn.day,
            12,
          ).toUtc().toIso8601String();
    await _db
        .from('schedules')
        .update({'paused_until': pausedUntil})
        .eq('family_id', familyId);
  }
}
