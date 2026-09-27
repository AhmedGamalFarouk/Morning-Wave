import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum FamilyRole { parent, child }

/// The signed-in person's place in one family.
class Membership {
  const Membership({
    required this.familyId,
    required this.role,
    required this.parentName,
    required this.childCode,
    required this.parentJoined,
    this.parentCode,
  });

  final String familyId;
  final FamilyRole role;

  /// What the children call the parent ("Mom"); the parent is greeted by it.
  final String parentName;

  /// Lets the parent's phone in once. Null after it's used, until a child
  /// asks for a new one for a reinstalled or new phone.
  final String? parentCode;

  /// Lets brothers and sisters join, any number of times.
  final String childCode;
  final bool parentJoined;

  Map<String, Object?> toJson() => {
    'familyId': familyId,
    'role': role.name,
    'parentName': parentName,
    'parentCode': parentCode,
    'childCode': childCode,
    'parentJoined': parentJoined,
  };

  factory Membership.fromJson(Map<String, dynamic> json) => Membership(
    familyId: json['familyId'] as String,
    role: FamilyRole.values.byName(json['role'] as String),
    parentName: json['parentName'] as String,
    parentCode: json['parentCode'] as String?,
    childCode: json['childCode'] as String,
    parentJoined: json['parentJoined'] as bool,
  );
}

/// Thrown when an invite code doesn't lead to a family.
class UnknownInviteCode implements Exception {
  const UnknownInviteCode();
}

/// Thrown after too many codes that didn't lead to a family.
class TooManyCodes implements Exception {
  const TooManyCodes();
}

/// Every call the app makes about families. The database functions
/// `create_family`, `join_family` and `reinvite_parent` own the rules; this
/// only calls them.
abstract interface class FamilyRepository {
  /// Empty until the person creates or joins a family. A grown child can
  /// be in several: one per parent, when parents live apart.
  Future<List<Membership>> myFamilies();

  Future<void> createFamily({
    required String parentName,
    required String myName,
  });

  /// The code decides the role. Throws [UnknownInviteCode] or [TooManyCodes].
  Future<void> joinFamily(String code, {required String myName});

  /// A fresh parent code for a reinstalled or new phone. The parent stays in
  /// the family until the new phone joins with it.
  Future<void> newParentCode(String familyId);
}

class SupabaseFamilyRepository implements FamilyRepository {
  SupabaseFamilyRepository(this._db, {Future<String> Function()? timeZone})
    : _timeZone = timeZone ?? _deviceTimeZone;

  final SupabaseClient _db;

  /// This phone's full IANA zone ("Africa/Cairo"); mornings are counted in
  /// the parent's.
  final Future<String> Function() _timeZone;

  static Future<String> _deviceTimeZone() async =>
      (await FlutterTimezone.getLocalTimezone()).identifier;

  @override
  Future<List<Membership>> myFamilies() async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return const [];
    final rows = await _db
        .from('members')
        .select(
          'role, families(id, parent_name, parent_code, child_code, '
          'members(role))',
        )
        .eq('user_id', userId)
        .order('created_at');
    return rows.map(_membership).toList();
  }

  @override
  Future<void> createFamily({
    required String parentName,
    required String myName,
  }) async {
    await _db.rpc(
      'create_family',
      // The child's zone to start with; the parent's phone corrects it
      // when it joins, for a parent who lives elsewhere.
      params: {
        'parent_name': parentName,
        'my_name': myName,
        'time_zone': await _timeZone(),
      },
    );
  }

  @override
  Future<void> joinFamily(String code, {required String myName}) async {
    final Object? family;
    try {
      family = await _db.rpc(
        'join_family',
        params: {'code': code, 'my_name': myName},
      );
    } on PostgrestException catch (error) {
      if (error.code == 'PT429') throw const TooManyCodes();
      rethrow;
    }
    if (!joinedAFamily(family)) throw const UnknownInviteCode();
    final row = (family is List ? family.first : family) as Map;
    await _useMyTimeZoneIfParent(row['id'] as String);
  }

  /// Best effort: a missed update leaves the child's zone, which is right
  /// for most families, and must not stop the parent getting in.
  Future<void> _useMyTimeZoneIfParent(String familyId) async {
    try {
      final me = await _db
          .from('members')
          .select('role')
          .eq('family_id', familyId)
          .eq('user_id', _db.auth.currentUser!.id)
          .single();
      if (me['role'] != FamilyRole.parent.name) return;
      await _db
          .from('schedules')
          .update({'time_zone': await _timeZone()})
          .eq('family_id', familyId);
    } catch (error) {
      debugPrint('Saving the parent’s time zone: $error');
    }
  }

  @override
  Future<void> newParentCode(String familyId) async {
    await _db.rpc('reinvite_parent', params: {'family_id': familyId});
  }

  static Membership _membership(Map<String, dynamic> row) {
    final family = row['families'] as Map<String, dynamic>;
    final roles = (family['members'] as List).map((m) => m['role']);
    return Membership(
      familyId: family['id'] as String,
      role: FamilyRole.values.byName(row['role'] as String),
      parentName: family['parent_name'] as String,
      parentCode: family['parent_code'] as String?,
      childCode: family['child_code'] as String,
      parentJoined: roles.contains(FamilyRole.parent.name),
    );
  }
}

/// The last families seen, so the app opens straight to the right home
/// even before the network answers.
abstract interface class FamilyCache {
  Future<List<Membership>?> read();
  Future<void> write(List<Membership>? families);
}

class PrefsFamilyCache implements FamilyCache {
  static const _key = 'families';

  @override
  Future<List<Membership>?> read() async {
    final json = (await SharedPreferences.getInstance()).getString(_key);
    if (json == null) return null;
    return [
      for (final item in jsonDecode(json) as List)
        Membership.fromJson(item as Map<String, dynamic>),
    ];
  }

  @override
  Future<void> write(List<Membership>? families) async {
    final prefs = await SharedPreferences.getInstance();
    if (families == null) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(
        _key,
        jsonEncode([for (final f in families) f.toJson()]),
      );
    }
  }
}

/// What join_family returned names a family. A wrong code comes back as
/// nothing: null, an empty list, or a row of nulls, depending on how
/// PostgREST shapes the function's result.
bool joinedAFamily(Object? result) {
  final row = result is List ? result.firstOrNull : result;
  return row is Map && row['id'] != null;
}

/// "KX7PQ2MA" shown as "KX7P Q2MA", easier to read out over the phone. The
/// server ignores spaces, dashes and case, so what's typed is sent as is.
String displayInviteCode(String code) =>
    code.length == 8 ? '${code.substring(0, 4)} ${code.substring(4)}' : code;
