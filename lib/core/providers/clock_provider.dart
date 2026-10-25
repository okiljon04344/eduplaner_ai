import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Emits [initial] now and again at each instant returned by [nextBoundary];
/// the timer and stream are cleaned up when the provider is disposed.
Stream<DateTime> _boundaryStream(
  Ref ref, {
  required DateTime Function(DateTime now) initial,
  required DateTime Function(DateTime now) nextBoundary,
}) {
  final controller = StreamController<DateTime>();
  Timer? timer;
  void emit() {
    final now = DateTime.now();
    controller.add(initial(now));
    timer = Timer(nextBoundary(now).difference(now), emit);
  }

  ref.onDispose(() {
    timer?.cancel();
    controller.close();
  });
  emit();
  return controller.stream;
}

/// Today's date (local midnight), re-emitted at each midnight so providers that
/// depend on "today" refresh on rollover.
final todayProvider = StreamProvider<DateTime>((ref) {
  return _boundaryStream(
    ref,
    initial: (now) => DateTime(now.year, now.month, now.day),
    nextBoundary: (now) => DateTime(now.year, now.month, now.day + 1),
  );
});

/// The current time, re-emitted at the start of every minute (for "live / in N
/// min / ended" labels).
final minuteTickProvider = StreamProvider.autoDispose<DateTime>((ref) {
  return _boundaryStream(
    ref,
    initial: (now) => now,
    nextBoundary: (now) =>
        DateTime(now.year, now.month, now.day, now.hour, now.minute + 1),
  );
});
