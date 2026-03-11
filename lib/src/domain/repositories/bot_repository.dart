import '../entities/image_send_strategy.dart';
import '../entities/keyboard_button.dart';
import '../entities/parse_mode.dart';
import '../entities/sent_message.dart';

/// Абстрактный репозиторий для взаимодействия с Telegram Bot API
///
/// Изолирует доменный слой от конкретной реализации (Televerse)
abstract class BotRepository {
  /// Отправить сообщение с опциональными изображениями и клавиатурой
  ///
  /// Логика отправки определяется параметром [imageSendStrategy]:
  ///
  /// **ImageSendStrategy.auto** (по умолчанию):
  /// - 0 изображений: обычное текстовое сообщение
  /// - 1 изображение: sendPhoto с caption (текст) и клавиатурой
  /// - 2+ изображений: sendMediaGroup + отдельное сообщение с текстом и кнопками
  ///
  /// **ImageSendStrategy.separateMessage**:
  /// - Сначала sendPhoto/sendMediaGroup (без кнопок)
  /// - Затем текстовое сообщение с кнопками
  ///
  /// **ImageSendStrategy.combined**:
  /// - Всегда пытается объединить в одно сообщение
  /// - Если текст > 1024 символов, переключается на separateMessage
  ///
  /// keyboard - список строк кнопок. Каждый вложенный список = одна строка кнопок.
  /// parseMode - режим парсинга текста
  ///
  /// Возвращает список SentMessage со структурой всех отправленных сообщений
  Future<List<SentMessage>> sendMessage({
    required int chatId,
    required String text,
    List<String> images = const [],
    List<List<KeyboardButton>>? keyboard,
    ParseMode parseMode = ParseMode.none,
    ImageSendStrategy imageSendStrategy = ImageSendStrategy.auto,
  });

  /// Редактировать существующее сообщение
  ///
  /// keyboard - список строк кнопок. Каждый вложенный список = одна строка кнопок.
  /// parseMode - режим парсинга текста
  Future<void> editMessage({
    required int chatId,
    required int messageId,
    required String text,
    List<List<KeyboardButton>>? keyboard,
    ParseMode parseMode = ParseMode.none,
  });

  /// Редактировать изображение в существующем сообщении
  ///
  /// Используется для обновления фото без удаления сообщения (без анимации)
  /// Работает только с сообщениями, содержащими одно изображение
  Future<void> editMessageMedia({
    required int chatId,
    required int messageId,
    required String imageUrl,
    String? caption,
    List<List<KeyboardButton>>? keyboard,
    ParseMode parseMode = ParseMode.none,
  });

  /// Удалить клавиатуру у сообщения (оставить только текст)
  Future<void> removeKeyboard({
    required int chatId,
    required int messageId,
  });

  /// Удалить несколько сообщений одновременно (батч-удаление)
  ///
  /// Telegram Bot API поддерживает удаление до 100 сообщений за один запрос.
  /// Если какие-то сообщения не найдены - они просто пропускаются.
  /// Возвращает true при успешном выполнении.
  Future<bool> deleteMessages({
    required int chatId,
    required List<int> messageIds,
  });

  /// Ответить на callback query (убрать "часики" на кнопке)
  Future<void> answerCallbackQuery({
    required String queryId,
    String? text,
  });

  /// Отправить статус действия в чат (typing, upload_photo и т.д.)
  Future<void> sendChatAction({
    required int chatId,
    required String action,
  });

  /// Получить поток обновлений от бота
  Stream<BotUpdate> getUpdates();
}

/// Базовый класс для обновлений от бота
sealed class BotUpdate {
  const BotUpdate();
}

/// Обновление с текстовым сообщением
class MessageUpdate extends BotUpdate {
  final int userId;
  final int chatId;
  final String text;
  final int messageId;

  const MessageUpdate({
    required this.userId,
    required this.chatId,
    required this.text,
    required this.messageId,
  });
}

/// Обновление с callback query (нажатие на inline-кнопку)
class CallbackQueryUpdate extends BotUpdate {
  final String queryId;
  final int userId;
  final int chatId;
  final String data;
  final int? messageId;

  const CallbackQueryUpdate({
    required this.queryId,
    required this.userId,
    required this.chatId,
    required this.data,
    this.messageId,
  });
}

/// Обновление с командой бота
class CommandUpdate extends BotUpdate {
  final int userId;
  final int chatId;
  final String command;
  final String? payload;
  final int messageId;

  const CommandUpdate({
    required this.userId,
    required this.chatId,
    required this.command,
    this.payload,
    required this.messageId,
  });
}
