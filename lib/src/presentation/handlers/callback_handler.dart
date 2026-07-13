import '../../core/logging/logger.dart';
import '../../core/admin/navigation_context_admin.dart';
import '../../core/analytics/analytics_service.dart';
import 'package:get_it/get_it.dart';
import 'package:televerse/televerse.dart';

import '../../core/navigation/navigation_manager.dart';
import '../../core/navigation/route_registry.dart';
import '../../domain/entities/buttons/link_button.dart';
import '../../domain/entities/keyboard_button.dart';
import '../../domain/repositories/bot_repository.dart';
import '../../domain/repositories/session_repository.dart';

/// Настройка обработчика callback queries (нажатий на inline-кнопки)
void setupCallbackHandler(
  Bot bot,
  NavigationManager navManager,
  BotRepository botRepository, {
  RouteRegistry? routeRegistry,
  SessionRepository? sessionRepository,
}) {
  // Используем метод callbackQuery для обработки всех callback queries
  bot.callbackQuery(RegExp('.*'), (ctx) async {
    final query = ctx.callbackQuery;
    if (query == null) return;

    final data = query.data ?? '';
    final userId = query.from.id.toInt();
    final chatId = query.message?.chat.id.toInt() ?? userId;

    log('Callback query from user $userId: $data');

    try {
      // Парсинг callback data
      if (data.startsWith('nav:')) {
        // Навигационное действие
        final navData = data.substring(4); // Убрать префикс "nav:"

        // Парсим routeId (до символа # если есть)
        final hashIndex = navData.indexOf('#');
        final routeId = hashIndex != -1
            ? navData.substring(0, hashIndex)
            : navData;

        if (routeId == 'back') {
          // Возврат назад
          await navManager.goBack(userId: userId, chatId: chatId);
        } else if (routeId == 'home') {
          // Переход на домашний экран
          await _handleHomeNavigation(
            userId,
            chatId,
            navManager,
            routeRegistry,
          );
        } else {
          // Навигация на указанный экран - нужно найти кнопку чтобы получить параметры
          await _handleNavigation(
            data,
            userId,
            chatId,
            routeId,
            navManager,
            routeRegistry,
            sessionRepository,
          );
        }
      } else if (data.startsWith('action:')) {
        // Пользовательское действие
        final actionData = data.substring(7); // Убрать префикс "action:"
        await _handleCustomAction(
          actionData,
          userId,
          chatId,
          query,
          navManager,
          botRepository,
          routeRegistry,
          sessionRepository,
        );
      } else {
        log('Unknown callback data format: $data');
      }

      // Ответить на callback query (убрать "часики")
      await botRepository.answerCallbackQuery(queryId: query.id);
    } catch (e, stackTrace) {
      log('Error handling callback query: $e');
      log(stackTrace);

      // Все равно ответить на callback query
      await botRepository.answerCallbackQuery(
        queryId: query.id,
        text: 'Произошла ошибка. Попробуйте снова.',
      );
    }
  });
}

/// Обработка перехода на домашний экран
Future<void> _handleHomeNavigation(
  int userId,
  int chatId,
  NavigationManager navManager,
  RouteRegistry? routeRegistry,
) async {
  if (routeRegistry == null) {
    log('Warning: RouteRegistry not provided, cannot navigate to home');
    return;
  }

  final homeRoute = routeRegistry.homeRoute;
  await navManager.navigateTo(
    userId: userId,
    chatId: chatId,
    routeId: homeRoute,
  );
}

/// Обработка навигации с параметрами
Future<void> _handleNavigation(
  String callbackData,
  int userId,
  int chatId,
  String routeId,
  NavigationManager navManager,
  RouteRegistry? routeRegistry,
  SessionRepository? sessionRepository,
) async {
  Map<String, dynamic>? params;

  // Если есть доступ к реестру и сессии - попробуем найти кнопку с параметрами
  if (routeRegistry != null && sessionRepository != null) {
    final context = await sessionRepository.getContext(userId);
    if (context.currentRoute != null) {
      try {
        final screen = routeRegistry.createScreen(
          context.currentRoute!,
          context,
        );
        final buttonRows = await screen.getButtons(context);

        // Ищем кнопку с этим callbackData
        for (final row in buttonRows) {
          for (final button in row) {
            if (button.callbackData == callbackData) {
              // Трекинг клика — админы не учитываются
              if (!context.isAdmin) {
                GetIt.instance<AnalyticsService>()
                    .trackClick(userId, button.text)
                    .ignore();
              }
              // Нашли кнопку - проверяем есть ли параметры
              if (button.action is NavigateAction) {
                final navAction = button.action as NavigateAction;
                params = navAction.params;
              }
              break;
            }
          }
          if (params != null) break;
        }
      } catch (e) {
        log('Warning: Failed to get button params: $e');
      }
    }
  }

  // Навигация с параметрами (если есть)
  await navManager.navigateTo(
    userId: userId,
    chatId: chatId,
    routeId: routeId,
    params: params,
  );
}

/// Обработка пользовательских действий
Future<void> _handleCustomAction(
  String actionData,
  int userId,
  int chatId,
  dynamic query,
  NavigationManager navManager,
  BotRepository botRepository,
  RouteRegistry? routeRegistry,
  SessionRepository? sessionRepository,
) async {
  if (routeRegistry == null || sessionRepository == null) {
    log(
      'Warning: RouteRegistry or SessionRepository not provided, CustomAction will not be executed',
    );
    return;
  }

  // Получить текущий контекст и экран
  final context = await sessionRepository.getContext(userId);
  if (context.currentRoute == null) {
    log('Warning: No current route in context');
    return;
  }

  // Создать экран
  final screen = routeRegistry.createScreen(context.currentRoute!, context);

  // Найти кнопку с этим callbackData
  final buttonRows = await screen.getButtons(context);
  final callbackData = 'action:$actionData';

  KeyboardButton? targetButton;
  // Ищем по всем строкам
  for (final row in buttonRows) {
    for (final button in row) {
      if (button.callbackData == callbackData) {
        targetButton = button;
        break;
      }
    }
    if (targetButton != null) break;
  }

  if (targetButton == null) {
    log('Warning: Button with callbackData "$callbackData" not found');
    return;
  }

  // Трекинг клика
  GetIt.instance<AnalyticsService>()
      .trackClick(userId, targetButton.text)
      .ignore();

  // Выполнить CustomAction если есть
  if (targetButton.action is CustomAction) {
    final customAction = targetButton.action as CustomAction;
    log('Executing CustomAction for: $callbackData');

    // Отправить статус "typing" перед выполнением
    await botRepository.sendChatAction(chatId: chatId, action: 'typing');

    // Выполнить обработчик - он может вернуть HandlerResult
    final result = await customAction.handler(context);

    // Обработать результат
    if (result != null) {
      switch (result) {
        case NoneResult():
          // Ничего не делать, только сохранить контекст
          await sessionRepository.saveContext(userId, context);
          log('✓ CustomAction executed (no action)');

        case NavigateResult(:final routeId, :final params):
          // Сохранить изменённый контекст перед навигацией: navigateTo
          // перечитывает контекст из хранилища, поэтому несохранённые
          // изменения из обработчика (например, sign-out, очистивший сессию)
          // иначе потеряются.
          await sessionRepository.saveContext(userId, context);
          // Навигация на указанный маршрут с параметрами
          await navManager.navigateTo(
            userId: userId,
            chatId: chatId,
            routeId: routeId,
            params: params,
          );
          log('✓ CustomAction executed and navigated to $routeId');
          if (params != null && params.isNotEmpty) {
            log('  with params: $params');
          }

        case RefreshResult():
          // Сохранить изменённый контекст перед обновлением экрана
          await sessionRepository.saveContext(userId, context);
          // Явное обновление экрана
          await navManager.refreshCurrentScreen(
            userId: userId,
            chatId: chatId,
          );
          log('✓ CustomAction executed and screen refreshed (explicit)');

        case MessageResult(:final text, :final images, :final links):
          // Создать клавиатуру со ссылками (если есть)
          List<List<KeyboardButton>>? keyboard;
          if (links.isNotEmpty) {
            keyboard = links.map((link) {
              return [
                LinkButton(
                  text: link.text,
                  url: link.url,
                ),
              ];
            }).toList();
          }

          // Отправить информационное сообщение (НЕ трекается!)
          await botRepository.sendMessage(
            chatId: chatId,
            text: text,
            images: images,
            keyboard: keyboard,
          );

          // НЕ сохраняем messageIds - сообщение остаётся в чате
          // Сохранить контекст (без изменений в messageIds)
          await sessionRepository.saveContext(userId, context);
          log(
            '✓ CustomAction executed and info message sent: "$text" (${images.length} images, ${links.length} links)',
          );

        case AlertResult(:final text):
          // Показать всплывающее уведомление (alert)
          await botRepository.answerCallbackQuery(
            queryId: query.id,
            text: text,
          );
          // Сохранить контекст
          await sessionRepository.saveContext(userId, context);
          log('✓ CustomAction executed and alert shown: "$text"');
      }
    } else {
      // null + refreshScreen: false = только сохранить контекст
      await sessionRepository.saveContext(userId, context);
      log('✓ CustomAction executed (screen not refreshed)');
    }
  } else {
    log('Warning: Button action is not CustomAction');
  }
}
