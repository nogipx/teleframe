import '../../../domain/entities/image_send_strategy.dart';
import '../../../domain/entities/keyboard_button.dart';
import '../../../domain/entities/navigation_context.dart';
import '../base/base_screen.dart';

/// Базовый класс для экранов с сеткой элементов
///
/// Предоставляет функционал для отображения элементов в виде сетки кнопок
/// с настраиваемым количеством колонок
abstract class GridScreen extends BaseScreen {
  /// Получить список кнопок для отображения в сетке
  Future<List<KeyboardButton>> getGridButtons(NavigationContext context);

  /// Количество колонок в сетке (по умолчанию 2)
  int get columnsCount => 2;

  @override
  ImageSendStrategy get imageSendStrategy => ImageSendStrategy.combined;

  /// Дополнительные кнопки, отображаемые после сетки
  Future<List<List<KeyboardButton>>> getAdditionalButtons(
    NavigationContext context,
  ) async => [];

  @override
  Future<List<List<KeyboardButton>>> getButtons(
    NavigationContext context,
  ) async {
    final buttons = await getGridButtons(context);
    final gridRows = _buildGrid(buttons);
    final additionalButtons = await getAdditionalButtons(context);

    return [
      ...gridRows,
      ...additionalButtons,
    ];
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
