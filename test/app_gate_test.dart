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
}

class _FakeFamilies implements FamilyRepository {
  static const code = 'SUN42A';

  Membership? mine;
  var reachable = true;

  @override
  Future<Membership?> myMembership() async {
    if (!reachable) throw Exception('offline');
    return mine;
  }

  @override
  Future<Membership> createFamily({required String parentName}) async {
    return mine = Membership(
      role: FamilyRole.child,
      parentName: parentName,
      inviteCode: code,
      parentJoined: false,
    );
  }

  @override
  Future<Membership> joinFamily(String typed) async {
    if (normalizeInviteCode(typed) != code) throw const UnknownInviteCode();
    return mine = Membership(
      role: FamilyRole.parent,
      parentName: 'Mom',
      inviteCode: code,
      parentJoined: true,
    );
  }
}

Widget _app(Auth auth, FamilyRepository families) => MaterialApp(
  theme: buildAppTheme(),
  home: AppGate(auth: auth, families: families),
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

  testWidgets('the child signs in, names Mom and sees the invite code', (
    tester,
  ) async {
    final families = _FakeFamilies();
    await tester.pumpWidget(_app(_FakeAuth(googleName: 'Sara'), families));

    await _tap(tester, 'Continue with Google');
    expect(find.text('Hi Sara! Who are the good mornings from?'), findsOne);

    await tester.tap(find.text('Mom'));
    await tester.pump();
    await _tap(tester, 'Start our mornings');

    expect(find.text('Now, Mom’s phone'), findsOneWidget);
    expect(find.text('SUN42A'), findsOneWidget);
    expect(find.text('Mom said good morning'), findsNothing);
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
    await tester.enterText(find.byType(TextField), 'sun 42a');
    await _tap(tester, 'Join my family');

    expect(find.text('Good morning, Mom'), findsOneWidget);
    expect(auth.anonymousSignIns, 1);
  });

  testWidgets('a code no family has gets a gentle second try', (tester) async {
    final auth = _FakeAuth();
    await tester.pumpWidget(_app(auth, _FakeFamilies()));

    await _tap(tester, 'I have a code');
    await tester.enterText(find.byType(TextField), 'NOPE12');
    await _tap(tester, 'Join my family');
    expect(find.textContaining('Check it with your family'), findsOneWidget);
    expect(
      find.textContaining(RegExp('wrong|invalid|error|fail')),
      findsNothing,
    );

    await tester.enterText(find.byType(TextField), 'SUN42A');
    await _tap(tester, 'Join my family');
    expect(find.text('Good morning, Mom'), findsOneWidget);
    // The same parent account is reused for the second try.
    expect(auth.anonymousSignIns, 1);
  });

  testWidgets('a returning parent goes straight home', (tester) async {
    final auth = _FakeAuth()
      ..isSignedIn = true
      ..isParentAccount = true;
    final families = _FakeFamilies()
      ..mine = const Membership(
        role: FamilyRole.parent,
        parentName: 'Papa',
        inviteCode: 'SUN42A',
        parentJoined: true,
      );
    await tester.pumpWidget(_app(auth, families));
    await _settle(tester);

    expect(find.text('Good morning, Papa'), findsOneWidget);
  });

  testWidgets('once Mom has joined, the child sees her morning', (
    tester,
  ) async {
    final auth = _FakeAuth(googleName: 'Sara')..isSignedIn = true;
    final families = _FakeFamilies()
      ..mine = const Membership(
        role: FamilyRole.child,
        parentName: 'Mom',
        inviteCode: 'SUN42A',
        parentJoined: true,
      );
    await tester.pumpWidget(_app(auth, families));
    await _settle(tester);

    expect(find.text('Mom said good morning'), findsOneWidget);
    expect(find.text('SUN42A'), findsNothing);
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

  test('codes are read without spaces, dashes or lower case', () {
    expect(normalizeInviteCode(' sun-42 a '), 'SUN42A');
  });
}
