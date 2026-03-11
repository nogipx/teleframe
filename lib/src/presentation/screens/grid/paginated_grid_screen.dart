import '../../../domain/entities/image_send_strategy.dart';
import '../../../domain/entities/keyboard_button.dart';
import '../../../domain/entities/navigation_context.dart';
import 'grid_screen.dart';

/// Экран с сеткой элементов и пагинацией
///
/// Автоматически разбивает элементы на страницы и добавляет кнопки навигации
/// между страницами (Далее/Назад)
abstract class PaginatedGridScreen extends GridScreen {
  /// Количество элементов на одной странице
  int get itemsPerPage;

  /// Ключ для хранения текущей страницы в context.data
  ///
  /// По умолчанию использует routeId для предотвращения коллизий
  String get pageKey => '${routeId}_page';

  /// Получить все кнопки (без пагинации)
  @override
  Future<List<KeyboardButton>> getGridButtons(NavigationContext context);

  /// Текст кнопки "следующая страница"
  /// Переопределите для изменения текста
  String get nextButtonText => '➡️';

  /// Текст кнопки "предыдущая страница"
  /// Переопределите для изменения текста
  String get previousButtonText => '⬅️';

  /// Показывать ли номер страницы в кнопках навигации (напр. "2/5")
  bool get showPageNumbers => false;

  @override
  ImageSendStrategy get imageSendStrategy => ImageSendStrategy.separateMessage;

  @override
  Future<void> onExit(NavigationContext context) async {
    // Очищаем данные о текущей странице при выходе с экрана
    context.removeData(pageKey);
    await super.onExit(context);
  }

  /// Получить кнопки пагинации (внутренний метод)
  Future<List<List<KeyboardButton>>> _getPaginationButtons(
    NavigationContext context,
  ) async {
    final allButtons = await getGridButtons(context);
    final currentPage = getCurrentPage(context);
    final totalPages = getTotalPages(allButtons.length);

    if (totalPages <= 1) {
      return [];
    }

    final buttons = <KeyboardButton>[];

    // Кнопка "Назад" (к предыдущей странице)
    if (currentPage > 0) {
      buttons.add(
        KeyboardButton(
          text: showPageNumbers
              ? '$previousButtonText ($currentPage/$totalPages)'
              : previousButtonText,
          callbackData: 'action:page_prev_$currentPage',
          action: CustomAction((context) async {
            // Обновляем страницу через setData и возвращаем refresh
            context.setData(pageKey, currentPage - 1);
            return const HandlerResult.refresh();
          }),
        ),
      );
    }

    // Кнопка "Далее" (к следующей странице)
    if (currentPage < totalPages - 1) {
      buttons.add(
        KeyboardButton(
          text: showPageNumbers
              ? '$nextButtonText (${currentPage + 2}/$totalPages)'
              : nextButtonText,
          callbackData: 'action:page_next_$currentPage',
          action: CustomAction((context) async {
            // Обновляем страницу через setData и возвращаем refresh
            context.setData(pageKey, currentPage + 1);
            return const HandlerResult.refresh();
          }),
        ),
      );
    }

    return buttons.isNotEmpty ? [buttons] : [];
  }

  /// Переопределяем getGridButtons для возврата только кнопок текущей страницы
  Future<List<KeyboardButton>> _getPageButtons(
    NavigationContext context,
  ) async {
    final allButtons = await getGridButtons(context);
    final currentPage = getCurrentPage(context);
    final startIndex = currentPage * itemsPerPage;
    final endIndex = (startIndex + itemsPerPage).clamp(0, allButtons.length);

    if (startIndex >= allButtons.length) {
      return [];
    }

    return allButtons.sublist(startIndex, endIndex);
  }

  @override
  Future<List<List<KeyboardButton>>> getButtons(
    NavigationContext context,
  ) async {
    // Используем кнопки текущей страницы вместо всех кнопок
    final pageButtons = await _getPageButtons(context);
    final gridRows = _buildGrid(pageButtons);
    final paginationButtons = await _getPaginationButtons(context);
    final additionalButtons = await getAdditionalButtons(context);

    return [
      ...gridRows,
      ...paginationButtons,
      ...additionalButtons,
    ];
  }

  /// Получить текущую страницу из параметров навигации (0-based индекс)
  ///
  /// Используйте этот метод в наследниках для получения номера текущей страницы.
  /// Для отображения пользователю добавьте +1 к результату.
  int getCurrentPage(NavigationContext context) {
    final page = context.data[pageKey];
    if (page is int && page >= 0) {
      return page;
    }
    return 0;
  }

  /// Вычислить общее количество страниц на основе общего количества элементов
  ///
  /// Используйте этот метод в наследниках для получения общего количества страниц.
  int getTotalPages(int totalItems) {
    if (totalItems == 0 || itemsPerPage == 0) return 0;
    return (totalItems / itemsPerPage).ceil();
  }

  /// Построить сетку из списка кнопок
  List<List<KeyboardButton>> _buildGrid(List<KeyboardButton> buttons) {
    final rows = <List<KeyboardButton>>[];

    for (var i = 0; i < buttons.length; i += columnsCount) {
      final row = buttons.skip(i).take(columnsCount).toList();
      rows.add(row);
    }

    return rows;
  }
}
