import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morning_wave/screens/child_home_screen.dart';
import 'package:morning_wave/services/subscription.dart';
import 'package:morning_wave/theme/app_theme.dart';

class _FakeSubscription implements SubscriptionService {
  final entitled = ValueNotifier<bool>(false);

  @override
  ValueListenable<bool> get isEntitled => entitled;

  @override
  Future<PlanOffer?> loadOffer() async => null;

  @override
  Future<void> purchase() async {}

  @override
  Future<void> restore() async {}
}

void main() {
  testWidgets('no plan link without a subscription service', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const ChildHomeScreen()),
    );
    expect(find.text('Get the family plan'), findsNothing);
  });

  testWidgets('the plan link opens the paywall and reflects entitlement', (
    tester,
  ) async {
    final subscription = _FakeSubscription();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ChildHomeScreen(subscription: subscription),
      ),
    );

    expect(find.text('Get the family plan'), findsOneWidget);
    await tester.tap(find.text('Get the family plan'));
    await tester.pumpAndSettle();

    expect(find.text('Keep the good mornings coming'), findsOneWidget);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    subscription.entitled.value = true;
    await tester.pump();

    expect(find.text('Family plan'), findsOneWidget);
    expect(find.text('Get the family plan'), findsNothing);
  });
}
