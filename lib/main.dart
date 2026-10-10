import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/providers/auth_providers.dart';
import 'models/app_user.dart';

void main() {
  runApp(const ProviderScope(child: VishnuConnectApp()));
}

class _RouterRefresh extends ChangeNotifier {
  void refresh() => notifyListeners();
}

class VishnuConnectApp extends ConsumerStatefulWidget {
  const VishnuConnectApp({super.key});

  @override
  ConsumerState<VishnuConnectApp> createState() => _VishnuConnectAppState();
}

class _VishnuConnectAppState extends ConsumerState<VishnuConnectApp> {
  late final _RouterRefresh _routerRefresh;
  late final GoRouter _router;
  late final ProviderSubscription<AsyncValue<AppUser?>> _sessionSubscription;

  @override
  void initState() {
    super.initState();
    _routerRefresh = _RouterRefresh();
    _router = createAppRouter(
      refreshListenable: _routerRefresh,
      readSession: () => ref.read(authControllerProvider),
    );
    _sessionSubscription = ref.listenManual(
      authControllerProvider,
      (previous, next) => _routerRefresh.refresh(),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _sessionSubscription.close();
    _router.dispose();
    _routerRefresh.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'VishnuConnect',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: _router,
    );
  }
}
