import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

/// Checks what is on screen and what TalkBack reads aloud.
void _expectWarmCopy(WidgetTester tester) {
  final handle = tester.ensureSemantics();
  for (final text in tester.widgetList<RichText>(find.byType(RichText))) {
    expect(text.text.toPlainText(), isNot(matches(_coldWords)));
  }
  expect(find.bySemanticsLabel(_coldWords), findsNothing);
  handle.dispose();
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

  testWidgets('home greets the parent without a system prompt', (tester) async {
    var permissionRequests = 0;
    await tester.pumpWidget(
      _app(
        HomeScreen(
          requestNotificationPermission: () async {
            permissionRequests++;
            return true;
          },
          notificationsEnabled: () async => false,
        ),
      ),
    );

    expect(find.text('Good morning, Mom'), findsOneWidget);
    expect(find.text('Ready to say hello?'), findsOneWidget);
    expect(permissionRequests, 0);

    // The invitation comes after the first good morning.
    await tester.tap(find.bySemanticsLabel('Say good morning to your family'));
    await _settle(tester);
    await tester.scrollUntilVisible(find.text('Yes, bring me notes'), 200);
    await tester.ensureVisible(find.text('Yes, bring me notes'));
    await tester.pump();
    await tester.tap(find.text('Yes, bring me notes'));
    await _settle(tester);

    expect(permissionRequests, 1);
    expect(find.text('Yes, bring me notes'), findsNothing);
  });

  testWidgets('no invitation when notifications are already allowed', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        ParentHomeScreen(
          requestNotificationPermission: () async => true,
          notificationsEnabled: () async => true,
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('Say good morning to your family'));
    await _settle(tester);

    expect(find.text('Yes, bring me notes'), findsNothing);
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

  testWidgets('going away until a chosen day, and coming back early', (
    tester,
  ) async {
    // A Monday.
    await tester.pumpWidget(
      _app(ParentHomeScreen(today: DateTime(2026, 9, 28))),
    );

    await tester.scrollUntilVisible(find.text('Going somewhere?'), 200);
    await tester.ensureVisible(find.text('Going somewhere?'));
    await tester.pump();
    await tester.tap(find.text('Going somewhere?'));
    await _settle(tester);

    expect(find.text('Tomorrow'), findsOneWidget);
    expect(find.text('Next Monday'), findsOneWidget);
    expect(find.text('Later…'), findsOneWidget);
    await tester.ensureVisible(find.text('Friday'));
    await tester.pump();
    await tester.tap(find.text('Friday'));
    await tester.pump();
    await tester.ensureVisible(find.text('Let my family know'));
    await tester.pump();
    await tester.tap(find.text('Let my family know'));
    await _settle(tester);

    expect(find.text('You’re away'), findsOneWidget);
    expect(find.text('Back on Friday. Your family knows.'), findsOneWidget);
    _expectWarmCopy(tester);

    await tester.tap(find.bySemanticsLabel('Tell your family you’re back'));
    await _settle(tester);
    expect(find.text('Ready to say hello?'), findsOneWidget);
  });

  testWidgets('away for longer than a week uses a calendar', (tester) async {
    await tester.pumpWidget(
      _app(ParentHomeScreen(today: DateTime(2026, 9, 28))),
    );
    await tester.scrollUntilVisible(find.text('Going somewhere?'), 200);
    await tester.ensureVisible(find.text('Going somewhere?'));
    await tester.pump();
    await tester.tap(find.text('Going somewhere?'));
    await _settle(tester);

    // Tomorrow is preselected, so the main button already works.
    await tester.ensureVisible(find.text('Later…'));
    await tester.pump();
    await tester.tap(find.text('Later…'));
    await _settle(tester);
    await tester.tap(find.text('20'));
    await tester.tap(find.text('That’s the day'));
    await _settle(tester);
    await tester.ensureVisible(find.text('Let my family know'));
    await tester.pump();
    await tester.tap(find.text('Let my family know'));
    await _settle(tester);

    expect(find.textContaining('Back on Tue, Oct 20.'), findsOneWidget);
  });

  testWidgets('an accidental good morning can be undone for a short while', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const ParentHomeScreen()));

    await tester.tap(find.bySemanticsLabel('Say good morning to your family'));
    await _settle(tester);
    await tester.tap(find.text('Oops, not yet'));
    await _settle(tester);
    expect(find.text('Ready to say hello?'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Say good morning to your family'));
    await tester.pump(ParentHomeScreen.undoWindow);
    await _settle(tester);
    expect(find.text('Oops, not yet'), findsNothing);
    expect(find.text('Your family knows you’re okay.'), findsOneWidget);
  });

  for (final scale in [1.5, 2.0]) {
    testWidgets('sun words stay whole at ${scale}x text size', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: _app(const ParentHomeScreen()),
        ),
      );
      await tester.pump();

      final error = tester.takeException();
      expect(error, isNull, reason: "$error");
      final label = tester.renderObject<RenderParagraph>(
        find.text('Say good\nmorning'),
      );
      // Two lines, broken only where the label says (28sp, 1.08 leading).
      final line = 28 * 1.08 * scale;
      expect(label.size.height, lessThan(line * 2.5));
    });
  }

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
