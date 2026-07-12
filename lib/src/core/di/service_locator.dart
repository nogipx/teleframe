import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:get_it/get_it.dart';
// televerse exports its own `HttpClient` interface (implemented by
// DioHttpClient); hide it so `HttpClient` refers to dart:io's.
import 'package:televerse/televerse.dart' hide HttpClient;

import '../logging/logger.dart';

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
  // Создание HTTP клиента с правильными timeout.
  // receiveTimeout должен быть больше чем long polling timeout (30s) + запас!
  // TELEGRAM_PROXY (host:port или http://[user:pass@]host:port) маршрутизирует
  // весь трафик к api.telegram.org через HTTP CONNECT-прокси — нужно там, где
  // Telegram недоступен напрямую (например из РФ-инфраструктуры).
  final httpClient = _buildHttpClient(Platform.environment['TELEGRAM_PROXY']);

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

/// Builds the televerse HTTP client, optionally routing all Telegram API
/// traffic through an HTTP CONNECT proxy given by [proxy] (`host:port` or
/// `http://[user:pass@]host:port`). Needed where api.telegram.org is not
/// directly reachable (e.g. Russian infrastructure).
DioHttpClient _buildHttpClient(String? proxy) {
  const connectTimeout = Duration(seconds: 40);
  const receiveTimeout = Duration(seconds: 60);

  final value = proxy?.trim() ?? '';
  if (value.isEmpty) {
    return DioHttpClient(
      timeout: connectTimeout,
      receiveTimeout: receiveTimeout,
    );
  }

  final uri =
      value.contains('://') ? Uri.parse(value) : Uri.parse('http://$value');
  final hostPort = '${uri.host}:${uri.port}';
  final creds = uri.userInfo.isNotEmpty ? uri.userInfo.split(':') : const [];

  // Mirror televerse's default BaseOptions so the Bot API keeps working;
  // only the proxy adapter is added on top.
  final dio = Dio(
    BaseOptions(
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      sendTimeout: connectTimeout,
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': 'Televerse/1.0',
      },
      validateStatus: (status) => status != null && status < 500,
    ),
  );
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () {
      final client = HttpClient();
      client.findProxy = (_) => 'PROXY $hostPort';
      if (creds.length == 2) {
        client.addProxyCredentials(
          uri.host,
          uri.port,
          '',
          HttpClientBasicCredentials(creds[0], creds[1]),
        );
      }
      return client;
    },
  );
  log('🌐 Routing Telegram API through proxy $hostPort');
  return DioHttpClient(dio: dio);
}
