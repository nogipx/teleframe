import 'navigation_context.dart';

/// Результат выполнения CustomAction
sealed class HandlerResult {
  const HandlerResult();

  /// Обновить текущий экран (если refreshScreen: true)
  const factory HandlerResult.refresh() = RefreshResult;

  /// Перейти на указанный маршрут
  const factory HandlerResult.navigate(
    String routeId, {
    Map<String, dynamic>? params,
  }) = NavigateResult;

  /// Не делать ничего (полезно с refreshScreen: false)
  const factory HandlerResult.none() = NoneResult;

  /// Отправить информационное сообщение пользователю
  ///
  /// Сообщение не трекается системой навигации и остаётся в чате
  const factory HandlerResult.message(
    String text, {
    List<String> images,
    List<MessageLink> links,
  }) = MessageResult;

  /// Показать всплывающее уведомление (alert)
  const factory HandlerResult.alert(String text) = AlertResult;
}

/// Результат: обновить текущий экран
class RefreshResult extends HandlerResult {
  const RefreshResult();
}

/// Результат: перейти на маршрут
class NavigateResult extends HandlerResult {
  final String routeId;
  final Map<String, dynamic>? params;

  const NavigateResult(this.routeId, {this.params});
}

/// Результат: не делать ничего
class NoneResult extends HandlerResult {
  const NoneResult();
}

/// Результат: отправить информационное сообщение
///
/// Сообщение не трекается системой навигации и остаётся в чате
class MessageResult extends HandlerResult {
  final String text;
  final List<String> images;
  final List<MessageLink> links;

  const MessageResult(
    this.text, {
    this.images = const [],
    this.links = const [],
  });
}

/// Ссылка для отображения в сообщении
class MessageLink {
  final String text;
  final String url;

  const MessageLink({
    required this.text,
    required this.url,
  });
}

/// Результат: показать всплывающее уведомление (alert)
class AlertResult extends HandlerResult {
  final String text;

  const AlertResult(this.text);
}

/// Представление кнопки клавиатуры бота
class KeyboardButton {
  /// Текст, отображаемый на кнопке
  final String text;

  /// Данные для callback query (идентификатор действия)
  final String callbackData;

  /// Действие, выполняемое при нажатии кнопки
  final ButtonAction action;

  const KeyboardButton({
    required this.text,
    required this.callbackData,
    this.action = const EmptyAction(),
  });
}

/// Базовый класс для типов действий кнопок
sealed class ButtonAction {
  const ButtonAction();
}

class EmptyAction extends ButtonAction {
  const EmptyAction();
}

/// Действие навигации на указанный маршрут
class NavigateAction extends ButtonAction {
  /// ID целевого маршрута
  final String targetRoute;

  /// Параметры для передачи в контекст при навигации
  final Map<String, dynamic>? params;

  const NavigateAction(this.targetRoute, {this.params});
}

/// Действие возврата на предыдущий экран
class BackAction extends ButtonAction {
  const BackAction();
}

/// Действие перехода на домашний экран (home route)
class HomeAction extends ButtonAction {
  const HomeAction();
}

/// Пользовательское действие с произвольной логикой
class CustomAction extends ButtonAction {
  /// Функция-обработчик, выполняемая при нажатии кнопки
  ///
  /// Может вернуть:
  /// - `null` - обновить текущий экран (если refreshScreen: true) или не делать ничего
  /// - `HandlerResult.refresh()` - явно обновить экран
  /// - `HandlerResult.navigate('route')` - перейти на указанный маршрут
  /// - `HandlerResult.none()` - не делать ничего
  final Future<HandlerResult?> Function(NavigationContext context) handler;

  const CustomAction(this.handler);
}
