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

  /// Moves the time the parent's mornings usually start by (window_end),
  /// which is when the family would first hear if they haven't. In the
  /// family's own time zone.
  Future<void> setUsualBy(
    String familyId, {
    required int hour,
    required int minute,
  });

  /// A child's heart for today's good morning. Only a signed-in child of
  /// [familyId] may call this; the server rejects anyone else.
  Future<void> sendLove(String familyId);

  /// The names of the children who sent love today, oldest first, each
  /// once.
  Future<List<String>> lovedBy(String familyId);
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
  Future<void> setUsualBy(
    String familyId, {
    required int hour,
    required int minute,
  }) async {
    String two(int n) => n.toString().padLeft(2, '0');
    await _db
        .from('schedules')
        .update({
          // Nothing reads window_start; it only has to sit before the end.
          'window_start': '00:00',
          'window_end': '${two(hour)}:${two(minute)}',
        })
        .eq('family_id', familyId);
  }

  @override
  Future<void> sendLove(String familyId) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) throw StateError('Sign in to send love.');
    final member = await _db
        .from('members')
        .select('id')
        .eq('family_id', familyId)
        .eq('user_id', userId)
        .eq('role', 'child')
        .single();
    await _db.from('family_love').insert({
      'family_id': familyId,
      'member_id': member['id'],
    });
  }

  @override
  Future<List<String>> lovedBy(String familyId) async {
    // Love answers today's good morning, so count from this phone's midnight;
    // the parent's phone set the family's zone, so it's the family's day.
    final now = DateTime.now();
    final since = DateTime(now.year, now.month, now.day);
    final love = await _db
        .from('family_love')
        .select('member_id')
        .eq('family_id', familyId)
        .gt('created_at', since.toUtc().toIso8601String())
        .order('created_at');
    final ids = {for (final row in love) row['member_id'] as String};
    if (ids.isEmpty) return const [];
    final members = await _db
        .from('members')
        .select('id, display_name')
        .inFilter('id', ids.toList());
    final names = {
      for (final m in members) m['id'] as String: m['display_name'] as String,
    };
    return [for (final id in ids) ?names[id]];
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

/// When the parent's next "say good morning" reminder should ring: half an
/// hour before their morning window ends, so they hear it before the family
/// does. Skips today once they've said it, and the days they're away. Null
/// when the family has no schedule.
DateTime? nextMorningReminder(FamilyStatus status, DateTime now) {
  if (status.usualByHour == null) return null;
  if (status.away && status.awayUntil == null) return null;
  DateTime at(DateTime day) => DateTime(
    day.year,
    day.month,
    day.day,
    status.usualByHour!,
    status.usualByMinute!,
  ).subtract(const Duration(minutes: 30));
  var day = DateTime(now.year, now.month, now.day);
  if (status.away && status.awayUntil != null) {
    // Mornings resume the day after the parent is back.
    final back = status.awayUntil!;
    final resume = DateTime(back.year, back.month, back.day + 1);
    if (resume.isAfter(day)) day = resume;
  }
  if (status.checkedInToday || !at(day).isAfter(now)) {
    if (day == DateTime(now.year, now.month, now.day)) {
      day = DateTime(day.year, day.month, day.day + 1);
    }
  }
  return at(day);
}
