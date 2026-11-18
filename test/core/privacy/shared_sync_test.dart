import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Shared JSON synchronization (root shared/ <-> functions/shared/)', () {
    const sharedFiles = [
      'error_reasons.json',
      'school_policy_defaults.json',
    ];

    for (final fileName in sharedFiles) {
      test('$fileName matches between shared/ and functions/shared/', () {
        final rootFile = File('shared/$fileName');
        final fnFile = File('functions/shared/$fileName');

        expect(
          rootFile.existsSync(),
          isTrue,
          reason: 'Root source-of-truth file shared/$fileName must exist',
        );
        expect(
          fnFile.existsSync(),
          isTrue,
          reason: 'Server copy functions/shared/$fileName missing. Run: cd functions && npm run sync-shared',
        );

        final rootJson = jsonDecode(rootFile.readAsStringSync());
        final fnJson = jsonDecode(fnFile.readAsStringSync());
        expect(
          fnJson,
          equals(rootJson),
          reason: 'functions/shared/$fileName drifted from shared/$fileName. Run: cd functions && npm run sync-shared',
        );
      });
    }

    test('test_fixtures/privacy_cases.json is valid and non-empty', () {
      final file = File('test_fixtures/privacy_cases.json');
      expect(file.existsSync(), isTrue);
      final parsed = jsonDecode(file.readAsStringSync()) as List<dynamic>;
      expect(parsed, isNotEmpty);
    });
  });
}
