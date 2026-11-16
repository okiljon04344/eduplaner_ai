import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/utils/responsive.dart';
import '../../features/school/school_providers.dart';
import 'app_bottom_nav.dart';
import 'app_nav_rail.dart';

/// Wraps every routed screen with a directional slide when switching tabs.
///
/// UZ: Har bir yo'naltirilgan ekranni tablar almashganda yo'naltirilgan siljish (slide) bilan o'raydi.
class AppShell extends ConsumerWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(schoolReminderSyncProvider);
    final isTablet = context.isTablet;
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: !isTablet,
      body: isTablet
          ? Row(
              children: [
                const AppNavRail(),
                // Each tab clamps its own content column, so glows and
                // full-bleed headers can span the whole area.
                // UZ: Har bir tab o'z kontent ustunini cheklaydi, shunda porlashlar (glows) va
                // to'liq kenglikdagi sarlavhalar butun maydonni qamrab olishi mumkin.
                Expanded(child: _DirectionalTab(child: child)),
              ],
            )
          : _DirectionalTab(child: child),
      bottomNavigationBar: isTablet ? null : const AppBottomNav(),
    );
  }
}

class _DirectionalTab extends ConsumerStatefulWidget {
  final Widget child;
  const _DirectionalTab({required this.child});

  @override
  ConsumerState<_DirectionalTab> createState() => _DirectionalTabState();
}

class _DirectionalTabState extends ConsumerState<_DirectionalTab> {
  // Bumped on every tab switch (even back to a previously-visited index) so
  // the KeyedSubtree below is never reused across visits — AppColors' mutable
  // statics don't flow through InheritedWidget, so a reused Element can paint
  // stale colors picked up from before this tab was last hidden.
  // UZ: Har bir tab almashganda (hatto ilgari tashrif buyurilgan indeksga qaytganda ham) oshiriladi,
  // shunda quyidagi KeyedSubtree tashriflar davomida hech qachon qayta ishlatilmaydi — AppColors'ning
  // o'zgaruvchan statiklari InheritedWidget orqali o'tmaydi, shuning uchun qayta ishlatilgan Element
  // ushbu tab oxirgi marta yashirilishidan oldin olingan eski ranglarni chizib qo'yishi mumkin.
  int _visitNonce = 0;

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(shellTabIndexProvider, (prev, next) {
      if (prev != null && prev != next) {
        setState(() {
          _visitNonce++;
        });
      }
    });

    final index = ref.watch(shellTabIndexProvider);
    final isReduced = reduceMotion(context);

    // One copy of the shell child only: it is go_router's Navigator, which
    // carries a GlobalKey, so an AnimatedSwitcher (old + new child alive at
    // once) throws "Duplicate GlobalKey" on every tab switch. A fresh key
    // restarts this entrance instead; the page that left is not kept.
    // UZ: Shell child faqat bitta nusxada bo'ladi: u go_router'ning Navigator'i va GlobalKey'ga
    // ega, shuning uchun AnimatedSwitcher (eski va yangi child bir vaqtda) har tab almashganda
    // "Duplicate GlobalKey" xatosini beradi. Buning o'rniga yangi kalit shu kirish animatsiyasini
    // qayta boshlaydi; chiqib ketgan sahifa saqlanmaydi.
    return TweenAnimationBuilder<double>(
      key: ValueKey('${index}_$_visitNonce'),
      tween: Tween(begin: _visitNonce == 0 ? 1.0 : 0.0, end: 1.0),
      duration: isReduced ? AppMotion.fadeDuration : AppMotion.screenDuration,
      curve: AppMotion.strongEaseOut,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: isReduced ? child : Transform.translate(offset: Offset(0, 10.0 * (1.0 - t)), child: child),
      ),
      child: widget.child,
    );
  }
}
