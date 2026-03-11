import 'sent_message.dart';

/// Контекст навигации пользователя, содержащий информацию о сессии,
/// истории навигации и данных между экранами.
class NavigationContext {
  /// ID пользователя Telegram
  final int userId;

  /// ID чата Telegram
  final int chatId;

  /// Стек навигации (история переходов между экранами)
  final List<String> navigationStack;

  /// Хранилище данных для передачи между экранами
  final Map<String, dynamic> data;

  /// Структура последних отправленных сообщений
  ///
  /// Содержит полную информацию о каждом отправленном сообщении:
  /// тип, ID, содержимое. Используется для умного обновления при refresh.
  List<SentMessage> lastMessages;

  NavigationContext({
    required this.userId,
    required this.chatId,
    List<String>? navigationStack,
    Map<String, dynamic>? data,
    List<SentMessage>? lastMessages,
  }) : navigationStack = navigationStack ?? [],
       data = data ?? {},
       lastMessages = lastMessages ?? [];

  /// Получить текущий маршрут (последний в стеке)
  String? get currentRoute =>
      navigationStack.isNotEmpty ? navigationStack.last : null;

  /// Получить предыдущий маршрут
  String? get previousRoute => navigationStack.length > 1
      ? navigationStack[navigationStack.length - 2]
      : null;

  /// Проверить, можно ли вернуться назад
  bool get canGoBack => navigationStack.length > 1;

  /// Получить данные по ключу с приведением типа
  T? getData<T>(String key) {
    final value = data[key];
    return value is T ? value : null;
  }

  /// Установить данные по ключу
  void setData(String key, dynamic value) {
    data[key] = value;
  }

  /// Удалить данные по ключу
  void removeData(String key) {
    data.remove(key);
  }

  /// Получить ID всех последних сообщений (включая дополнительные из медиа-групп)
  List<int> get lastMessageIds {
    final ids = <int>[];
    for (final msg in lastMessages) {
      ids.addAll(msg.allMessageIds);
    }
    return ids;
  }

  /// Создать копию контекста с новыми значениями
  NavigationContext copyWith({
    int? userId,
    int? chatId,
    List<String>? navigationStack,
    Map<String, dynamic>? data,
    List<SentMessage>? lastMessages,
    bool clearLastMessages = false,
  }) {
    return NavigationContext(
      userId: userId ?? this.userId,
      chatId: chatId ?? this.chatId,
      navigationStack:
          navigationStack ?? List<String>.from(this.navigationStack),
      data: data ?? Map<String, dynamic>.from(this.data),
      lastMessages: clearLastMessages
          ? []
          : (lastMessages ?? List<SentMessage>.from(this.lastMessages)),
    );
  }
}
