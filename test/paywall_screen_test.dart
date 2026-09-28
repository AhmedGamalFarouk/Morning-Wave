import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morning_wave/screens/paywall_screen.dart';
import 'package:morning_wave/services/subscription.dart';
import 'package:morning_wave/theme/app_theme.dart';

class _FakeSubscription implements SubscriptionService {
  _FakeSubscription({this.offer});

  final PlanOffer? offer;
  final entitled = ValueNotifier<bool>(false);
  var purchaseCalls = 0;
  var restoreCalls = 0;
  var throwOnPurchase = false;

  @override
  ValueListenable<bool> get isEntitled => entitled;

  @override
  Future<PlanOffer?> loadOffer() async => offer;

  @override
  Future<void> purchase() async {
    purchaseCalls++;
    if (throwOnPurchase) throw StateError('nope');
    entitled.value = true;
  }

  @override
  Future<void> restore() async => restoreCalls++;
}

Widget _app(SubscriptionService subscription, {String? parentName}) =>
    MaterialApp(
      theme: buildAppTheme(),
      home: PaywallScreen(subscription: subscription, parentName: parentName),
    );

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(find.text(label), 200);
  await tester.ensureVisible(find.text(label));
  await tester.pump();
  await tester.tap(find.text(label));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('shows the family plan and starts a purchase', (tester) async {
    final subscription = _FakeSubscription(
      offer: (priceString: r'$59.99', introPriceString: null),
    );
    await tester.pumpWidget(_app(subscription, parentName: 'Mom'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Keep the good mornings coming'), findsOneWidget);
    expect(find.textContaining('Mom never pays a thing'), findsOneWidget);

    await _tap(tester, 'Start the family plan');

    expect(subscription.purchaseCalls, 1);
    expect(find.text('You’re all set'), findsOneWidget);
    expect(find.text('Start the family plan'), findsNothing);
  });

  testWidgets('a failed purchase says so gently, without cold words', (
    tester,
  ) async {
    final subscription = _FakeSubscription()..throwOnPurchase = true;
    await tester.pumpWidget(_app(subscription));
    await tester.pump();
    await tester.pump();

    await _tap(tester, 'Start the family plan');

    expect(find.textContaining('another try'), findsOneWidget);
    expect(subscription.entitled.value, isFalse);
  });

  testWidgets('restoring a purchase calls through', (tester) async {
    final subscription = _FakeSubscription();
    await tester.pumpWidget(_app(subscription));
    await tester.pump();
    await tester.pump();

    await _tap(tester, 'Restore a purchase');

    expect(subscription.restoreCalls, 1);
  });

  test('the noop service reports not entitled and refuses to purchase', () {
    const service = NoopSubscriptionService();
    expect(service.isEntitled.value, isFalse);
    expect(() => service.purchase(), throwsStateError);
  });
}
