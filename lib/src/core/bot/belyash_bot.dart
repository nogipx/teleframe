import '../logging/logger.dart';
import 'package:televerse/televerse.dart';

import '../../domain/entities/screen_state.dart';
import '../../domain/repositories/bot_repository.dart';
import '../../domain/repositories/session_repository.dart';
import '../di/service_locator.dart';
import '../navigation/navigation_manager.dart';
import '../navigation/route_registry.dart';
import '../utils/static_assets.dart';
import '../../presentation/handlers/callback_handler.dart';
import 'bot_watchdog.dart';

/// Конфигурация бота
class BotConfig {
  /// Токен бота (обязательно)
  final String token;

  /// Список экранов для регистрации (простые экраны без параметров)
  final List<ScreenState> screens;

  /// Фабрики экранов с параметрами (ключ - routeId, значение - фабрика)
  final Map<String, ScreenFactory> screenFactories;

  /// Фабрика для NotFound экрана
  final ScreenFactory? notFoundFactory;

  /// Показывать ли verbose информацию (по умолчанию false)
  final bool verbose;

  /// ID маршрута стартового экрана (при /start) - обязательный параметр
  final String startRoute;

  /// ID маршрута домашнего экрана (для возврата "домой")
  ///
  /// Если не указан, используется startRoute
  final String? homeRoute;

  /// Список username-ов (без @) пользователей с правами администратора.
  ///
  /// Администраторы получают доступ к экранам, унаследованным от [AdminScreen].
  /// Проверка происходит по Telegram username (регистронезависимо).
  ///
  /// Пример: `['john_doe', 'alice_admin']`
  final List<String> adminUsernames;

  const BotConfig({
    required this.token,
    required this.startRoute,
    this.screens = const [],
    this.screenFactories = const {},
    this.notFoundFactory,
    this.verbose = false,
    this.homeRoute,
    this.adminUsernames = const [],
  });
}

/// Главный класс Telegram бота
class TeleframeBot {
  final BotConfig config;
  late Bot _bot;
  late NavigationManager _navManager;
  late RouteRegistry _routeRegistry;
  late BotRepository _botRepository;
  late SessionRepository _sessionRepository;
  late BotWatchdog _watchdog;

  TeleframeBot(this.config);

  /// Запустить бота
  Future<void> start() async {
    try {
      log('🚀 Initializing Teleframe bot...');

      // Инициализация статических ресурсов
      await StaticAssets.initialize();
      if (config.verbose) {
        log('📁 Static assets initialized');
        StaticAssets.printInfo();
      }

      // Инициализация зависимостей
      log('🔧 Setting up dependencies...');
      await setupDependencies(config.token, adminUsernames: config.adminUsernames);

      // Получение зависимостей
      _bot = getIt<Bot>();
      _routeRegistry = getIt<RouteRegistry>();
      _navManager = getIt<NavigationManager>();
      _botRepository = getIt<BotRepository>();
      _sessionRepository = getIt<SessionRepository>();

      // Регистрация экранов
      log('📝 Registering screens...');
      _registerScreens();

      // Установка стартового и домашнего маршрутов
      _routeRegistry.setStartRoute(config.startRoute);
      // Если homeRoute не указан, используем startRoute
      _routeRegistry.setHomeRoute(config.homeRoute ?? config.startRoute);

      // Регистрация NotFound экрана
      if (config.notFoundFactory != null) {
        _routeRegistry.setNotFoundFactory(config.notFoundFactory!);
      }

      if (config.verbose) {
        log('📋 Registered routes: ${_routeRegistry.registeredRoutes}');
      }

      // Настройка обработчиков
      log('⚙️  Setting up handlers...');
      _setupHandlers();

      // Настройка watchdog для мониторинга активности бота
      log('🐕 Setting up watchdog...');
      _setupWatchdog();

      // Запуск бота
      log('✅ Teleframe bot initialized successfully!');
      log('🚀 Start route: ${config.startRoute}');
      log('🏠 Home route: ${config.homeRoute ?? config.startRoute}');
      log('📞 Starting bot polling...');

      // ВАЖНО: bot.start() в televerse запускает long polling в фоне
      // и сразу возвращает управление. Мы должны держать процесс активным.
      _bot.start();

      // Держим процесс активным бесконечно
      // Бот будет работать до получения сигнала завершения (SIGTERM/SIGINT)
      log('🔄 Bot is running. Keeping process alive...');
      log('Press Ctrl+C to stop the bot.');
      await Future<void>.delayed(Duration(days: 365 * 100)); // ~100 лет
    } catch (e, stackTrace) {
      log('❌ Fatal error during bot initialization: $e');
      log('Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Зарегистрировать экраны в реестре маршрутов
  void _registerScreens() {
    // Регистрация простых экранов (без параметров)
    for (final screen in config.screens) {
      _routeRegistry.register(screen.routeId, (ctx) => screen);
    }

    // Регистрация экранов с фабриками (с параметрами)
    config.screenFactories.forEach((routeId, factory) {
      _routeRegistry.register(routeId, factory);
    });
  }

  /// Настроить обработчики команд и callback queries
  void _setupHandlers() {
    // Обработчик команды /start
    _bot.command('start', (ctx) async {
      final userId = ctx.from?.id.toInt();
      final chatId = ctx.chat?.id.toInt();

      if (userId == null || chatId == null) {
        log('Warning: Unable to get user or chat ID');
        return;
      }

      log('User $userId started the bot');

      // Получить контекст
      final context = await _sessionRepository.getContext(userId);

      // Удалить последние сообщения от бота при старте
      if (context.lastMessages.isNotEmpty) {
        log('Deleting ${context.lastMessages.length} previous bot messages');
        final messageIds = context.lastMessageIds;
        try {
          await _botRepository.deleteMessages(
            chatId: chatId,
            messageIds: messageIds,
          );
          context.lastMessages.clear();
          log('Successfully deleted messages');
        } catch (e) {
          // Игнорируем ошибки - сообщения могли быть уже удалены или устарели (>48ч)
          log('Warning: Failed to delete messages: $e');
          // Очищаем список в любом случае
          context.lastMessages.clear();
        }
      }

      // Сохранить данные пользователя в контексте
      final userName = ctx.from?.firstName ?? 'Друг';
      context.setData('userName', userName);
      final username = ctx.from?.username;
      if (username != null) context.setData('_username', username);
      await _sessionRepository.saveContext(userId, context);

      // Перейти на стартовый экран
      await _navManager.navigateTo(
        userId: userId,
        chatId: chatId,
        routeId: config.startRoute,
      );
    });

    // Обработчик callback queries
    setupCallbackHandler(
      _bot,
      _navManager,
      _botRepository,
      routeRegistry: _routeRegistry,
      sessionRepository: _sessionRepository,
    );
  }

  /// Настроить watchdog для мониторинга активности бота
  void _setupWatchdog() {
    _watchdog = BotWatchdog(
      inactivityThreshold: Duration(minutes: 5), // Порог неактивности
      checkInterval: Duration(minutes: 1),       // Частота проверки
      onInactivity: () async {
        log('🔄 Restarting bot due to inactivity...');
        try {
          await _bot.stop();
          await Future.delayed(Duration(seconds: 2));
          await _bot.start();
          log('✅ Bot restarted successfully');
        } catch (e) {
          log('❌ Error restarting bot: $e');
        }
      },
    );

    _watchdog.start();

    // Обновлять heartbeat при получении любых обновлений
    // Используем middleware для отслеживания всех обновлений
    _bot.use((ctx, next) async {
      _watchdog.heartbeat();
      await next();
    });
  }

  /// Остановить бота
  Future<void> stop() async {
    _watchdog.stop();
    await _bot.stop();
    log('🛑 Bot stopped');
  }
}
