import 'package:flutter_test/flutter_test.dart';
import 'package:morning_wave/screens/home_screen.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets('home screen greets and asks for notifications once', (
    tester,
  ) async {
    var permissionRequests = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          requestNotificationPermission: () async {
            permissionRequests++;
            return true;
          },
        ),
      ),
    );

    expect(find.text('Good morning'), findsOneWidget);
    expect(permissionRequests, 1);
  });
}
