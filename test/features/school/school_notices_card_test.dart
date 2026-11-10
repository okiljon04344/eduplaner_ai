import 'package:edu_planner_ai/core/theme/app_colors.dart';
import 'package:edu_planner_ai/features/school/models/school_notice.dart';
import 'package:edu_planner_ai/features/school/school_providers.dart';
import 'package:edu_planner_ai/features/school/widgets/school_notices_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeSeenNoticesNotifier extends SeenNoticesNotifier {
  final Set<String> _initial;
  FakeSeenNoticesNotifier([this._initial = const {}]);

  @override
  Set<String> build() => _initial;

  @override
  Future<void> markSeen(String id) async {
    state = {...state, id};
  }
}

Widget _buildCardApp({
  required List<SchoolNotice> notices,
  Set<String> seenIds = const {},
}) =>
    ProviderScope(
      overrides: [
        myNoticesProvider.overrideWithValue(notices),
        seenNoticesProvider.overrideWith(() => FakeSeenNoticesNotifier(seenIds)),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: SchoolNoticesCard()),
        ),
      ),
    );

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ja');
  });

  setUp(() {
    AppColors.applyBrightness(Brightness.dark);
    SharedPreferences.setMockInitialValues({'seen_notice_ids': <String>[]});
  });

  testWidgets('SchoolNoticesCard renders nothing for an empty list', (tester) async {
    await tester.pumpWidget(_buildCardApp(notices: const []));
    await tester.pumpAndSettle();

    expect(find.byType(SchoolNoticesCard), findsOneWidget);
    expect(find.text('お知らせ'), findsNothing);
    expect(find.text('すべて見る'), findsNothing);
    expect(find.byType(UrgentBadge), findsNothing);
    expect(find.byType(NoticeRow), findsNothing);
    expect(find.byIcon(Icons.campaign_outlined), findsNothing);
  });

  testWidgets('shows title + 緊急 badge for urgent notices and no badge for normal notices', (tester) async {
    final notices = [
      SchoolNotice(
        id: 'n_urgent',
        grade: 1,
        course: '農業',
        title: '明日は台風のため自宅待機',
        body: '外出を控えてください。',
        urgent: true,
        authorName: '佐藤教頭',
        createdAt: DateTime(2026, 11, 10, 8, 30),
      ),
      SchoolNotice(
        id: 'n_normal',
        grade: 1,
        course: '農業',
        title: '持ち物連絡',
        body: '作業服を持参のこと。',
        urgent: false,
        authorName: '田中先生',
        createdAt: DateTime(2026, 11, 10, 9, 0),
      ),
    ];

    await tester.pumpWidget(_buildCardApp(notices: notices));
    await tester.pumpAndSettle();

    // Card header
    expect(find.text('お知らせ'), findsOneWidget);
    expect(find.byIcon(Icons.campaign_outlined), findsOneWidget);

    // Both notice titles are displayed
    expect(find.text('明日は台風のため自宅待機'), findsOneWidget);
    expect(find.text('持ち物連絡'), findsOneWidget);

    // Urgent badge appears only once (for the urgent notice)
    expect(find.byType(UrgentBadge), findsOneWidget);
    expect(find.text('緊急'), findsOneWidget);

    // Exactly 2 notice rows
    expect(find.byType(NoticeRow), findsNWidgets(2));

    // Under 3 notices -> see-all link must not be shown
    expect(find.text('すべて見る'), findsNothing);
  });

  testWidgets('shows the see-all link only when more than 3 notices', (tester) async {
    final threeNotices = [
      const SchoolNotice(id: 'n1', grade: 2, title: 'お知らせ1'),
      const SchoolNotice(id: 'n2', grade: 2, title: 'お知らせ2'),
      const SchoolNotice(id: 'n3', grade: 2, title: 'お知らせ3'),
    ];

    // Exactly 3 notices: no see-all link
    await tester.pumpWidget(_buildCardApp(notices: threeNotices));
    await tester.pumpAndSettle();

    expect(find.text('お知らせ'), findsOneWidget);
    expect(find.byType(NoticeRow), findsNWidgets(3));
    expect(find.text('すべて見る'), findsNothing);

    // 4 notices: see-all link appears and only the first 3 are in the main card
    final fourNotices = [
      ...threeNotices,
      const SchoolNotice(id: 'n4', grade: 2, title: 'お知らせ4'),
    ];

    await tester.pumpWidget(_buildCardApp(notices: fourNotices));
    await tester.pumpAndSettle();

    expect(find.text('すべて見る'), findsOneWidget);
    expect(find.text('お知らせ1'), findsOneWidget);
    expect(find.text('お知らせ2'), findsOneWidget);
    expect(find.text('お知らせ3'), findsOneWidget);
    expect(find.text('お知らせ4'), findsNothing);

    // Tapping see-all opens the bottom sheet with all 4 notices
    await tester.tap(find.text('すべて見る'));
    await tester.pumpAndSettle();

    expect(find.text('お知らせ4'), findsOneWidget);
    // The sheet contains all 4 notices
    expect(
      find.descendant(of: find.byType(BottomSheet), matching: find.byType(NoticeRow)),
      findsNWidgets(4),
    );
  });

  testWidgets('marks unread notices based on seenNoticesProvider', (tester) async {
    final notices = [
      const SchoolNotice(id: 'seen_1', grade: 1, title: '既読のお知らせ'),
      const SchoolNotice(id: 'unseen_1', grade: 1, title: '未読のお知らせ'),
    ];

    await tester.pumpWidget(_buildCardApp(notices: notices, seenIds: {'seen_1'}));
    await tester.pumpAndSettle();

    final seenRow = tester.widget<NoticeRow>(
      find.byWidgetPredicate((w) => w is NoticeRow && w.notice.id == 'seen_1'),
    );
    final unseenRow = tester.widget<NoticeRow>(
      find.byWidgetPredicate((w) => w is NoticeRow && w.notice.id == 'unseen_1'),
    );

    expect(seenRow.unread, isFalse);
    expect(unseenRow.unread, isTrue);
  });
}
