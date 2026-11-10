import 'package:edu_planner_ai/features/school/school_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('read targets match readTarget/noticeReadTarget in functions/school/overrides.js', () {
    // Same expectations as functions/test/sync.test.js and notices.test.js.
    expect(SchoolRepository.readTarget(1, '農業', '2026-10-29', '3-4'), 'o_1_農業_2026-10-29_3-4');
    expect(SchoolRepository.readTarget(1, 'a/b', '2026-10-29', '3-4'), 'o_1_a,b_2026-10-29_3-4');
    expect(SchoolRepository.noticeReadTarget('notice123'), 'n_notice123');
  });
}
