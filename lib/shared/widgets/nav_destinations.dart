import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/app_providers.dart';

/// The four main destinations, shared by [AppBottomNav] and [AppNavRail].
const kNavRoutes = ['/home', '/timetable', '/assignments', '/ai'];

/// Whether [route] is the active destination.
bool isNavRouteActive(BuildContext context, String route) =>
    GoRouterState.of(context).matchedLocation.startsWith(route);

/// Syncs [shellTabIndexProvider] with [route] and navigates to it.
void navigateToNavRoute(WidgetRef ref, BuildContext context, String route) {
  final idx = kNavRoutes.indexOf(route);
  if (idx >= 0) ref.read(shellTabIndexProvider.notifier).state = idx;
  context.go(route);
}
