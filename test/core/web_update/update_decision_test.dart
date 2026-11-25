import 'package:edu_planner_ai/core/services/web_update/update_decision.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UpdateDecision.hasNewBuild', () {
    test('false for dev builds without a build id', () {
      expect(UpdateDecision.hasNewBuild(currentBuildId: '', remoteBuildId: 'b2'), isFalse);
    });

    test('false when remote is missing or blank', () {
      expect(UpdateDecision.hasNewBuild(currentBuildId: 'b1', remoteBuildId: null), isFalse);
      expect(UpdateDecision.hasNewBuild(currentBuildId: 'b1', remoteBuildId: '  '), isFalse);
    });

    test('false when ids match, true when they differ', () {
      expect(UpdateDecision.hasNewBuild(currentBuildId: 'b1', remoteBuildId: 'b1'), isFalse);
      expect(UpdateDecision.hasNewBuild(currentBuildId: 'b1', remoteBuildId: 'b2'), isTrue);
    });
  });

  group('UpdateDecision.shouldReload', () {
    test('reloads once for a new build', () {
      expect(
        UpdateDecision.shouldReload(currentBuildId: 'b1', remoteBuildId: 'b2', lastAttemptedBuildId: null),
        isTrue,
      );
    });

    test('does not loop when the reload already happened for that build', () {
      expect(
        UpdateDecision.shouldReload(currentBuildId: 'b1', remoteBuildId: 'b2', lastAttemptedBuildId: 'b2'),
        isFalse,
      );
    });

    test('reloads again for an even newer build', () {
      expect(
        UpdateDecision.shouldReload(currentBuildId: 'b1', remoteBuildId: 'b3', lastAttemptedBuildId: 'b2'),
        isTrue,
      );
    });
  });

  group('UpdateDecision.parseBuildId', () {
    test('reads buildId and rejects malformed bodies', () {
      expect(UpdateDecision.parseBuildId({'buildId': ' abc '}), 'abc');
      expect(UpdateDecision.parseBuildId({'buildId': ''}), isNull);
      expect(UpdateDecision.parseBuildId({'buildId': 3}), isNull);
      expect(UpdateDecision.parseBuildId(['x']), isNull);
      expect(UpdateDecision.parseBuildId(null), isNull);
    });
  });
}
