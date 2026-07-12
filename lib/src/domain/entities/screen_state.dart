import 'image_send_strategy.dart';
import 'keyboard_button.dart';
import 'navigation_context.dart';
import 'parse_mode.dart';

/// Абстрактный базовый класс для всех экранов бота
abstract class ScreenState {
  /// Уникальный идентификатор маршрута экрана
  String get routeId;

  /// Заголовок экрана
  String get title => '';

  /// Режим парсинга текста
  ParseMode get parseMode => ParseMode.none;

  /// Стратегия отправки изображений
  ///
  /// Определяет, как отправлять изображения:
  /// - `separateMessage` (по умолчанию): изображения отдельно, текст с кнопками отдельно
  ///   Позволяет редактировать без анимации удаления через editMessageMedia
  /// - `auto`: автоматический выбор (1 фото = combined, 2+ = separateMessage)
  /// - `combined`: всегда пытаться объединить в одно сообщение (sendPhoto с caption)
  ImageSendStrategy get imageSendStrategy => ImageSendStrategy.separateMessage;

  /// Сохранять ли сообщение при выходе с экрана
  ///
  /// - `false` (по умолчанию): удалять сообщение при навигации (чистый чат)
  /// - `true`: оставлять сообщение в истории (только убрать клавиатуру)
  ///
  /// Действует как при `navigateTo()`, так и при `goBack()`
  ///
  /// Параметр [context] позволяет принимать решение на основе состояния:
  /// ```dart
  /// @override
  /// bool keepMessageOnExit(NavigationContext context) {
  ///   // Сохраняем только если пользователь что-то выбрал
  ///   return context.getData<String>('selected_item') != null;
  /// }
  /// ```
  bool keepMessageOnExit(NavigationContext context) => false;

  /// Получить текст сообщения для отображения
  Future<String> getMessage(NavigationContext context);

  /// Получить список изображений для отображения
  ///
  /// По умолчанию возвращает пустой список (нет изображений).
  /// Переопределите для добавления изображений на экран:
  /// - 0 изображений: обычное текстовое сообщение
  /// - 1 изображение: sendPhoto с caption
  /// - 2+ изображений: sendMediaGroup + сообщение с кнопками
  ///
  /// Поддерживаемые форматы путей:
  /// - URL: `https://example.com/image.jpg`
  /// - Локальный файл: `file:///path/to/image.jpg` или `/absolute/path/image.jpg`
  /// - Telegram File ID: `AgACAgIAAxkBAAI...` (начинается с букв, без слешей)
  Future<List<String>> getImages(NavigationContext context) async => const [];

  /// Одно видео для экрана: URL или Telegram file_id, либо `null`.
  ///
  /// Если задано, экран рендерится как видео-сообщение: caption берётся из
  /// [getMessage], клавиатура — из [getButtons]. Отправляется свежим
  /// сообщением (без in-place редактирования). Аналог [getImages], но для
  /// одного видео. URL Telegram скачивает сам; file_id должен принадлежать
  /// этому боту.
  Future<String?> getVideo(NavigationContext context) async => null;

  /// Получить список кнопок для inline-клавиатуры
  ///
  /// Возвращает список строк кнопок. Каждый вложенный список - это одна строка.
  /// Пример:
  /// ```dart
  /// [
  ///   [button1, button2],  // Две кнопки в одной строке
  ///   [button3],           // Одна кнопка на всю строку
  /// ]
  /// ```
  Future<List<List<KeyboardButton>>> getButtons(NavigationContext context);

  /// Проверка прав доступа к экрану.
  ///
  /// Вызывается в [NavigationManager] до перехода на экран.
  /// Если возвращает `false` — переход отменяется, текущий экран остаётся.
  ///
  /// Переопределяйте в защищённых экранах:
  /// ```dart
  /// @override
  /// bool canAccess(NavigationContext context) =>
  ///     GetIt.instance<AdminGuard>().isAdmin(context);
  /// ```
  bool canAccess(NavigationContext context) => true;

  /// Lifecycle hook: вызывается при входе на экран
  ///
  /// Используйте для инициализации данных, загрузки ресурсов и т.д.
  Future<void> onEnter(NavigationContext context) async {}

  /// Lifecycle hook: вызывается при выходе с экрана
  ///
  /// Используйте для очистки ресурсов, сохранения состояния и т.д.
  Future<void> onExit(NavigationContext context) async {}
}
