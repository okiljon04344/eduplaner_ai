import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/app_providers.dart';

/// The four main app destinations — shared by [AppBottomNav] and
/// [AppNavRail] (mobile bottom nav vs. tablet/desktop side rail), which
/// otherwise duplicated this list and the tap-handling logic below.
const kNavRoutes = ['/home', '/timetable', '/assignments', '/ai'];

/// Whether [route] is the currently active destination for [context].
bool isNavRouteActive(BuildContext context, String route) =>
    GoRouterState.of(context).matchedLocation.startsWith(route);

/// Updates [shellTabIndexProvider] to match [route] and navigates to it —
/// shared tap handler for both nav bar and nav rail items.
void navigateToNavRoute(WidgetRef ref, BuildContext context, String route) {
  final idx = kNavRoutes.indexOf(route);
  if (idx >= 0) ref.read(shellTabIndexProvider.notifier).state = idx;
  context.go(route);
}
