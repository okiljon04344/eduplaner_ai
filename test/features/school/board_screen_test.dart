import 'package:edu_planner_ai/core/theme/app_colors.dart';
import 'package:edu_planner_ai/features/school/models/school.dart';
import 'package:edu_planner_ai/features/school/models/school_notice.dart';
import 'package:edu_planner_ai/features/school/school_providers.dart';
import 'package:edu_planner_ai/features/school/screens/board_screen.dart';
import 'package:edu_planner_ai/features/school/widgets/school_notices_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

class _Seen extends SeenNoticesNotifier {
  @override
  Set<String> build() => const {};
}

SchoolNotice _n(String id, {bool urgent = false, int day = 1, String subject = '', NoticeCategory c = NoticeCategory.contact}) =>
    SchoolNotice(id: id, grade: 1, course: '農業', title: id, urgent: urgent, subject: subject, category: c, createdAt: DateTime(2026, 11, day));

Widget _app(List<SchoolNotice> notices, {String? subject}) => ProviderScope(
      overrides: [
        myNoticesProvider.overrideWithValue(notices),
        seenNoticesProvider.overrideWith(_Seen.new),
        schoolChangesProvider.overrideWith((ref) => Stream.value(const <SchoolChange>[])),
        schoolInfoProvider.overrideWith((ref) => Stream.value(null)),
      ],
      child: MaterialApp(home: BoardScreen(subject: subject)),
    );

void main() {
  setUpAll(() => initializeDateFormatting('ja'));
  setUp(() => AppColors.applyBrightness(Brightness.dark));

  test('sortBoard pins urgent notices, then newest first', () {
    final sorted = sortBoard([_n('old', day: 1), _n('urgent', urgent: true, day: 2), _n('new', day: 5)]);
    expect(sorted.map((n) => n.id), ['urgent', 'new', 'old']);
  });

  test('notice parsing: category default, subject match, https-only link', () {
    final old = SchoolNotice.fromMap('a', {'grade': 1, 'title': 't'});
    expect(old.category, NoticeCategory.contact);
    expect(old.safeLink, isNull);
    final n = SchoolNotice.fromMap('b', {'grade': 1, 'title': 't', 'category': 'change', 'subject': ' 数学 ', 'link': 'https://drive.google.com/x'});
    expect(n.category, NoticeCategory.change);
    expect(n.hasSubject('数学'), isTrue);
    expect(n.hasSubject('英語'), isFalse);
    expect(n.safeLink?.host, 'drive.google.com');
    for (final bad in ['http://a.jp', 'javascript:alert(1)', 'https://']) {
      expect(SchoolNotice.fromMap('c', {'grade': 1, 'title': 't', 'link': bad}).safeLink, isNull, reason: bad);
    }
  });

  testWidgets('filters by the subject it was opened with, and by category', (tester) async {
    await tester.pumpWidget(_app([
      _n('math-change', subject: '数学', c: NoticeCategory.change),
      _n('math-contact', subject: '数学'),
      _n('english', subject: '英語'),
    ], subject: '数学'));
    await tester.pumpAndSettle();
    expect(find.byType(NoticeRow), findsNWidgets(2));
    expect(find.text('english'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, NoticeCategory.change.label));
    await tester.pumpAndSettle();
    expect(find.byType(NoticeRow), findsOneWidget);
    expect(find.text('math-change'), findsOneWidget);

    // Clearing the subject chip shows the whole class board for that category.
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(find.byType(NoticeRow), findsOneWidget);
  });

  testWidgets('shows an empty state when nothing matches', (tester) async {
    await tester.pumpWidget(_app(const []));
    await tester.pumpAndSettle();
    expect(find.byType(NoticeRow), findsNothing);
    expect(find.byType(ChoiceChip), findsNWidgets(4));
  });
}
