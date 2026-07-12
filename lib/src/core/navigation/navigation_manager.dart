import '../../core/admin/navigation_context_admin.dart';
import '../../core/analytics/analytics_service.dart';
import '../../domain/entities/buttons/copy_button.dart';
import '../../domain/entities/buttons/link_button.dart';
import '../../domain/entities/image_send_strategy.dart';
import '../../domain/entities/keyboard_button.dart';
import '../../domain/entities/navigation_context.dart';
import '../../domain/entities/screen_state.dart';
import '../../domain/entities/sent_message.dart';
import '../../domain/repositories/bot_repository.dart';
import '../../domain/repositories/session_repository.dart';
import '../logging/logger.dart';
import 'route_registry.dart';

/// Режим обновления экрана при refresh
enum _RefreshMode {
  /// Ничего не изменилось - пропустить обновление
  noChange,

  /// Изменился только текст - editMessage для текстового сообщения
  editTextOnly,

  /// Изменилось изображение - editMessageMedia + editMessage
  editMedia,

  /// Структура изменилась - удалить и отправить заново
  resend,
}

/// Менеджер навигации между экранами бота
///
/// Управляет переходами, стеком навигации и отправкой сообщений
class NavigationManager {
  final RouteRegistry _routeRegistry;
  final SessionRepository _sessionRepository;
  final BotRepository _botRepository;
  final AnalyticsService? _analyticsService;

  NavigationManager({
    required RouteRegistry routeRegistry,
    required SessionRepository sessionRepository,
    required BotRepository botRepository,
    AnalyticsService? analyticsService,
  }) : _routeRegistry = routeRegistry,
       _sessionRepository = sessionRepository,
       _botRepository = botRepository,
       _analyticsService = analyticsService;

  /// Перейти на новый экран
  ///
  /// Параметры:
  /// - [userId]: ID пользователя
  /// - [chatId]: ID чата
  /// - [routeId]: ID целевого маршрута
  /// - [params]: Опциональные параметры для передачи в контекст экрана
  Future<void> navigateTo({
    required int userId,
    required int chatId,
    required String routeId,
    Map<String, dynamic>? params,
  }) async {
    // Показать индикатор "typing"
    await _botRepository.sendChatAction(chatId: chatId, action: 'typing');

    // Получить или создать контекст
    var context = await _sessionRepository.getContext(userId);

    // Обновить chatId если необходимо
    if (context.chatId != chatId) {
      context = context.copyWith(chatId: chatId);
    }

    // Проверить права доступа к целевому экрану
    try {
      final targetScreen = _routeRegistry.createScreen(routeId, context);
      if (!targetScreen.canAccess(context)) {
        log('🚫 Access denied to "$routeId" for user $userId');
        // Оставаться на текущем экране — просто refresh
        if (context.currentRoute != null) {
          await refreshCurrentScreen(userId: userId, chatId: chatId);
        }
        return;
      }
    } catch (e) {
      log('Warning: canAccess check failed for $routeId: $e');
    }

    // Захватываем текущий маршрут ДО модификации стека — нужен для трекинга воронки
    final previousRoute = context.currentRoute;

    // Обработка предыдущих сообщений - проверяем настройку текущего экрана
    bool shouldKeepMessages = false;
    if (context.currentRoute != null) {
      try {
        final currentScreen = _routeRegistry.createScreen(
          context.currentRoute!,
          context,
        );
        shouldKeepMessages = currentScreen.keepMessageOnExit(context);
        log(
          '🔍 Screen ${context.currentRoute}: keepMessageOnExit = $shouldKeepMessages',
        );
      } catch (e) {
        log(
          'Warning: Failed to check keepMessageOnExit for ${context.currentRoute}: $e',
        );
      }
    }

    if (shouldKeepMessages) {
      log(
        '💾 Keeping messages from ${context.currentRoute}, removing keyboard only',
      );
      // Убираем ТОЛЬКО интерактивные кнопки (не ссылки и не копирование)
      if (context.lastMessages.isNotEmpty) {
        final currentScreen = _routeRegistry.createScreen(
          context.currentRoute!,
          context,
        );
        final buttons = await currentScreen.getButtons(context);

        // Фильтруем кнопки - оставляем только Link и Copy
        final nonInteractiveButtons = _filterNonInteractiveButtons(buttons);

        if (nonInteractiveButtons.isNotEmpty) {
          // Есть Link/Copy кнопки - редактируем клавиатуру, оставляя их
          log(
            '  Keeping ${_countButtons(nonInteractiveButtons)} link/copy buttons',
          );

          try {
            // Определяем тип последнего сообщения
            final lastMessage = context.lastMessages.last;

            if (lastMessage.type == MessageType.photo) {
              // Фото с caption - используем editMessageMedia
              final imageUrl = lastMessage.content!;
              await _botRepository.editMessageMedia(
                chatId: chatId,
                messageId: lastMessage.messageId,
                imageUrl: imageUrl,
                caption: await currentScreen.getMessage(context),
                keyboard: nonInteractiveButtons,
                parseMode: currentScreen.parseMode,
              );
            } else {
              // Текстовое сообщение - используем editMessage
              await _botRepository.editMessage(
                chatId: chatId,
                messageId: lastMessage.messageId,
                text: await currentScreen.getMessage(context),
                keyboard: nonInteractiveButtons,
                parseMode: currentScreen.parseMode,
              );
            }
          } catch (e) {
            log('  Warning: Failed to edit message: $e');
            // Игнорируем ошибку - сообщение останется с исходными кнопками
          }
        } else {
          // Нет Link/Copy кнопок - полностью удаляем клавиатуру
          log('  Removing all buttons (no link/copy buttons)');
          await _botRepository.removeKeyboard(
            chatId: chatId,
            messageId: context.lastMessages.last.messageId,
          );
        }
      }
      // Очищаем lastMessages чтобы новый экран отправил новое сообщение
      context.lastMessages.clear();
    }
    // Если НЕ keepMessages - НЕ удаляем и НЕ очищаем!
    // _sendOrEditMessage() сам решит что делать (редактировать или удалить+отправить)

    // Вызвать onExit для текущего экрана
    if (context.currentRoute != null) {
      try {
        final currentScreen = _routeRegistry.createScreen(
          context.currentRoute!,
          context,
        );
        await currentScreen.onExit(context);
      } catch (e) {
        log('Warning: onExit failed for ${context.currentRoute}: $e');
      }
    }

    // Проверяем, является ли целевой роут стартовым или домашним
    final startRoute = _routeRegistry.startRoute;
    final homeRoute = _routeRegistry.homeRoute;
    final isRootRoute = routeId == startRoute || routeId == homeRoute;

    if (isRootRoute) {
      // Для корневых роутов (start/home) очищаем стек и добавляем только сам роут
      context.navigationStack.clear();
      context.navigationStack.add(routeId);
      final routeType = routeId == startRoute ? 'start' : 'home';
      log(
        '🏠 Navigating to $routeType route - navigation stack cleared and set to [$routeId]',
      );
    } else {
      // Для обычных роутов - дедупликация
      final shouldAddToStack =
          context.currentRoute != routeId || _paramsChanged(context, params);

      if (shouldAddToStack) {
        // Добавить новый маршрут в стек
        context.navigationStack.add(routeId);
        log(
          '📍 Added route to stack: $routeId (stack size: ${context.navigationStack.length})',
        );
      } else {
        log('♻️ Same route with same params, not adding to stack: $routeId');
      }
    }

    // Установить параметры в контекст
    if (params != null) {
      params.forEach((key, value) {
        context.setData(key, value);
      });
    }

    // Трекинг навигации — fire-and-forget, не блокирует переход
    // Админы не учитываются в аналитике
    if (!context.isAdmin) {
      _analyticsService
          ?.trackNavigation(
            userId: userId,
            routeId: routeId,
            previousRoute: previousRoute,
          )
          .ignore();
    }

    // Создать новый экран
    final screen = _routeRegistry.createScreen(routeId, context);

    // Вызвать onEnter
    await screen.onEnter(context);

    // Получить данные для отображения
    final message = await screen.getMessage(context);
    final images = (await screen.getImages(
      context,
    )).where((img) => img.isNotEmpty).toList();
    final buttons = await screen.getButtons(context);

    // Отправить или редактировать сообщение
    final sentMessages = await _sendOrEditMessage(
      context: context,
      chatId: chatId,
      screen: screen,
      message: message,
      images: images,
      buttons: buttons,
    );

    // Сохранить структуру сообщений в контексте
    context.lastMessages = sentMessages;

    // Сохранить контекст
    await _sessionRepository.saveContext(userId, context);
  }

  /// Вернуться на предыдущий экран
  ///
  /// Если стек пуст или содержит только один элемент, переходит на home роут
  ///
  /// Параметры:
  /// - [userId]: ID пользователя
  /// - [chatId]: ID чата
  Future<void> goBack({required int userId, required int chatId}) async {
    // Показать индикатор "typing"
    await _botRepository.sendChatAction(chatId: chatId, action: 'typing');

    // Получить контекст
    var context = await _sessionRepository.getContext(userId);

    // Если стек пуст или содержит только один элемент - переходим на home роут
    if (!context.canGoBack) {
      log(
        'Info: Navigation stack is empty or has only one item, navigating to home route',
      );
      final homeRoute = _routeRegistry.homeRoute;
      await navigateTo(userId: userId, chatId: chatId, routeId: homeRoute);
      return;
    }

    // Обработка текущих сообщений - проверяем настройку текущего экрана
    bool shouldKeepMessages = false;
    if (context.currentRoute != null) {
      try {
        final currentScreen = _routeRegistry.createScreen(
          context.currentRoute!,
          context,
        );
        shouldKeepMessages = currentScreen.keepMessageOnExit(context);
        log(
          '🔍 [goBack] Screen ${context.currentRoute}: keepMessageOnExit = $shouldKeepMessages',
        );
      } catch (e) {
        log(
          'Warning: Failed to check keepMessageOnExit for ${context.currentRoute}: $e',
        );
      }
    }

    if (shouldKeepMessages) {
      log(
        '💾 [goBack] Keeping messages from ${context.currentRoute}, removing keyboard only',
      );
      // Убираем ТОЛЬКО интерактивные кнопки (не ссылки и не копирование)
      if (context.lastMessages.isNotEmpty) {
        final currentScreen = _routeRegistry.createScreen(
          context.currentRoute!,
          context,
        );
        final buttons = await currentScreen.getButtons(context);

        // Фильтруем кнопки - оставляем только Link и Copy
        final nonInteractiveButtons = _filterNonInteractiveButtons(buttons);

        if (nonInteractiveButtons.isNotEmpty) {
          // Есть Link/Copy кнопки - редактируем клавиатуру, оставляя их
          log(
            '  Keeping ${_countButtons(nonInteractiveButtons)} link/copy buttons',
          );

          try {
            // Определяем тип последнего сообщения
            final lastMessage = context.lastMessages.last;

            if (lastMessage.type == MessageType.photo) {
              // Фото с caption - используем editMessageMedia
              final imageUrl = lastMessage.content!;
              await _botRepository.editMessageMedia(
                chatId: chatId,
                messageId: lastMessage.messageId,
                imageUrl: imageUrl,
                caption: await currentScreen.getMessage(context),
                keyboard: nonInteractiveButtons,
                parseMode: currentScreen.parseMode,
              );
            } else {
              // Текстовое сообщение - используем editMessage
              await _botRepository.editMessage(
                chatId: chatId,
                messageId: lastMessage.messageId,
                text: await currentScreen.getMessage(context),
                keyboard: nonInteractiveButtons,
                parseMode: currentScreen.parseMode,
              );
            }
          } catch (e) {
            log('  Warning: Failed to edit message: $e');
            // Игнорируем ошибку - сообщение останется с исходными кнопками
          }
        } else {
          // Нет Link/Copy кнопок - полностью удаляем клавиатуру
          log('  Removing all buttons (no link/copy buttons)');
          await _botRepository.removeKeyboard(
            chatId: chatId,
            messageId: context.lastMessages.last.messageId,
          );
        }
      }
      // Очищаем lastMessages чтобы предыдущий экран отправил новое сообщение
      context.lastMessages.clear();
    }
    // Если НЕ keepMessages - НЕ удаляем и НЕ очищаем!
    // _sendOrEditMessage() сам решит что делать (редактировать или удалить+отправить)

    // Вызвать onExit для текущего экрана
    if (context.currentRoute != null) {
      try {
        final currentScreen = _routeRegistry.createScreen(
          context.currentRoute!,
          context,
        );
        await currentScreen.onExit(context);
      } catch (e) {
        log('Warning: onExit failed for ${context.currentRoute}: $e');
      }
    }

    // Удалить текущий маршрут из стека
    context.navigationStack.removeLast();

    // Получить предыдущий маршрут
    final previousRoute = context.currentRoute!;

    // Создать экран предыдущего маршрута
    final screen = _routeRegistry.createScreen(previousRoute, context);

    // Вызвать onEnter
    await screen.onEnter(context);

    // Получить данные для отображения
    final message = await screen.getMessage(context);
    final images = await screen.getImages(context);
    final buttons = await screen.getButtons(context);

    // Отправить или редактировать сообщение
    final sentMessages = await _sendOrEditMessage(
      context: context,
      chatId: chatId,
      screen: screen,
      message: message,
      images: images,
      buttons: buttons,
    );

    // Сохранить структуру сообщений в контексте
    context.lastMessages = sentMessages;

    // Сохранить контекст
    await _sessionRepository.saveContext(userId, context);
  }

  /// Обновить текущий экран с новыми данными
  ///
  /// Полезно после изменения данных в контексте (например, через CustomAction)
  /// Параметры:
  /// - [userId]: ID пользователя
  /// - [chatId]: ID чата
  /// - [params]: Опциональные дополнительные параметры для обновления контекста
  Future<void> refreshCurrentScreen({
    required int userId,
    required int chatId,
    Map<String, dynamic>? params,
  }) async {
    // Показать индикатор "typing"
    await _botRepository.sendChatAction(chatId: chatId, action: 'typing');

    // Получить контекст
    var context = await _sessionRepository.getContext(userId);

    // Проверить наличие текущего экрана
    if (context.currentRoute == null) {
      log('Warning: No current route to refresh');
      return;
    }

    // Обновить параметры если переданы
    if (params != null) {
      params.forEach((key, value) {
        context.setData(key, value);
      });
    }

    // Создать текущий экран
    final screen = _routeRegistry.createScreen(context.currentRoute!, context);

    // Получить обновленные данные для отображения
    final message = await screen.getMessage(context);
    final images = (await screen.getImages(
      context,
    )).where((img) => img.isNotEmpty).toList();
    final buttons = await screen.getButtons(context);

    // Определяем режим обновления
    final refreshMode = _determineRefreshMode(context, images);

    log('🔍 Refresh mode: $refreshMode');
    log(
      '   Current: images=${images.length}, lastMessages=${context.lastMessages.length}',
    );
    log(
      '   Last structure: ${context.lastMessages.map((m) => m.type).join(", ")}',
    );

    // Выполняем обновление согласно определенному режиму
    switch (refreshMode) {
      case _RefreshMode.noChange:
        log('ℹ️ No changes detected, skipping update');
        break;

      case _RefreshMode.editTextOnly:
        try {
          await _botRepository.editMessage(
            chatId: chatId,
            messageId: context.lastMessages.last.messageId,
            text: message,
            keyboard: buttons.isNotEmpty ? buttons : null,
            parseMode: screen.parseMode,
          );
          log('✓ Screen refreshed via editMessage (text only)');
        } catch (e) {
          final errorString = e.toString();
          if (errorString.contains('message is not modified') ||
              errorString.contains('exactly the same')) {
            log('ℹ️ Message content identical, no update needed');
          } else {
            log('Warning: Failed to edit message: $e');
            await _refreshViaSendMessage(context, chatId, screen);
          }
        }
        break;

      case _RefreshMode.editMedia:
        await _refreshViaEditMedia(
          context,
          chatId,
          screen,
          images,
          message,
          buttons,
        );
        break;

      case _RefreshMode.resend:
        log('⚠️ Resending all messages');
        await _refreshViaSendMessage(context, chatId, screen);
        break;
    }

    // Сохранить обновленный контекст
    await _sessionRepository.saveContext(userId, context);
  }

  /// Вспомогательный метод: обновление через editMessageMedia (без анимации удаления)
  Future<void> _refreshViaEditMedia(
    NavigationContext context,
    int chatId,
    ScreenState screen,
    List<String> newImages,
    String message,
    List<List<KeyboardButton>> buttons,
  ) async {
    final lastMessages = context.lastMessages;

    // Проверяем структуру: [photo, text] или [mediaGroup, text]
    if (lastMessages.length == 2 &&
        lastMessages.first.type == MessageType.photo &&
        lastMessages.last.type == MessageType.text &&
        newImages.length == 1) {
      // Одно изображение: [photo_msg, text_msg]

      // Сравниваем URL картинки
      final oldImageUrl = lastMessages.first.content;
      final newImageUrl = newImages.first;
      final imageUrlChanged = oldImageUrl != newImageUrl;

      // СНАЧАЛА обновляем текст (чтобы избежать визуального рассинхрона)
      bool textUpdateFailed = false;
      try {
        await _botRepository.editMessage(
          chatId: chatId,
          messageId: lastMessages.last.messageId,
          text: message,
          keyboard: buttons.isNotEmpty ? buttons : null,
          parseMode: screen.parseMode,
        );
      } catch (e) {
        final errorString = e.toString();
        if (errorString.contains('message is not modified') ||
            errorString.contains('exactly the same')) {
          log('ℹ️ Text identical, no update needed');
        } else {
          log('Warning: Failed to edit text: $e');
          textUpdateFailed = true;
        }
      }

      // ПОТОМ обновляем картинку (только если URL изменился)
      bool mediaUpdateFailed = false;
      if (imageUrlChanged) {
        try {
          await _botRepository.editMessageMedia(
            chatId: chatId,
            messageId: lastMessages.first.messageId,
            imageUrl: newImageUrl,
          );
          // Обновляем content в lastMessages
          context.lastMessages[0] = SentMessage.photo(
            messageId: lastMessages.first.messageId,
            imageUrl: newImageUrl,
          );
          log('✓ Media updated');
        } catch (e) {
          final errorString = e.toString();
          if (errorString.contains('message is not modified') ||
              errorString.contains('exactly the same')) {
            log('ℹ️ Media identical (same file), no update needed');
            // Всё равно обновляем content, т.к. URL изменился
            context.lastMessages[0] = SentMessage.photo(
              messageId: lastMessages.first.messageId,
              imageUrl: newImageUrl,
            );
          } else {
            log('Warning: Failed to edit media: $e');
            mediaUpdateFailed = true;
          }
        }
      } else {
        log('ℹ️ Media URL unchanged, skipping update');
      }

      // Пересоздаём только если обе операции упали с реальной ошибкой
      if (mediaUpdateFailed || textUpdateFailed) {
        log('⚠️ Failed to edit messages, resending all');
        await _refreshViaSendMessage(context, chatId, screen);
      } else {
        log('✓ Screen refreshed via editMessageMedia (no animation)');
      }
    } else if (lastMessages.length == 2 &&
        lastMessages.first.type == MessageType.photo &&
        lastMessages.last.type == MessageType.text &&
        newImages.isEmpty) {
      // Картинка была, но теперь её нет - удаляем photo, обновляем text
      log('🗑️ Removing image, updating text only');
      await _botRepository.deleteMessages(
        chatId: chatId,
        messageIds: [lastMessages.first.messageId],
      );

      try {
        await _botRepository.editMessage(
          chatId: chatId,
          messageId: lastMessages.last.messageId,
          text: message,
          keyboard: buttons.isNotEmpty ? buttons : null,
          parseMode: screen.parseMode,
        );

        // Обновляем lastMessages - удаляем photo
        context.lastMessages.removeAt(0);
        log('✓ Image removed, text updated');
      } catch (e) {
        log('Warning: Failed to update text after removing image: $e');
        await _refreshViaSendMessage(context, chatId, screen);
      }
    } else if (lastMessages.length == 1 &&
        lastMessages.first.type == MessageType.text &&
        newImages.isNotEmpty) {
      // Картинки не было, но теперь появилась - пересоздаём
      log('🖼️ Adding image, resending all messages');
      await _refreshViaSendMessage(context, chatId, screen);
    } else {
      // Медиа-группа или другой сложный случай - пока не поддерживается, пересылаем
      log('⚠️ Complex update scenario, resending all messages');
      await _refreshViaSendMessage(context, chatId, screen);
    }
  }

  /// Вспомогательный метод: обновление через удаление и отправку нового сообщения
  Future<void> _refreshViaSendMessage(
    NavigationContext context,
    int chatId,
    ScreenState screen,
  ) async {
    // Удалить старые сообщения (батч-удаление)
    if (context.lastMessages.isNotEmpty) {
      // Собираем все ID (основные + дополнительные из медиа-групп)
      final messageIds = <int>[];
      for (final msg in context.lastMessages) {
        messageIds.addAll(msg.allMessageIds);
      }

      try {
        await _botRepository.deleteMessages(
          chatId: chatId,
          messageIds: messageIds,
        );
      } catch (e) {
        log('Warning: Failed to delete old messages: $e');
      }
    }

    // Получить данные
    final message = await screen.getMessage(context);
    final images = await screen.getImages(context);
    final filteredImages = <String>[];
    for (final img in images) {
      if (img.isNotEmpty) {
        filteredImages.add(img);
      }
    }
    final buttons = await screen.getButtons(context);

    // Отправить новое сообщение
    final sentMessages = await _botRepository.sendMessage(
      chatId: chatId,
      text: message,
      images: filteredImages,
      keyboard: buttons.isNotEmpty ? buttons : null,
      parseMode: screen.parseMode,
      imageSendStrategy: screen.imageSendStrategy,
    );

    // Обновить структуру сообщений в контексте
    context.lastMessages = sentMessages;
  }

  /// Очистить сессию пользователя
  Future<void> clearSession(int userId) async {
    await _sessionRepository.clearContext(userId);
  }

  /// Проверить, изменились ли параметры навигации
  ///
  /// Возвращает true, если новые параметры отличаются от текущих в контексте
  bool _paramsChanged(
    NavigationContext context,
    Map<String, dynamic>? newParams,
  ) {
    if (newParams == null || newParams.isEmpty) {
      return false; // Нет новых параметров - считаем что не изменились
    }

    // Проверяем каждый ключ из новых параметров
    for (final entry in newParams.entries) {
      final currentValue = context.data[entry.key];
      if (currentValue != entry.value) {
        return true; // Параметр изменился
      }
    }

    return false; // Все параметры совпадают
  }

  /// Определить режим обновления экрана
  ///
  /// Последовательно проверяет условия от самого мягкого (noChange) до самого жесткого (resend)
  _RefreshMode _determineRefreshMode(
    NavigationContext context,
    List<String> newImages,
  ) {
    final lastMessages = context.lastMessages;

    // Проверка 1: Есть ли вообще что обновлять?
    if (lastMessages.isEmpty) {
      return _RefreshMode.resend; // Первая отправка - технически resend
    }

    // Проверка 2: Определяем текущую и предыдущую структуру
    final hasImages = newImages.isNotEmpty;
    final hadImages = lastMessages.any(
      (m) => m.type == MessageType.photo || m.type == MessageType.mediaGroup,
    );

    // Проверка 3: Изменилось ли наличие изображений?
    if (hasImages != hadImages) {
      // Изображения появились или исчезли
      return _RefreshMode.resend;
    }

    // Проверка 4: Нет изображений ни сейчас, ни раньше
    if (!hasImages && !hadImages) {
      // Только текст
      return _RefreshMode.editTextOnly;
    }

    // С этого момента мы знаем что hasImages=true и hadImages=true

    // Проверка 5: Собираем старые изображения из lastMessages
    final oldImages = <String>[];
    for (final msg in lastMessages) {
      if (msg.type == MessageType.photo && msg.content != null) {
        oldImages.add(msg.content!);
      } else if (msg.type == MessageType.mediaGroup) {
        oldImages.addAll(msg.imageUrls);
      }
    }

    // Проверка 6: Изменилось ли количество изображений?
    if (oldImages.length != newImages.length) {
      return _RefreshMode.resend;
    }

    // Проверка 7: Изменились ли сами изображения (URL)?
    bool imagesChanged = false;
    for (var i = 0; i < newImages.length; i++) {
      if (oldImages[i] != newImages[i]) {
        imagesChanged = true;
        break;
      }
    }

    // Проверка 8: Финальное решение
    if (imagesChanged) {
      return _RefreshMode.editMedia;
    } else {
      return _RefreshMode.editTextOnly;
    }
  }

  /// Отправить или редактировать сообщение (используется при навигации)
  ///
  /// Максимально использует редактирование вместо удаления+отправки для плавного UX.
  /// Поддерживаемые трансформации:
  /// - [text] → [text] ✅ editMessage
  /// - [photo_with_caption] → [photo_with_caption] ✅ editMessageMedia
  /// - [photo, text] → [photo, text] ✅ editMessageMedia + editMessage
  /// - [photo, text] → [text] ✅ deleteMessages(photo) + editMessage(text)
  /// - [text] → [photo, text] ❌ Fallback: delete + send (нельзя добавить фото к тексту)
  /// - [photo_with_caption] → [text] ❌ Fallback: delete + send (сложная трансформация)
  /// - [mediaGroup] → любое ❌ Fallback: delete + send (медиа-группы не поддерживают редактирование)
  Future<List<SentMessage>> _sendOrEditMessage({
    required NavigationContext context,
    required int chatId,
    required ScreenState screen,
    required String message,
    required List<String> images,
    required List<List<KeyboardButton>> buttons,
  }) async {
    final lastMessages = context.lastMessages;

    // Видео-экран: рендерим как свежее видео-сообщение (удаляем прошлые
    // сообщения + sendVideo с caption и клавиатурой). Без in-place
    // редактирования — video отправляется заново при каждом входе.
    final video = await screen.getVideo(context);
    if (video != null && video.isNotEmpty) {
      if (lastMessages.isNotEmpty) {
        await _botRepository.deleteMessages(
          chatId: chatId,
          messageIds: lastMessages.expand((m) => m.allMessageIds).toList(),
        );
      }
      final sent = await _botRepository.sendVideo(
        chatId: chatId,
        video: video,
        caption: message,
        keyboard: buttons.isNotEmpty ? buttons : null,
        parseMode: screen.parseMode,
      );
      return [sent];
    }

    // Фильтруем пустые URL из images (важно для правильного определения структуры!)
    final validImages = images.where((url) => url.isNotEmpty).toList();

    // Если нет предыдущих сообщений - просто отправляем новое
    if (lastMessages.isEmpty) {
      log('📤 No previous messages, sending new');
      return await _botRepository.sendMessage(
        chatId: chatId,
        text: message,
        images: validImages,
        keyboard: buttons.isNotEmpty ? buttons : null,
        parseMode: screen.parseMode,
        imageSendStrategy: screen.imageSendStrategy,
      );
    }

    // Определяем структуру: сколько сообщений и какие типы
    final hadOneMessage = lastMessages.length == 1;
    final hadTwoMessages = lastMessages.length == 2;
    final hadTextOnly =
        hadOneMessage && lastMessages.first.type == MessageType.text;
    final hadPhotoWithCaption =
        hadOneMessage && lastMessages.first.type == MessageType.photo;
    final hadSeparatePhoto =
        hadTwoMessages &&
        lastMessages.first.type == MessageType.photo &&
        lastMessages.last.type == MessageType.text;

    // Определяем что будем отправлять (используем validImages!)
    final willHaveImages = validImages.isNotEmpty;
    final willHaveOneImage = validImages.length == 1;

    // === СЛУЧАЙ 1: [text] → [text] ✅ ===
    if (!willHaveImages && hadTextOnly) {
      log('✏️ Transformation: [text] → [text]');
      try {
        await _botRepository.editMessage(
          chatId: chatId,
          messageId: lastMessages.first.messageId,
          text: message,
          keyboard: buttons.isNotEmpty ? buttons : null,
          parseMode: screen.parseMode,
        );
        log('✓ Edited text message');

        return [
          SentMessage.text(
            messageId: lastMessages.first.messageId,
            text: message,
          ),
        ];
      } catch (e) {
        log('⚠️ Edit failed: $e, falling back to delete + send');
        return await _sendMessageAfterDelete(
          context: context,
          chatId: chatId,
          screen: screen,
          message: message,
          images: validImages,
          buttons: buttons,
        );
      }
    }

    // === СЛУЧАЙ 2: [photo_with_caption] → [photo_with_caption] ✅ ===
    if (willHaveOneImage && hadPhotoWithCaption) {
      final strategy = screen.imageSendStrategy;
      final willUseCombined =
          strategy == ImageSendStrategy.combined ||
          (strategy == ImageSendStrategy.auto && willHaveOneImage);

      if (willUseCombined) {
        log('✏️ Transformation: [photo_with_caption] → [photo_with_caption]');
        try {
          final photoMessage = lastMessages.first;
          final oldImageUrl = photoMessage.content;
          final newImageUrl = validImages.first;

          if (oldImageUrl != newImageUrl) {
            await _botRepository.editMessageMedia(
              chatId: chatId,
              messageId: photoMessage.messageId,
              imageUrl: newImageUrl,
              caption: message,
              keyboard: buttons.isNotEmpty ? buttons : null,
              parseMode: screen.parseMode,
            );
            log('✓ Edited photo with caption (media changed)');
          } else {
            await _botRepository.editMessage(
              chatId: chatId,
              messageId: photoMessage.messageId,
              text: message,
              keyboard: buttons.isNotEmpty ? buttons : null,
              parseMode: screen.parseMode,
            );
            log('✓ Edited photo caption and keyboard (media unchanged)');
          }

          return [
            SentMessage.photo(
              messageId: photoMessage.messageId,
              imageUrl: newImageUrl,
            ),
          ];
        } catch (e) {
          log('⚠️ Edit failed: $e, falling back to delete + send');
          return await _sendMessageAfterDelete(
            context: context,
            chatId: chatId,
            screen: screen,
            message: message,
            images: validImages,
            buttons: buttons,
          );
        }
      }
    }

    // === СЛУЧАЙ 3: [photo, text] → [photo, text] ✅ ===
    if (willHaveOneImage && hadSeparatePhoto) {
      final strategy = screen.imageSendStrategy;
      if (strategy == ImageSendStrategy.separateMessage) {
        log('✏️ Transformation: [photo, text] → [photo, text]');
        try {
          final photoMessage = lastMessages.first;
          final textMessage = lastMessages.last;
          final oldImageUrl = photoMessage.content;
          final newImageUrl = validImages.first;

          // Сначала обновляем фото (если URL изменился)
          if (oldImageUrl != newImageUrl) {
            await _botRepository.editMessageMedia(
              chatId: chatId,
              messageId: photoMessage.messageId,
              imageUrl: newImageUrl,
            );
            log('✓ Edited separate photo');
          } else {
            log('ℹ️ Photo URL unchanged');
          }

          // Затем обновляем текст
          await _botRepository.editMessage(
            chatId: chatId,
            messageId: textMessage.messageId,
            text: message,
            keyboard: buttons.isNotEmpty ? buttons : null,
            parseMode: screen.parseMode,
          );
          log('✓ Edited text message');

          return [
            SentMessage.photo(
              messageId: photoMessage.messageId,
              imageUrl: newImageUrl,
            ),
            SentMessage.text(messageId: textMessage.messageId, text: message),
          ];
        } catch (e) {
          log('⚠️ Edit failed: $e, falling back to delete + send');
          return await _sendMessageAfterDelete(
            context: context,
            chatId: chatId,
            screen: screen,
            message: message,
            images: validImages,
            buttons: buttons,
          );
        }
      }
    }

    // === СЛУЧАЙ 4: [photo, text] → [text] ✅ ===
    // Удаляем фото, редактируем текст
    if (!willHaveImages && hadSeparatePhoto) {
      log('✏️ Transformation: [photo, text] → [text]');
      try {
        final photoMessage = lastMessages.first;
        final textMessage = lastMessages.last;

        // Удаляем фото
        await _botRepository.deleteMessages(
          chatId: chatId,
          messageIds: [photoMessage.messageId],
        );
        log('✓ Deleted photo message');

        // Редактируем текст
        await _botRepository.editMessage(
          chatId: chatId,
          messageId: textMessage.messageId,
          text: message,
          keyboard: buttons.isNotEmpty ? buttons : null,
          parseMode: screen.parseMode,
        );
        log('✓ Edited text message');

        return [
          SentMessage.text(messageId: textMessage.messageId, text: message),
        ];
      } catch (e) {
        log('⚠️ Edit failed: $e, falling back to delete + send');
        return await _sendMessageAfterDelete(
          context: context,
          chatId: chatId,
          screen: screen,
          message: message,
          images: validImages,
          buttons: buttons,
        );
      }
    }

    // === FALLBACK: Несовместимые структуры - удаление + отправка ===
    log(
      '⚠️ Incompatible structure, falling back to delete + send\n'
      '   Last: ${lastMessages.map((m) => m.type).join(", ")}\n'
      '   New: images=$willHaveImages (count=${validImages.length}), strategy=${screen.imageSendStrategy}',
    );
    return await _sendMessageAfterDelete(
      context: context,
      chatId: chatId,
      screen: screen,
      message: message,
      images: images,
      buttons: buttons,
    );
  }

  /// Удалить старые сообщения и отправить новые
  Future<List<SentMessage>> _sendMessageAfterDelete({
    required NavigationContext context,
    required int chatId,
    required ScreenState screen,
    required String message,
    required List<String> images,
    required List<List<KeyboardButton>> buttons,
  }) async {
    // Удалить старые сообщения
    if (context.lastMessages.isNotEmpty) {
      final messageIds = <int>[];
      for (final msg in context.lastMessages) {
        messageIds.addAll(msg.allMessageIds);
      }

      try {
        await _botRepository.deleteMessages(
          chatId: chatId,
          messageIds: messageIds,
        );
      } catch (e) {
        log('Warning: Failed to delete messages: $e');
      }
    }

    // Отправить новое сообщение
    return await _botRepository.sendMessage(
      chatId: chatId,
      text: message,
      images: images,
      keyboard: buttons.isNotEmpty ? buttons : null,
      parseMode: screen.parseMode,
      imageSendStrategy: screen.imageSendStrategy,
    );
  }

  /// Фильтровать кнопки, оставляя только Link и Copy (не требующие обработки бота)
  ///
  /// Возвращает новую структуру кнопок без интерактивных кнопок
  /// (NavigationButton, ActionButton, BackButton удаляются)
  List<List<KeyboardButton>> _filterNonInteractiveButtons(
    List<List<KeyboardButton>> buttonRows,
  ) {
    final filtered = <List<KeyboardButton>>[];

    for (final row in buttonRows) {
      final filteredRow = <KeyboardButton>[];
      for (final button in row) {
        // Оставляем только Link и Copy кнопки
        if (button is LinkButton || button is CopyButton) {
          filteredRow.add(button);
        }
      }
      // Добавляем строку только если в ней есть кнопки
      if (filteredRow.isNotEmpty) {
        filtered.add(filteredRow);
      }
    }

    return filtered;
  }

  /// Подсчитать общее количество кнопок во всех строках
  int _countButtons(List<List<KeyboardButton>> buttonRows) {
    int count = 0;
    for (final row in buttonRows) {
      count += row.length;
    }
    return count;
  }
}
