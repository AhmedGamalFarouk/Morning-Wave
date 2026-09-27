import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morning_wave/family/auth.dart';
import 'package:morning_wave/family/family_repository.dart';
import 'package:morning_wave/screens/app_gate.dart';
import 'package:morning_wave/theme/app_theme.dart';

class _FakeAuth implements Auth {
  _FakeAuth({this.googleName});

  /// Set when Google sign-in should succeed.
  final String? googleName;

  @override
  var isSignedIn = false;
  @override
  var isParentAccount = false;
  var anonymousSignIns = 0;

  @override
  String? get childFirstName => isParentAccount ? null : googleName;

  @override
  Future<bool> signInWithGoogle() async {
    if (googleName == null) return false;
    isSignedIn = true;
    return true;
  }

  @override
  Future<void> signInAsParent() async {
    if (isSignedIn) return;
    anonymousSignIns++;
    isSignedIn = isParentAccount = true;
  }

  @override
  Future<void> signOut() async => isSignedIn = isParentAccount = false;
}

const _parentCode = 'KX7PQ2MA';
const _childCode = 'HN4RT8WE';

Membership _family(
  String parentName, {
  FamilyRole role = FamilyRole.child,
  bool parentJoined = true,
  String? newPhoneCode,
}) => Membership(
  familyId: parentName,
  role: role,
  parentName: parentName,
  parentCode: parentJoined ? newPhoneCode : _parentCode,
  childCode: _childCode,
  parentJoined: parentJoined,
);

class _FakeFamilies implements FamilyRepository {
  var mine = <Membership>[];
  var reachable = true;
  var wrongCodes = 0;

  /// The next request goes through but its answer is lost.
  var loseNextAnswer = false;

  void _maybeLoseAnswer() {
    if (!loseNextAnswer) return;
    loseNextAnswer = false;
    throw Exception('connection lost');
  }

  @override
  Future<List<Membership>> myFamilies() async {
    if (!reachable) throw Exception('offline');
    return mine;
  }

  @override
  Future<void> createFamily({
    required String parentName,
    required String myName,
  }) async {
    mine = [...mine, _family(parentName, parentJoined: false)];
    _maybeLoseAnswer();
  }

  /// Like the server: spaces, dashes and case don't matter, a wrong code
  /// returns nothing, and a used parent code is gone.
  @override
  Future<void> joinFamily(String code, {required String myName}) async {
    if (wrongCodes >= 10) throw const TooManyCodes();
    final typed = code.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    if (typed == _parentCode && mine.isEmpty) {
      mine = [_family('Mom', role: FamilyRole.parent)];
      return;
    }
    if (typed == _childCode && mine.isNotEmpty) throw const AlreadyInFamily();
    wrongCodes++;
    throw const UnknownInviteCode();
  }

  @override
  Future<void> newParentCode(String familyId) async {
    mine = [
      for (final f in mine)
        f.familyId == familyId
            ? _family(f.parentName, newPhoneCode: 'ZP3QW9CD')
            : f,
    ];
  }
}

class _FakeCache implements FamilyCache {
  List<Membership>? saved;

  @override
  Future<List<Membership>?> read() async => saved;

  @override
  Future<void> write(List<Membership>? families) async => saved = families;
}

Widget _app(Auth auth, FamilyRepository families, [FamilyCache? cache]) =>
    MaterialApp(
      theme: buildAppTheme(),
      home: AppGate(
        auth: auth,
        families: families,
        cache: cache ?? _FakeCache(),
      ),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pump();
  await tester.tap(find.text(label));
  await _settle(tester);
}

Future<void> _typeCode(WidgetTester tester, String code) async {
  await tester.enterText(find.byType(TextField), code);
  await _tap(tester, 'Join my family');
}

void main() {
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1080, 2340);
    view.devicePixelRatio = 2.625;
  });
  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });

  testWidgets('the child signs in, names Mom and sees her code', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(_FakeAuth(googleName: 'Sara'), _FakeFamilies()),
    );

    await _tap(tester, 'Continue with Google');
    expect(find.text('Hi Sara! Who are the good mornings from?'), findsOne);

    await tester.tap(find.text('Mom'));
    await tester.pump();
    await _tap(tester, 'Start our mornings');

    expect(find.text('Now, Mom’s phone'), findsOneWidget);
    expect(find.text('KX7P Q2MA'), findsOneWidget);
    expect(find.text('Mom said good morning'), findsNothing);
  });

  testWidgets('a family made while the answer was lost isn’t made twice', (
    tester,
  ) async {
    final families = _FakeFamilies()..loseNextAnswer = true;
    final auth = _FakeAuth(googleName: 'Sara')..isSignedIn = true;
    await tester.pumpWidget(_app(auth, families));
    await _settle(tester);

    await tester.tap(find.text('Mom'));
    await tester.pump();
    await _tap(tester, 'Start our mornings');

    expect(find.text('Now, Mom’s phone'), findsOneWidget);
    expect(families.mine, hasLength(1));
  });

  testWidgets('closing Google’s sheet stays on welcome', (tester) async {
    await tester.pumpWidget(_app(_FakeAuth(), _FakeFamilies()));
    await _tap(tester, 'Continue with Google');
    expect(find.text('Morning Wave'), findsOneWidget);
  });

  testWidgets('the parent types the code and lands on the morning sun', (
    tester,
  ) async {
    final auth = _FakeAuth();
    await tester.pumpWidget(_app(auth, _FakeFamilies()));

    await _tap(tester, 'I have a code');
    await _typeCode(tester, 'kx7p q2ma');

    expect(find.text('Good morning, Mom'), findsOneWidget);
    expect(auth.anonymousSignIns, 1);
  });

  testWidgets('a code no family has gets a gentle second try', (tester) async {
    final auth = _FakeAuth();
    await tester.pumpWidget(_app(auth, _FakeFamilies()));

    await _tap(tester, 'I have a code');
    await _typeCode(tester, 'AAAA AAAA');
    expect(find.textContaining('Check it with your family'), findsOneWidget);
    expect(
      find.textContaining(RegExp('wrong|invalid|error|fail')),
      findsNothing,
    );

    await _typeCode(tester, _parentCode);
    expect(find.text('Good morning, Mom'), findsOneWidget);
    // The same parent account is reused for the second try.
    expect(auth.anonymousSignIns, 1);
  });

  testWidgets('a retry after a lost answer finds the parent already in', (
    tester,
  ) async {
    final auth = _FakeAuth()
      ..isSignedIn = true
      ..isParentAccount = true;
    // The first try joined; its answer never arrived, so the code is used.
    final families = _FakeFamilies()
      ..mine = [_family('Mom', role: FamilyRole.parent)]
      ..reachable = false;
    await tester.pumpWidget(_app(auth, families, _FakeCache()..saved = []));
    await _settle(tester);

    families.reachable = true;
    await _typeCode(tester, _parentCode);
    expect(find.text('Good morning, Mom'), findsOneWidget);
  });

  testWidgets('many wrong codes ask for a break, kindly', (tester) async {
    final families = _FakeFamilies()..wrongCodes = 10;
    await tester.pumpWidget(_app(_FakeAuth(), families));

    await _tap(tester, 'I have a code');
    await _typeCode(tester, _parentCode);
    expect(find.textContaining('take a little break'), findsOneWidget);
  });

  testWidgets('a returning parent goes straight home, even offline', (
    tester,
  ) async {
    final auth = _FakeAuth()
      ..isSignedIn = true
      ..isParentAccount = true;
    final families = _FakeFamilies()..reachable = false;
    final cache = _FakeCache()
      ..saved = [_family('Papa', role: FamilyRole.parent)];
    await tester.pumpWidget(_app(auth, families, cache));
    await _settle(tester);

    expect(find.text('Good morning, Papa'), findsOneWidget);
    expect(find.textContaining('can’t reach'), findsNothing);
  });

  testWidgets('once Mom has joined, the child sees she’s set, not a morning', (
    tester,
  ) async {
    final auth = _FakeAuth(googleName: 'Sara')..isSignedIn = true;
    final families = _FakeFamilies()..mine = [_family('Mom')];
    await tester.pumpWidget(_app(auth, families));
    await _settle(tester);

    expect(find.text('Mom is all set'), findsOneWidget);
    expect(find.text('Mom said good morning'), findsNothing);
    expect(find.textContaining('HN4R T8WE'), findsNothing);

    await _tap(tester, 'Invite a brother or sister');
    expect(find.text('HN4R T8WE'), findsOneWidget);
  });

  testWidgets('out of reach never leads a child to a second family', (
    tester,
  ) async {
    final auth = _FakeAuth(googleName: 'Sara')..isSignedIn = true;
    final families = _FakeFamilies()..reachable = false;
    await tester.pumpWidget(_app(auth, families));
    await _settle(tester);

    expect(find.textContaining('can’t reach Morning Wave'), findsOneWidget);
    expect(find.text('Start our mornings'), findsNothing);

    families.reachable = true;
    await _tap(tester, 'Try again');
    expect(find.text('Start our mornings'), findsOneWidget);
  });

  testWidgets('a wrong code from a child with a family says so', (
    tester,
  ) async {
    final auth = _FakeAuth(googleName: 'Sara')..isSignedIn = true;
    final families = _FakeFamilies()..mine = [_family('Mom')];
    await tester.pumpWidget(_app(auth, families));
    await _settle(tester);

    await _tap(tester, 'Add a parent who lives apart');
    await _tap(tester, 'I have a code from my family');
    await _typeCode(tester, 'AAAA AAAA');
    expect(find.textContaining('Check it with your family'), findsOneWidget);
  });

  testWidgets('a family without a parent or a code asks for a new one', (
    tester,
  ) async {
    final auth = _FakeAuth(googleName: 'Sara')..isSignedIn = true;
    final families = _FakeFamilies()
      ..mine = [
        const Membership(
          familyId: 'Mom',
          role: FamilyRole.child,
          parentName: 'Mom',
          childCode: _childCode,
          parentJoined: false,
        ),
      ];
    await tester.pumpWidget(_app(auth, families));
    await _settle(tester);

    expect(find.text('Mom’s phone needs a new code'), findsOneWidget);
    expect(find.text('New phone for Mom?'), findsOneWidget);
  });

  testWidgets('a sibling code for your own family says you’re in', (
    tester,
  ) async {
    final auth = _FakeAuth(googleName: 'Sara')..isSignedIn = true;
    final families = _FakeFamilies()..mine = [_family('Mom')];
    await tester.pumpWidget(_app(auth, families));
    await _settle(tester);

    await _tap(tester, 'Add a parent who lives apart');
    await _tap(tester, 'I have a code from my family');
    await _typeCode(tester, _childCode);
    expect(
      find.text('You’re already in this family. Go back to see them.'),
      findsOneWidget,
    );
  });

  testWidgets('a child can look after two parents who live apart', (
    tester,
  ) async {
    final auth = _FakeAuth(googleName: 'Sara')..isSignedIn = true;
    final families = _FakeFamilies()..mine = [_family('Mom')];
    await tester.pumpWidget(_app(auth, families));
    await _settle(tester);

    await _tap(tester, 'Add a parent who lives apart');
    await tester.tap(find.text('Dad'));
    await tester.pump();
    await _tap(tester, 'Start our mornings');

    expect(find.text('Mom is all set'), findsOneWidget);
    expect(find.text('Now, Dad’s phone'), findsOneWidget);
  });

  testWidgets('a new phone for Mom asks first, then shows a fresh code', (
    tester,
  ) async {
    final auth = _FakeAuth(googleName: 'Sara')..isSignedIn = true;
    final families = _FakeFamilies()..mine = [_family('Mom')];
    await tester.pumpWidget(_app(auth, families));
    await _settle(tester);

    await _tap(tester, 'New phone for Mom?');
    await _tap(tester, 'Not now');
    expect(find.text('ZP3Q W9CD'), findsNothing);

    await _tap(tester, 'New phone for Mom?');
    await _tap(tester, 'Get a code');
    // Mom stays in the family until the new phone joins.
    expect(find.text('Mom is all set'), findsOneWidget);
    expect(find.text('ZP3Q W9CD'), findsOneWidget);
  });

  testWidgets('back from a wrong code reaches Google sign-in again', (
    tester,
  ) async {
    final auth = _FakeAuth(googleName: 'Sara');
    await tester.pumpWidget(_app(auth, _FakeFamilies()));

    await _tap(tester, 'I have a code');
    await _typeCode(tester, 'AAAA AAAA');
    await _tap(tester, 'Back');

    expect(auth.isSignedIn, isFalse);
    await _tap(tester, 'Continue with Google');
    expect(find.text('Hi Sara! Who are the good mornings from?'), findsOne);
  });

  testWidgets('Android’s back key leaves the code screen, not the app', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_FakeAuth(), _FakeFamilies()));

    await _tap(tester, 'I have a code');
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  test('a wrong code is nothing, however PostgREST shapes it', () {
    expect(joinedAFamily(null), isFalse);
    expect(joinedAFamily(<Object>[]), isFalse);
    expect(joinedAFamily({'id': null, 'parent_name': null}), isFalse);
    expect(
      joinedAFamily([
        {'id': 'f1'},
      ]),
      isTrue,
    );
    expect(joinedAFamily({'id': 'f1'}), isTrue);
  });

  test('codes show in two groups of four', () {
    expect(displayInviteCode('KX7PQ2MA'), 'KX7P Q2MA');
  });
}
