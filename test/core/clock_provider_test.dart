import 'package:edu_planner_ai/core/providers/clock_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('todayProvider emits today at local midnight immediately', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final today = await container.read(todayProvider.future);
    final now = DateTime.now();
    expect(today.isAfter(now), isFalse);
    expect(today.isAfter(DateTime(now.year, now.month, now.day - 1, 23, 59)),
        isTrue);
    expect([today.hour, today.minute, today.second], [0, 0, 0]);
  });

  test('minuteTickProvider emits the current time immediately', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final before = DateTime.now();
    final tick = await container.read(minuteTickProvider.future);
    expect(tick.isBefore(before), isFalse);
    expect(tick.difference(before).inSeconds, lessThan(5));
  });
}
