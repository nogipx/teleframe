import '../../../domain/entities/image_send_strategy.dart';
import '../../../domain/entities/keyboard_button.dart';
import '../../../domain/entities/navigation_context.dart';
import '../base/base_screen.dart';

/// Базовый класс для экранов с выбираемым списком элементов
///
/// При выборе элемента:
/// - Элемент скрывается из списка кнопок
/// - Сообщение обновляется через `getSelectedMessage()`
/// - Используется `HandlerResult.refresh()` для обновления экрана
///
/// Паттерн "выбор с превью" - показываем детали без перехода на другой экран
abstract class SelectableListScreen<T> extends BaseScreen {
  /// Ключ для хранения ID выбранного элемента в context.data
  String get selectedItemKey => '${routeId}_selected_item';

  @override
  ImageSendStrategy get imageSendStrategy => ImageSendStrategy.separateMessage;

  /// Получить все элементы для отображения
  Future<List<T>> getItems(NavigationContext context);

  /// Получить ID элемента
  String getItemId(T item);

  /// Получить отображаемый текст для кнопки элемента
  String getItemButtonText(T item);

  /// Получить сообщение для выбранного элемента
  /// Возвращает null, если нужно показать базовое сообщение из getMessage()
  Future<String?> getSelectedMessage(NavigationContext context, T selectedItem);

  /// Количество колонок в списке (по умолчанию 1 - вертикальный список)
  int get columnsCount => 1;

  /// Дополнительные кнопки, отображаемые после списка
  Future<List<List<KeyboardButton>>> getAdditionalButtons(
    NavigationContext context,
  ) async => [];

  @override
  Future<String> getMessage(NavigationContext context) async {
    final selectedId = context.getData<String>(selectedItemKey);

    if (selectedId != null) {
      final items = await getItems(context);
      final selectedItem = items.cast<T?>().firstWhere(
        (item) => item != null && getItemId(item) == selectedId,
        orElse: () => null,
      );

      if (selectedItem != null) {
        final selectedMessage = await getSelectedMessage(context, selectedItem);
        if (selectedMessage != null) {
          return selectedMessage;
        }
      }
    }

    // Если ничего не выбрано или выбранный элемент не найден - показываем базовое сообщение
    return getBaseMessage(context);
  }

  /// Базовое сообщение, когда ничего не выбрано
  Future<String> getBaseMessage(NavigationContext context);

  @override
  Future<List<List<KeyboardButton>>> getButtons(
    NavigationContext context,
  ) async {
    final items = await getItems(context);
    final selectedId = context.getData<String>(selectedItemKey);

    // Фильтруем выбранный элемент
    final availableItems = items
        .where((item) => getItemId(item) != selectedId)
        .toList();

    final listButtons = _buildListButtons(availableItems);
    final additionalButtons = await getAdditionalButtons(context);

    return [
      ...listButtons,
      ...additionalButtons,
    ];
  }

  /// Построить список кнопок из элементов
  List<List<KeyboardButton>> _buildListButtons(List<T> items) {
    final rows = <List<KeyboardButton>>[];

    for (var i = 0; i < items.length; i += columnsCount) {
      final row = <KeyboardButton>[];

      for (var j = 0; j < columnsCount && (i + j) < items.length; j++) {
        final item = items[i + j];
        row.add(_createButton(item));
      }

      rows.add(row);
    }

    return rows;
  }

  /// Создать кнопку для элемента
  KeyboardButton _createButton(T item) {
    final itemId = getItemId(item);

    return KeyboardButton(
      text: getItemButtonText(item),
      callbackData: 'action:select_$itemId',
      action: CustomAction((context) async {
        context.setData(selectedItemKey, itemId);
        return const HandlerResult.refresh();
      }),
    );
  }

  @override
  Future<void> onExit(NavigationContext context) async {
    // Очищаем выбранный элемент при выходе с экрана
    context.removeData(selectedItemKey);
  }
}
