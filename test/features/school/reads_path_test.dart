import 'package:edu_planner_ai/features/school/school_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('readsPath matches readsPath in functions/school/overrides.js', () {
    // Same expectation as functions/test/sync.test.js: dots become commas.
    expect(SchoolRepository.readsPath('school.example.jp', 1, '農業', '2026-10-29', '3-4'),
        'reads/school,example,jp/1_農業/2026-10-29_3-4');
    expect(SchoolRepository.rtdbKey(r'a.b$c#d[e]f/g'), 'a,b,c,d,e,f,g');
  });
}
