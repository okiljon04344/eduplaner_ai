import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Emits [initial] immediately, then re-emits at every instant returned by
/// [nextBoundary] (called with the current time after each emission). The
/// timer is cancelled and the stream closed when the provider is disposed.
///
/// UZ: [initial] qiymatini darhol uzatadi, so'ngra [nextBoundary] qaytargan har bir lahzada
/// (har bir uzatishdan keyin joriy vaqt bilan chaqiriladi) qayta uzatadi. Provayder dispose
/// qilinganda taymer bekor qilinadi va oqim yopiladi.
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

/// Today's date (local midnight), emitted immediately and again at each next
/// local midnight, so providers that depend on "today" refresh on rollover
/// instead of reading `DateTime.now()` once.
///
/// UZ: Bugungi sana (mahalliy yarim tun), darhol va keyingi har bir mahalliy yarim tunda
/// yana uzatiladi, shuning uchun "today" ga bog'liq provayderlar `DateTime.now()` ni bir marta
/// o'qish o'rniga kun almashganda yangilanadi.
final todayProvider = StreamProvider<DateTime>((ref) {
  return _boundaryStream(
    ref,
    initial: (now) => DateTime(now.year, now.month, now.day),
    nextBoundary: (now) => DateTime(now.year, now.month, now.day + 1),
  );
});

/// The current time, emitted immediately and then once every minute aligned
/// to the start of the minute — for labels like "live / in N min / ended".
///
/// UZ: Joriy vaqt, darhol va keyin daqiqa boshiga tekislangan holda har daqiqada bir marta
/// uzatiladi — "live / in N min / ended" kabi yorliqlar uchun.
final minuteTickProvider = StreamProvider.autoDispose<DateTime>((ref) {
  return _boundaryStream(
    ref,
    initial: (now) => now,
    nextBoundary: (now) =>
        DateTime(now.year, now.month, now.day, now.hour, now.minute + 1),
  );
});
