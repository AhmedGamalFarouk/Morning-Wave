import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morning_wave/family/checkin_repository.dart';
import 'package:morning_wave/placeholder/family.dart';
import 'package:morning_wave/screens/child_home_screen.dart';
import 'package:morning_wave/screens/parent_home_screen.dart';
import 'package:morning_wave/theme/app_theme.dart';

FamilyStatus _status({
  bool checkedIn = false,
  bool away = false,
  DateTime? awayUntil,
}) => FamilyStatus(
  checkedInToday: checkedIn,
  away: away,
  awayUntil: awayUntil,
  usualByHour: 10,
  usualByMinute: 0,
);

ChildParent _mom(Future<void> Function() onSendLove) => (
  name: 'Mom',
  joined: true,
  parentCode: null,
  childCode: null,
  onNewPhone: null,
  onSendLove: onSendLove,
  onSendPhoto: null,
  onSendVoiceNote: null,
  loadStatus: null,
);

void main() {
  group('the morning reminder', () {
    final early = DateTime(2026, 10, 8, 7);

    test('rings half an hour before the window ends', () {
      expect(
        nextMorningReminder(_status(), early),
        DateTime(2026, 10, 8, 9, 30),
      );
    });

    test('skips today once the parent said good morning', () {
      expect(
        nextMorningReminder(_status(checkedIn: true), early),
        DateTime(2026, 10, 9, 9, 30),
      );
    });

    test('starts tomorrow when today’s time has passed', () {
      expect(
        nextMorningReminder(_status(), DateTime(2026, 10, 8, 9, 45)),
        DateTime(2026, 10, 9, 9, 30),
      );
    });

    test('waits for the morning after the parent is back', () {
      expect(
        nextMorningReminder(
          _status(away: true, awayUntil: DateTime(2026, 10, 12)),
          early,
        ),
        DateTime(2026, 10, 13, 9, 30),
      );
    });

    test('stays quiet without a schedule', () {
      const none = FamilyStatus(checkedInToday: false, away: false);
      expect(nextMorningReminder(none, early), isNull);
    });
  });

  test('names read the way people say them', () {
    expect(namesTogether(['Sara']), 'Sara');
    expect(namesTogether(['Sara', 'Ali']), 'Sara and Ali');
    expect(namesTogether(['Sara', 'Ali', 'Omar']), 'Sara, Ali and Omar');
  });

  testWidgets('love that didn’t go through can be sent again', (tester) async {
    var tries = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ChildHomeScreen(
          view: ChildView.heard,
          parents: [
            _mom(() async {
              if (++tries == 1) throw Exception('offline');
            }),
          ],
        ),
      ),
    );

    await tester.tap(find.text('Send love'));
    await tester.pump();
    expect(find.text('That didn’t go through. Try again?'), findsOneWidget);
    expect(find.text('Send love'), findsOneWidget);

    await tester.tap(find.text('Send love'));
    await tester.pump();
    expect(tries, 2);
    expect(find.text('Love sent'), findsOneWidget);
  });
}
