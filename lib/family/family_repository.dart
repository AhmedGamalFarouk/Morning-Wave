import 'package:supabase_flutter/supabase_flutter.dart';

enum FamilyRole { parent, child }

/// The signed-in person's place in their family.
class Membership {
  const Membership({
    required this.role,
    required this.parentName,
    required this.inviteCode,
    required this.parentJoined,
  });

  final FamilyRole role;

  /// What the family calls the parent ("Mom"); the parent is greeted by it.
  final String parentName;

  /// Shown to the child until the parent's phone has joined.
  final String inviteCode;
  final bool parentJoined;
}

/// Thrown when an invite code doesn't lead to a family.
class UnknownInviteCode implements Exception {
  const UnknownInviteCode();
}

/// Every call the app makes about families. The database functions
/// `create_family` and `join_family` own the rules; this only calls them.
abstract interface class FamilyRepository {
  /// Null until the person creates or joins a family.
  Future<Membership?> myMembership();

  Future<Membership> createFamily({required String parentName});

  /// Throws [UnknownInviteCode] when no family has [code].
  Future<Membership> joinFamily(String code);
}

class SupabaseFamilyRepository implements FamilyRepository {
  SupabaseFamilyRepository(this._db);

  final SupabaseClient _db;

  @override
  Future<Membership?> myMembership() async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return null;
    final row = await _db
        .from('members')
        .select('role, families(parent_name, invite_code, members(role))')
        .eq('user_id', userId)
        .maybeSingle();
    return row == null ? null : _membership(row);
  }

  @override
  Future<Membership> createFamily({required String parentName}) async {
    await _db.rpc('create_family', params: {'parent_name': parentName});
    return (await myMembership())!;
  }

  @override
  Future<Membership> joinFamily(String code) async {
    try {
      await _db.rpc('join_family', params: {'code': normalizeInviteCode(code)});
    } on PostgrestException catch (error) {
      // join_family raises "no_data_found" (P0002) for a code with no family.
      if (error.code == 'P0002') throw const UnknownInviteCode();
      rethrow;
    }
    return (await myMembership())!;
  }

  static Membership _membership(Map<String, dynamic> row) {
    final family = row['families'] as Map<String, dynamic>;
    final roles = (family['members'] as List).map((m) => m['role']);
    return Membership(
      role: FamilyRole.values.byName(row['role'] as String),
      parentName: family['parent_name'] as String,
      inviteCode: family['invite_code'] as String,
      parentJoined: roles.contains(FamilyRole.parent.name),
    );
  }
}

/// People read codes aloud and type them with spaces or dashes; the
/// database stores them bare and upper-case.
String normalizeInviteCode(String typed) =>
    typed.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
