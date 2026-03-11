import '../logging/logger.dart';
import 'package:get_it/get_it.dart';
import 'package:televerse/televerse.dart';

import '../../data/datasources/analytics_datasource.dart';
import '../../data/datasources/sembast_datasource.dart';
import '../../data/repositories/sembast_analytics_repository.dart';
import '../../data/repositories/sembast_session_repository.dart';
import '../../data/repositories/televerse_bot_repository.dart';
import '../../domain/repositories/analytics_repository.dart';
import '../../domain/repositories/bot_repository.dart';
import '../../domain/repositories/session_repository.dart';
import '../admin/admin_guard.dart';
import '../analytics/analytics_service.dart';
import '../navigation/navigation_manager.dart';
import '../navigation/route_registry.dart';

/// Глобальный экземпляр GetIt для Dependency Injection
final getIt = GetIt.instance;

/// Инициализация всех зависимостей приложения
Future<void> setupDependencies(
  String botToken, {
  List<String> adminUsernames = const [],
}) async {
  // Создание HTTP клиента с правильными timeout
  // receiveTimeout должен быть больше чем long polling timeout (30s) + запас!
  final httpClient = DioHttpClient(
    timeout: Duration(seconds: 40), // Connection timeout
    receiveTimeout: Duration(seconds: 60), // Long polling (30s) + запас (30s)
  );

  // Создание экземпляра Televerse Bot
  // LongPollingFetcher будет создан автоматически при bot.start()
  // с дефолтным timeout=30s и limit=100
  final bot = Bot(
    botToken,
    httpClient: httpClient,
  );

  log('🤖 Bot initialized with:');
  log('   Long polling timeout: 30s (default)');
  log('   HTTP receive timeout: 60s');
  log('   Connection timeout: 40s');

  getIt.registerSingleton<Bot>(bot);

  // Регистрация RouteRegistry как singleton
  getIt.registerSingleton<RouteRegistry>(RouteRegistry());

  // Регистрация AdminGuard
  getIt.registerSingleton<AdminGuard>(
    AdminGuard(adminUsernames: adminUsernames),
  );

  // Инициализация и регистрация Sembast datasource
  final sembastDatasource = SembastDatasource();
  await sembastDatasource.database; // Инициализируем БД заранее
  getIt.registerSingleton<SembastDatasource>(sembastDatasource);

  // Инициализация и регистрация Analytics datasource
  final analyticsDatasource = AnalyticsDatasource();
  await analyticsDatasource.database; // Инициализируем БД заранее
  getIt.registerSingleton<AnalyticsDatasource>(analyticsDatasource);

  // Регистрация репозитория и сервиса аналитики
  getIt.registerLazySingleton<AnalyticsRepository>(
    () => SembastAnalyticsRepository(datasource: getIt<AnalyticsDatasource>()),
  );
  getIt.registerLazySingleton<AnalyticsService>(
    () => AnalyticsService(repository: getIt<AnalyticsRepository>()),
  );

  // Регистрация репозиториев как lazy singletons
  getIt.registerLazySingleton<SessionRepository>(
    () => SembastSessionRepository(datasource: getIt<SembastDatasource>()),
  );

  getIt.registerLazySingleton<BotRepository>(
    () => TeleverseBotRepository(bot: getIt<Bot>()),
  );

  // Регистрация NavigationManager
  getIt.registerLazySingleton<NavigationManager>(
    () => NavigationManager(
      routeRegistry: getIt<RouteRegistry>(),
      sessionRepository: getIt<SessionRepository>(),
      botRepository: getIt<BotRepository>(),
      analyticsService: getIt<AnalyticsService>(),
    ),
  );
}
