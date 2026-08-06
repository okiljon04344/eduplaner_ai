import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Centralized Lottie animation helpers.
///
/// All animation asset paths are defined here so a single rename touches
/// one place.  Each widget falls back gracefully when the asset is missing
/// or the parser cannot render the JSON.
class AppLottie {
  AppLottie._();

  static const _loading = 'assets/animations/loading.json';
  static const _success = 'assets/animations/success.json';
  static const _error   = 'assets/animations/error.json';

  // ── Public factory widgets ────────────────────────────────────────────────

  /// Spinning ring loader — replaces [CircularProgressIndicator] in AI/auth
  /// screens for a more polished look.  Loops indefinitely.
  static Widget loading({double size = 64}) => _LottieLoop(
        asset: _loading,
        size: size,
      );

  /// Scale-in green circle with an animated checkmark draw.  Plays once then
  /// holds the last frame.  Use inside toasts or success screens.
  static Widget success({double size = 80}) => _LottieOnce(
        asset: _success,
        size: size,
      );

  /// Scale-in red circle with an animated X draw (includes a short shake).
  /// Plays once then holds the last frame.
  static Widget error({double size = 80}) => _LottieOnce(
        asset: _error,
        size: size,
      );

  /// Inline loading indicator that mirrors the style of the rest of the app
  /// but sits inside a centered column — ready to drop into any async screen.
  static Widget fullScreenLoading({String? label}) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            loading(size: 80),
            if (label != null) ...[
              const SizedBox(height: 12),
              Text(
                label,
                style: const TextStyle(fontSize: 14, color: Colors.white60),
              ),
            ],
          ],
        ),
      );
}

// ── Internal implementation widgets ─────────────────────────────────────────

/// Plays a Lottie animation in a continuous loop.
class _LottieLoop extends StatelessWidget {
  final String asset;
  final double size;
  const _LottieLoop({required this.asset, required this.size});

  @override
  Widget build(BuildContext context) {
    return Lottie.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      // Loops forever — correct for loading spinners.
      repeat: true,
      errorBuilder: (_, __, ___) => SizedBox(
        width: size,
        height: size,
        child: const CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}

/// Plays a Lottie animation exactly once and freezes on the last frame.
class _LottieOnce extends StatefulWidget {
  final String asset;
  final double size;
  const _LottieOnce({required this.asset, required this.size});

  @override
  State<_LottieOnce> createState() => _LottieOnceState();
}

class _LottieOnceState extends State<_LottieOnce>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    // Duration is overridden by Lottie.onLoaded; use a safe default.
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Lottie.asset(
      widget.asset,
      controller: _ctrl,
      width: widget.size,
      height: widget.size,
      fit: BoxFit.contain,
      // Inform the controller of the true animation duration once loaded.
      onLoaded: (comp) {
        _ctrl.duration = comp.duration;
        _ctrl.forward(from: 0);
      },
      repeat: false,
      errorBuilder: (_, __, ___) => SizedBox(
        width: widget.size,
        height: widget.size,
      ),
    );
  }
}
