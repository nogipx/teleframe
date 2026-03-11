import '../../../domain/entities/image_send_strategy.dart';
import '../../../domain/entities/keyboard_button.dart';
import '../../../domain/entities/navigation_context.dart';
import '../base/base_screen.dart';

/// Экран детального просмотра с навигацией между элементами
abstract class NavigableDetailScreen<T> extends BaseScreen {
  Future<List<T>> getAllItems(NavigationContext context);
  String getItemId(T item);

  /// Ключ параметра для хранения ID текущего элемента в context.data
  ///
  /// ВАЖНО: Это навигационный параметр, который передаётся при переходе на экран.
  /// Используйте уникальный ключ для вашего типа данных (например, 'product_id', 'pet_id').
  /// По умолчанию 'item_id' - переопределите для специфичных экранов.
  ///
  /// Этот ключ НЕ очищается при выходе с экрана, т.к. это часть навигации.
  String get currentItemIdKey => 'item_id';

  @override
  ImageSendStrategy get imageSendStrategy => ImageSendStrategy.separateMessage;

  /// Получить ID текущего элемента из context
  String getCurrentItemId(NavigationContext context) {
    return context.getData<String>(currentItemIdKey) ?? '';
  }

  /// Установить ID текущего элемента в context
  void setCurrentItemId(NavigationContext context, String itemId) {
    context.setData(currentItemIdKey, itemId);
  }

  Future<T?> getCurrentItem(NavigationContext context) async {
    final currentId = getCurrentItemId(context);
    final items = await getAllItems(context);
    try {
      return items.firstWhere((item) => getItemId(item) == currentId);
    } catch (e) {
      return null;
    }
  }

  /// Получить индекс текущего элемента в списке (0-based индекс)
  ///
  /// Используйте этот метод в наследниках для получения позиции текущего элемента.
  /// Возвращает -1, если элемент не найден.
  /// Для отображения пользователю добавьте +1 к результату.
  Future<int> getCurrentIndex(NavigationContext context) async {
    final currentId = getCurrentItemId(context);
    final items = await getAllItems(context);
    return items.indexWhere((item) => getItemId(item) == currentId);
  }

  /// Получить общее количество элементов
  ///
  /// Используйте этот метод в наследниках для получения общего количества элементов.
  Future<int> getTotalItems(NavigationContext context) async {
    final items = await getAllItems(context);
    return items.length;
  }

  /// Показывать ли кнопки навигации между элементами
  bool get showItemNavigation => true;

  /// Текст кнопки "следующая страница"
  /// Переопределите для изменения текста
  String get nextButtonText => '➡️';

  /// Текст кнопки "предыдущая страница"
  /// Переопределите для изменения текста
  String get previousButtonText => '⬅️';

  /// Показывать ли счетчик элементов (напр. "2/10")
  bool get showItemCounter => true;

  Future<List<List<KeyboardButton>>> getNavigationButtons(
    NavigationContext context,
  ) async {
    if (!showItemNavigation) return [];

    final items = await getAllItems(context);
    final currentIndex = await getCurrentIndex(context);
    if (currentIndex == -1 || items.isEmpty) return [];

    final buttons = <KeyboardButton>[];
    final totalItems = items.length;

    if (currentIndex > 0) {
      buttons.add(
        KeyboardButton(
          text: showItemCounter
              ? '$previousButtonText $currentIndex/$totalItems'
              : previousButtonText,
          callbackData: 'action:detail_prev',
          action: CustomAction((context) async {
            final items = await getAllItems(context);
            final currentIndex = await getCurrentIndex(context);
            if (currentIndex > 0) {
              final prevItem = items[currentIndex - 1];
              setCurrentItemId(context, getItemId(prevItem));
            }
            return const HandlerResult.refresh();
          }),
        ),
      );
    }

    if (currentIndex < totalItems - 1) {
      buttons.add(
        KeyboardButton(
          text: showItemCounter
              ? '$nextButtonText ${currentIndex + 2}/$totalItems'
              : nextButtonText,
          callbackData: 'action:detail_next',
          action: CustomAction((context) async {
            final items = await getAllItems(context);
            final currentIndex = await getCurrentIndex(context);
            if (currentIndex < items.length - 1) {
              final nextItem = items[currentIndex + 1];
              setCurrentItemId(context, getItemId(nextItem));
            }
            return const HandlerResult.refresh();
          }),
        ),
      );
    }

    return buttons.isNotEmpty ? [buttons] : [];
  }

  /// Получить дополнительные кнопки после навигационных
  ///
  /// Переопределите для добавления своих кнопок (например, "Назад к списку")
  Future<List<List<KeyboardButton>>> getAdditionalButtons(
    NavigationContext context,
  ) async => [];

  @override
  Future<List<List<KeyboardButton>>> getButtons(
    NavigationContext context,
  ) async {
    final navigationButtons = await getNavigationButtons(context);
    final additionalButtons = await getAdditionalButtons(context);
    return [...navigationButtons, ...additionalButtons];
  }
}
