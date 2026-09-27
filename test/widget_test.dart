import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morning_wave/placeholder/family.dart';
import 'package:morning_wave/screens/child_home_screen.dart';
import 'package:morning_wave/screens/home_screen.dart';
import 'package:morning_wave/screens/parent_home_screen.dart';
import 'package:morning_wave/theme/app_theme.dart';

Widget _app(Widget home) => MaterialApp(theme: buildAppTheme(), home: home);

/// The sun breathes forever, so settle with a fixed pump instead of
/// pumpAndSettle.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Words the design language never lets the parent see.
final _coldWords = RegExp(
  r'miss|monitor|status|alert|fail|inactive|compliance|track',
  caseSensitive: false,
);

void _expectWarmCopy(WidgetTester tester) {
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    expect(text.data ?? '', isNot(matches(_coldWords)));
  }
}

void main() {
  // A typical Android phone: 411 x 891 dp.
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

  testWidgets('home greets the parent and asks for notifications once', (
    tester,
  ) async {
    var permissionRequests = 0;
    await tester.pumpWidget(
      _app(
        HomeScreen(
          requestNotificationPermission: () async {
            permissionRequests++;
            return true;
          },
        ),
      ),
    );

    expect(find.text('Good morning, Mom'), findsOneWidget);
    expect(find.text('Ready to say hello?'), findsOneWidget);
    expect(permissionRequests, 1);
  });

  testWidgets('tapping the sun says good morning and shows the family note', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const ParentHomeScreen()));

    await tester.tap(find.bySemanticsLabel('Say good morning to your family'));
    await _settle(tester);

    expect(find.text('Your family knows you’re okay.'), findsOneWidget);
    expect(find.text('“${PlaceholderFamily.note}”'), findsOneWidget);
    expect(find.bySemanticsLabel('Your good morning was sent'), findsOneWidget);
    _expectWarmCopy(tester);
  });

  testWidgets('going away and coming back', (tester) async {
    await tester.pumpWidget(_app(const ParentHomeScreen()));

    await tester.scrollUntilVisible(find.text('Going somewhere?'), 200);
    await tester.ensureVisible(find.text('Going somewhere?'));
    await tester.pump();
    await tester.tap(find.text('Going somewhere?'));
    await _settle(tester);
    await tester.tap(find.text('Let my family know'));
    await _settle(tester);

    expect(find.text('You’re away'), findsOneWidget);
    expect(find.text('Your family knows.'), findsOneWidget);
    _expectWarmCopy(tester);

    await tester.tap(find.bySemanticsLabel('Tell your family you’re back'));
    await _settle(tester);
    expect(find.text('Ready to say hello?'), findsOneWidget);
  });

  testWidgets('child hero answers "How is Mom?" first', (tester) async {
    await tester.pumpWidget(_app(const ChildHomeScreen()));

    expect(find.text('Mom said good morning'), findsOneWidget);
    expect(find.text('Today · 8:14 AM'), findsOneWidget);

    await tester.tap(find.text('Send love'));
    await _settle(tester);
    expect(find.text('Love sent'), findsOneWidget);
  });

  testWidgets('child hero states use human language', (tester) async {
    await tester.pumpWidget(
      _app(const ChildHomeScreen(view: ChildView.waiting)),
    );
    expect(find.text('Haven’t heard from Mom yet'), findsOneWidget);
    _expectWarmCopy(tester);

    await tester.pumpWidget(_app(const ChildHomeScreen(view: ChildView.away)));
    expect(find.text('Mom is away'), findsOneWidget);
    _expectWarmCopy(tester);
  });

  test('preview define picks the home', () {
    expect(parseHomePreview(''), HomePreview.parent);
    expect(parseHomePreview('child-away'), HomePreview.childAway);
  });
}
