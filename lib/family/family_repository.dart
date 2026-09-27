import 'package:supabase_flutter/supabase_flutter.dart';

enum FamilyRole { parent, child }

/// The signed-in person's place in their family.
class Membership {
  const Membership({
    required this.familyId,
    required this.role,
    required this.parentName,
    required this.inviteCode,
    required this.parentJoined,
  });

  final String familyId;
  final FamilyRole role;

  /// What the family calls the parent ("Mom"): the family's name. The
  /// parent is greeted by it.
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
  /// Empty until the person creates or joins a family. A grown child can
  /// be in several: one per parent, when parents live apart.
  Future<List<Membership>> myFamilies();

  Future<void> createFamily({required String parentName});

  /// Throws [UnknownInviteCode] when no family has [code].
  Future<void> joinFamily(String code);

  /// A fresh code for the parent's reinstalled or new phone. Joining with
  /// it moves the parent's place in the family to that phone.
  Future<void> newParentCode(String familyId);
}

class SupabaseFamilyRepository implements FamilyRepository {
  SupabaseFamilyRepository(this._db, {this.childName});

  final SupabaseClient _db;

  /// How the child appears to the family, from their Google account.
  final String? Function()? childName;

  @override
  Future<List<Membership>> myFamilies() async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return const [];
    final rows = await _db
        .from('members')
        .select('role, families(id, name, invite_code, members(role))')
        .eq('user_id', userId)
        .order('created_at');
    return rows.map(_membership).toList();
  }

  /// The family is named for the parent ("Mom"), so the name the child
  /// picks is the one the parent is greeted by.
  @override
  Future<void> createFamily({required String parentName}) async {
    await _db.rpc(
      'create_family',
      params: {
        'family_name': parentName,
        'my_name': childName?.call() ?? 'Family',
      },
    );
  }

  @override
  Future<void> joinFamily(String code) async {
    try {
      final family = await _db.rpc(
        'join_family',
        params: {
          'code': normalizeInviteCode(code),
          'my_role': FamilyRole.parent.name,
          // The parent never types a name; they take the family's below.
          'my_name': 'Parent',
        },
      );
      await _db
          .from('members')
          .update({'display_name': family['name']})
          .eq('user_id', _db.auth.currentUser!.id);
    } on PostgrestException catch (error) {
      switch (error.code) {
        // No family has this code.
        case 'P0002':
          throw const UnknownInviteCode();
        // Already in this family, for example after a lost connection.
        case '23505':
          break;
        default:
          rethrow;
      }
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
      parentName: family['name'] as String,
      inviteCode: family['invite_code'] as String,
      parentJoined: roles.contains(FamilyRole.parent.name),
    );
  }
}

/// Codes are 8 hex characters. People read them aloud and type them with
/// spaces or dashes, and an O where the code has a zero.
String normalizeInviteCode(String typed) =>
    typed.replaceAll(RegExp(r'[\s-]'), '').toUpperCase().replaceAll('O', '0');

/// "3F2A91BC" shown as "3F2A 91BC", easier to read out over the phone.
String displayInviteCode(String code) =>
    code.length == 8 ? '${code.substring(0, 4)} ${code.substring(4)}' : code;
