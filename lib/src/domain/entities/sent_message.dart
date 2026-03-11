/// Тип отправленного сообщения
enum MessageType {
  /// Текстовое сообщение
  text,

  /// Одно фото
  photo,

  /// Медиа-группа (несколько фото)
  mediaGroup,
}

/// Информация об отправленном сообщении
///
/// Хранит структуру отправленного сообщения для правильного обновления
class SentMessage {
  /// ID сообщения в Telegram (основное)
  final int messageId;

  /// Дополнительные ID сообщений (для mediaGroup - все сообщения кроме первого)
  final List<int> additionalMessageIds;

  /// Тип сообщения
  final MessageType type;

  /// Содержимое сообщения:
  /// - Для text: текст сообщения
  /// - Для photo: URL изображения
  /// - Для mediaGroup: список URL изображений (через запятую)
  final String? content;

  const SentMessage({
    required this.messageId,
    required this.type,
    this.content,
    this.additionalMessageIds = const [],
  });

  /// Создать текстовое сообщение
  factory SentMessage.text({
    required int messageId,
    required String text,
  }) {
    return SentMessage(
      messageId: messageId,
      type: MessageType.text,
      content: text,
    );
  }

  /// Создать сообщение с фото
  factory SentMessage.photo({
    required int messageId,
    required String imageUrl,
  }) {
    return SentMessage(
      messageId: messageId,
      type: MessageType.photo,
      content: imageUrl,
    );
  }

  /// Создать сообщение с медиа-группой
  factory SentMessage.mediaGroup({
    required int messageId,
    required List<String> imageUrls,
    List<int> additionalMessageIds = const [],
  }) {
    return SentMessage(
      messageId: messageId,
      type: MessageType.mediaGroup,
      content: imageUrls.join(','),
      additionalMessageIds: additionalMessageIds,
    );
  }

  /// Получить список URL изображений (для mediaGroup)
  List<String> get imageUrls {
    if (type != MessageType.mediaGroup || content == null) {
      return [];
    }
    return content!.split(',');
  }

  /// Получить все ID сообщений (основной + дополнительные)
  List<int> get allMessageIds {
    return [messageId, ...additionalMessageIds];
  }

  @override
  String toString() {
    return 'SentMessage(id=$messageId, type=$type, content=${content?.substring(0, content!.length > 50 ? 50 : content!.length)}...)';
  }
}
