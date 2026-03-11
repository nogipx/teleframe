import 'package:televerse/telegram.dart';
import 'package:televerse/televerse.dart';

import '../../domain/repositories/bot_repository.dart';

/// Источник данных для взаимодействия с Televerse API
///
/// Преобразует Televerse типы в доменные типы приложения
class TeleverseDatasource {
  final Bot bot;

  TeleverseDatasource({required this.bot});

  /// Преобразовать Televerse CallbackQuery в доменный CallbackQueryUpdate
  CallbackQueryUpdate mapCallbackQuery(CallbackQuery query) {
    return CallbackQueryUpdate(
      queryId: query.id,
      userId: query.from.id.toInt(),
      chatId: query.message?.chat.id.toInt() ?? query.from.id.toInt(),
      data: query.data ?? '',
      messageId: query.message?.messageId,
    );
  }

  /// Преобразовать Televerse Message в доменный MessageUpdate
  MessageUpdate mapMessage(Message message) {
    return MessageUpdate(
      userId: message.from?.id.toInt() ?? 0,
      chatId: message.chat.id.toInt(),
      text: message.text ?? '',
      messageId: message.messageId,
    );
  }

  /// Преобразовать Televerse Message с командой в доменный CommandUpdate
  CommandUpdate mapCommand(Message message, String command, String? payload) {
    return CommandUpdate(
      userId: message.from?.id.toInt() ?? 0,
      chatId: message.chat.id.toInt(),
      command: command,
      payload: payload,
      messageId: message.messageId,
    );
  }
}
