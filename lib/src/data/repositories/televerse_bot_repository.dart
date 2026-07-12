import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/logging/logger.dart';
import '../../domain/entities/sent_message.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:televerse/telegram.dart' as tg;
import 'package:televerse/televerse.dart';

import '../../domain/entities/buttons/copy_button.dart';
import '../../domain/entities/buttons/link_button.dart';
import '../../domain/entities/image_send_strategy.dart';
import '../../domain/entities/keyboard_button.dart';
import '../../domain/entities/parse_mode.dart';
import '../../domain/repositories/bot_repository.dart';
import '../datasources/televerse_datasource.dart';

/// Реализация BotRepository на основе Televerse
class TeleverseBotRepository implements BotRepository {
  final Bot bot;
  late final TeleverseDatasource _datasource;
  late final Directory _cacheDir;

  TeleverseBotRepository({required this.bot}) {
    _datasource = TeleverseDatasource(bot: bot);
    _initCache();
  }

  /// Инициализировать директорию кеша
  void _initCache() {
    final scriptPath = Platform.script.toFilePath();
    final binDir = Directory(scriptPath).parent.path;
    _cacheDir = Directory('$binDir/.belyash_store_data/cache');

    if (!_cacheDir.existsSync()) {
      _cacheDir.createSync(recursive: true);
      log('📁 Created cache directory: ${_cacheDir.path}');
    }
  }

  @override
  Future<List<SentMessage>> sendMessage({
    required int chatId,
    required String text,
    List<String> images = const [],
    List<List<KeyboardButton>>? keyboard,
    ParseMode parseMode = ParseMode.none,
    ImageSendStrategy imageSendStrategy = ImageSendStrategy.auto,
  }) async {
    final chatIdObj = ChatID(chatId);
    final replyMarkup = keyboard != null
        ? _buildInlineKeyboard(keyboard)
        : null;
    final parseModeEnum = _parseModeToTelegram(parseMode);

    // Фильтрация валидных URL изображений
    final validImages = images.where(_isValidImageUrl).toList();

    // Константа лимита caption в Telegram
    const captionLimit = 1024;

    if (validImages.isEmpty) {
      // Случай 1: Нет изображений или все невалидные - обычное текстовое сообщение
      if (images.isNotEmpty && validImages.isEmpty) {
        log('Warning: All image URLs are invalid, sending text message only');
      }
      final message = await bot.api.sendMessage(
        chatIdObj,
        text,
        replyMarkup: replyMarkup,
        parseMode: parseModeEnum,
      );
      return [
        SentMessage.text(messageId: message.messageId, text: text),
      ];
    }

    // Определяем эффективную стратегию
    ImageSendStrategy effectiveStrategy = imageSendStrategy;

    // Для combined: если текст > 1024, переключаемся на separateMessage
    if (imageSendStrategy == ImageSendStrategy.combined &&
        text.length > captionLimit) {
      log(
        'Text exceeds caption limit (${text.length} > $captionLimit), switching to separateMessage',
      );
      effectiveStrategy = ImageSendStrategy.separateMessage;
    }

    // Логика отправки в зависимости от стратегии
    if (effectiveStrategy == ImageSendStrategy.separateMessage) {
      // Стратегия: отдельное сообщение
      return await _sendWithSeparateMessage(
        chatIdObj,
        text,
        validImages,
        replyMarkup,
        parseModeEnum,
      );
    } else if (effectiveStrategy == ImageSendStrategy.combined ||
        (effectiveStrategy == ImageSendStrategy.auto &&
            validImages.length == 1)) {
      // Стратегия: объединенное сообщение (или auto с 1 изображением)
      return await _sendWithCombinedMessage(
        chatIdObj,
        text,
        validImages,
        replyMarkup,
        parseModeEnum,
      );
    } else {
      // auto с 2+ изображениями - медиа-группа + текст
      return await _sendWithMediaGroup(
        chatIdObj,
        text,
        validImages,
        replyMarkup,
        parseModeEnum,
      );
    }
  }

  @override
  Future<SentMessage> sendVideo({
    required int chatId,
    required String video,
    String? caption,
    List<List<KeyboardButton>>? keyboard,
    ParseMode parseMode = ParseMode.none,
  }) async {
    final replyMarkup =
        keyboard != null ? _buildInlineKeyboard(keyboard) : null;
    // A bare source with an http(s) scheme is a URL Telegram fetches
    // itself; otherwise it's a file_id belonging to this bot.
    final isUrl = video.startsWith('http://') || video.startsWith('https://');
    final inputFile =
        isUrl ? InputFile.fromUrl(video) : InputFile.fromFileId(video);
    final message = await bot.api.sendVideo(
      ChatID(chatId),
      inputFile,
      caption: caption,
      replyMarkup: replyMarkup,
      parseMode: _parseModeToTelegram(parseMode),
    );
    return SentMessage.video(
      messageId: message.messageId,
      videoSource: video,
    );
  }

  /// Отправить с объединенным сообщением (sendPhoto с caption)
  Future<List<SentMessage>> _sendWithCombinedMessage(
    ChatID chatId,
    String text,
    List<String> images,
    tg.InlineKeyboardMarkup? replyMarkup,
    tg.ParseMode? parseMode,
  ) async {
    if (images.length == 1) {
      try {
        log('📷 Sending single image with caption (combined)');
        final inputFile = await _createInputFile(images.first);
        final message = await bot.api.sendPhoto(
          chatId,
          inputFile,
          caption: text,
          replyMarkup: replyMarkup,
          parseMode: parseMode,
        );
        return [
          SentMessage.photo(
            messageId: message.messageId,
            imageUrl: images.first,
          ),
        ];
      } catch (e) {
        log('Error sending photo: $e');
        log('Falling back to text message');
        final message = await bot.api.sendMessage(
          chatId,
          text,
          replyMarkup: replyMarkup,
          parseMode: parseMode,
        );
        return [
          SentMessage.text(messageId: message.messageId, text: text),
        ];
      }
    } else {
      // Несколько изображений с combined - используем медиа-группу
      return await _sendWithMediaGroup(
        chatId,
        text,
        images,
        replyMarkup,
        parseMode,
      );
    }
  }

  /// Отправить с отдельным сообщением
  Future<List<SentMessage>> _sendWithSeparateMessage(
    ChatID chatId,
    String text,
    List<String> images,
    tg.InlineKeyboardMarkup? replyMarkup,
    tg.ParseMode? parseMode,
  ) async {
    final sentMessages = <SentMessage>[];

    try {
      if (images.length == 1) {
        log('📷 Sending single image as separate message');
        final inputFile = await _createInputFile(images.first);
        final photoMessage = await bot.api.sendPhoto(chatId, inputFile);
        sentMessages.add(
          SentMessage.photo(
            messageId: photoMessage.messageId,
            imageUrl: images.first,
          ),
        );
      } else {
        log('📷 Sending media group as separate message');
        final mediaGroup = await _buildMediaGroup(images, null);
        final mediaMessages = await bot.api.sendMediaGroup(chatId, mediaGroup);
        // Для медиа-группы сохраняем все ID сообщений
        if (mediaMessages.isNotEmpty) {
          final allIds = mediaMessages.map((m) => m.messageId).toList();
          sentMessages.add(
            SentMessage.mediaGroup(
              messageId: allIds.first,
              imageUrls: images,
              additionalMessageIds: allIds.skip(1).toList(),
            ),
          );
        }
      }

      // Отправляем текст с кнопками отдельно
      final textMessage = await bot.api.sendMessage(
        chatId,
        text,
        replyMarkup: replyMarkup,
        parseMode: parseMode,
      );
      sentMessages.add(
        SentMessage.text(messageId: textMessage.messageId, text: text),
      );

      return sentMessages;
    } catch (e) {
      log('Error sending images separately: $e');
      log('Falling back to text message');
      final message = await bot.api.sendMessage(
        chatId,
        text,
        replyMarkup: replyMarkup,
        parseMode: parseMode,
      );
      return [
        SentMessage.text(messageId: message.messageId, text: text),
      ];
    }
  }

  /// Отправить медиа-группу + текст
  Future<List<SentMessage>> _sendWithMediaGroup(
    ChatID chatId,
    String text,
    List<String> images,
    tg.InlineKeyboardMarkup? replyMarkup,
    tg.ParseMode? parseMode,
  ) async {
    try {
      log('📷 Sending media group + text message');
      final mediaGroup = await _buildMediaGroup(images, null);
      final mediaMessages = await bot.api.sendMediaGroup(chatId, mediaGroup);
      final sentMessages = <SentMessage>[];

      // Добавляем медиа-группу (сохраняем все ID сообщений)
      if (mediaMessages.isNotEmpty) {
        final allIds = mediaMessages.map((m) => m.messageId).toList();
        sentMessages.add(
          SentMessage.mediaGroup(
            messageId: allIds.first,
            imageUrls: images,
            additionalMessageIds: allIds.skip(1).toList(),
          ),
        );
      }

      // Отправляем текст с кнопками отдельно
      final message = await bot.api.sendMessage(
        chatId,
        text,
        replyMarkup: replyMarkup,
        parseMode: parseMode,
      );
      sentMessages.add(
        SentMessage.text(messageId: message.messageId, text: text),
      );

      return sentMessages;
    } catch (e) {
      log('Error sending media group: $e');
      log('Falling back to text message');
      final message = await bot.api.sendMessage(
        chatId,
        text,
        replyMarkup: replyMarkup,
        parseMode: parseMode,
      );
      return [
        SentMessage.text(messageId: message.messageId, text: text),
      ];
    }
  }

  @override
  Future<void> editMessage({
    required int chatId,
    required int messageId,
    required String text,
    List<List<KeyboardButton>>? keyboard,
    ParseMode parseMode = ParseMode.none,
  }) async {
    final chatIdObj = ChatID(chatId);
    final replyMarkup = keyboard != null
        ? _buildInlineKeyboard(keyboard)
        : null;
    final parseModeEnum = _parseModeToTelegram(parseMode);

    try {
      await bot.api.editMessageText(
        chatIdObj,
        messageId,
        text,
        replyMarkup: replyMarkup,
        parseMode: parseModeEnum,
      );
    } catch (e) {
      log('Warning: Failed to edit message: $e');
      rethrow;
    }
  }

  @override
  Future<void> removeKeyboard({
    required int chatId,
    required int messageId,
  }) async {
    try {
      await bot.api.editMessageReplyMarkup(
        ChatID(chatId),
        messageId,
        replyMarkup: null,
      );
    } catch (e) {
      // Игнорируем ошибки - возможно сообщение уже без клавиатуры или удалено
      log('Warning: Failed to remove keyboard from message $messageId: $e');
    }
  }

  @override
  Future<void> editMessageMedia({
    required int chatId,
    required int messageId,
    required String imageUrl,
    String? caption,
    List<List<KeyboardButton>>? keyboard,
    ParseMode parseMode = ParseMode.none,
  }) async {
    try {
      final inputFile = await _createInputFile(imageUrl);
      final replyMarkup = keyboard != null
          ? _buildInlineKeyboard(keyboard)
          : null;
      final parseModeEnum = _parseModeToTelegram(parseMode);

      // Создаем InputMediaPhoto
      final media = tg.InputMediaPhoto(
        media: inputFile,
        caption: caption,
        parseMode: parseModeEnum,
      );

      await bot.api.editMessageMedia(
        ChatID(chatId),
        messageId,
        media,
        replyMarkup: replyMarkup,
      );
    } catch (e) {
      log('Warning: Failed to edit message media: $e');
      rethrow;
    }
  }

  @override
  Future<bool> deleteMessages({
    required int chatId,
    required List<int> messageIds,
  }) async {
    if (messageIds.isEmpty) {
      return true;
    }

    try {
      // Telegram Bot API поддерживает до 100 сообщений за раз
      const maxBatchSize = 100;

      if (messageIds.length <= maxBatchSize) {
        // Одна пачка - отправляем сразу
        return await bot.api.deleteMessages(ChatID(chatId), messageIds);
      } else {
        // Несколько пачек - разбиваем на батчи
        log(
          'Deleting ${messageIds.length} messages in batches of $maxBatchSize',
        );
        var allSuccess = true;

        for (var i = 0; i < messageIds.length; i += maxBatchSize) {
          final end = (i + maxBatchSize < messageIds.length)
              ? i + maxBatchSize
              : messageIds.length;
          final batch = messageIds.sublist(i, end);

          try {
            final result = await bot.api.deleteMessages(ChatID(chatId), batch);
            if (!result) {
              allSuccess = false;
            }
          } catch (e) {
            log(
              'Warning: Failed to delete batch ${i ~/ maxBatchSize + 1}: $e',
            );
            allSuccess = false;
          }
        }

        return allSuccess;
      }
    } catch (e) {
      log('Warning: Failed to delete messages: $e');
      return false;
    }
  }

  @override
  Future<void> answerCallbackQuery({
    required String queryId,
    String? text,
  }) async {
    try {
      await bot.api.answerCallbackQuery(queryId, text: text);
    } catch (e) {
      log('Warning: Failed to answer callback query: $e');
    }
  }

  @override
  Future<void> sendChatAction({
    required int chatId,
    required String action,
  }) async {
    try {
      // Преобразовать строку в ChatAction enum
      final chatAction = _getChatAction(action);
      await bot.api.sendChatAction(ChatID(chatId), chatAction);
    } catch (e) {
      log('Warning: Failed to send chat action: $e');
    }
  }

  /// Преобразовать строку в ChatAction enum
  tg.ChatAction _getChatAction(String action) {
    switch (action.toLowerCase()) {
      case 'typing':
        return tg.ChatAction.typing;
      case 'upload_photo':
        return tg.ChatAction.uploadPhoto;
      case 'record_video':
        return tg.ChatAction.recordVideo;
      case 'upload_video':
        return tg.ChatAction.uploadVideo;
      case 'record_voice':
        return tg.ChatAction.recordVoice;
      case 'upload_voice':
        return tg.ChatAction.uploadVoice;
      case 'upload_document':
        return tg.ChatAction.uploadDocument;
      case 'choose_sticker':
        return tg.ChatAction.chooseSticker;
      case 'find_location':
        return tg.ChatAction.findLocation;
      case 'record_video_note':
        return tg.ChatAction.recordVideoNote;
      case 'upload_video_note':
        return tg.ChatAction.uploadVideoNote;
      default:
        log('Warning: Unknown chat action "$action", using "typing"');
        return tg.ChatAction.typing;
    }
  }

  @override
  Stream<BotUpdate> getUpdates() {
    final controller = StreamController<BotUpdate>();

    // Слушаем callback queries через метод callbackQuery
    bot.callbackQuery(RegExp('.*'), (ctx) {
      if (ctx.callbackQuery != null) {
        controller.add(_datasource.mapCallbackQuery(ctx.callbackQuery!));
      }
    });

    return controller.stream;
  }

  /// Построить inline-клавиатуру из списка строк кнопок
  tg.InlineKeyboardMarkup _buildInlineKeyboard(
    List<List<KeyboardButton>> buttonRows,
  ) {
    final rows = <List<tg.InlineKeyboardButton>>[];

    for (final buttonRow in buttonRows) {
      final row = <tg.InlineKeyboardButton>[];
      for (final button in buttonRow) {
        // Определяем тип кнопки и создаём соответствующий InlineKeyboardButton
        if (button is CopyButton) {
          // Кнопка для копирования текста
          row.add(
            tg.InlineKeyboardButton(
              text: button.text,
              copyText: tg.CopyTextButton(text: button.textToCopy),
            ),
          );
        } else if (button is LinkButton) {
          // Кнопка со ссылкой
          row.add(
            tg.InlineKeyboardButton(
              text: button.text,
              url: button.targetUrl,
            ),
          );
        } else {
          // Обычная callback кнопка (NavigationButton, ActionButton и т.д.)
          row.add(
            tg.InlineKeyboardButton(
              text: button.text,
              callbackData: button.callbackData,
            ),
          );
        }
      }
      if (row.isNotEmpty) {
        rows.add(row);
      }
    }

    return tg.InlineKeyboardMarkup(inlineKeyboard: rows);
  }

  /// Построить медиагруппу из списка изображений
  Future<List<tg.InputMedia>> _buildMediaGroup(
    List<String> images,
    String? caption,
  ) async {
    final mediaList = <tg.InputMedia>[];

    for (var i = 0; i < images.length; i++) {
      final media = tg.InputMediaPhoto(
        media: await _createInputFile(images[i]),
        // Caption только для первого изображения (если передан)
        caption: (i == 0 && caption != null) ? caption : null,
      );
      mediaList.add(media);
    }

    return mediaList;
  }

  /// Создать InputFile из строки (URL, путь к файлу или File ID)
  Future<InputFile> _createInputFile(String source) async {
    // Проверка на File ID (обычно начинается с букв и не содержит слешей)
    if (!source.contains('/') &&
        !source.contains('\\') &&
        source.length > 10 &&
        RegExp(r'^[A-Za-z]').hasMatch(source)) {
      return InputFile.fromFileId(source);
    }

    // Проверка на URL (http/https)
    if (source.startsWith('http://') || source.startsWith('https://')) {
      // Всегда скачиваем и кешируем URL изображения
      try {
        final file = await _downloadAndCacheImage(source);
        return InputFile.fromFile(file);
      } catch (e) {
        log('Failed to download/cache image: $e');
        // Fallback: попробуем отправить как URL
        String? fileName;
        try {
          final uri = Uri.parse(source);
          final path = uri.path;
          if (path.isNotEmpty) {
            final segments = path.split('/');
            final lastSegment = segments.last;
            if (lastSegment.contains('.')) {
              fileName = lastSegment;
            }
          }
        } catch (_) {}

        fileName ??= 'image.jpg';
        return InputFile.fromUrl(source, name: fileName);
      }
    }

    // Проверка на файл (file:// или абсолютный путь)
    String filePath = source;
    if (source.startsWith('file://')) {
      filePath = source.substring(7); // Убрать префикс file://
    }

    final file = File(filePath);
    if (file.existsSync()) {
      return InputFile.fromFile(file);
    }

    // По умолчанию попробовать как URL
    log(
      'Warning: Unable to determine type of image source: $source, trying as URL',
    );
    return InputFile.fromUrl(source);
  }

  /// Скачать изображение по URL и закешировать
  Future<File> _downloadAndCacheImage(String url) async {
    // Создаем хеш URL для имени файла
    final urlHash = md5.convert(utf8.encode(url)).toString();

    // Проверяем кеш (ищем и .svg и .png для конвертированных SVG)
    final cachedFiles = _cacheDir.listSync().whereType<File>().where((file) {
      return file.path.contains(urlHash);
    });

    if (cachedFiles.isNotEmpty) {
      log('✓ Using cached image: ${cachedFiles.first.path}');
      return cachedFiles.first;
    }

    // Скачиваем
    log('⬇️  Downloading image: $url');
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Failed to download image: ${response.statusCode}');
    }

    // Определяем расширение по Content-Type или URL
    String extension = '.jpg';
    bool isSvg = false;
    final contentType = response.headers['content-type'];

    // Проверка на SVG
    if (contentType != null && contentType.contains('svg')) {
      isSvg = true;
      extension = '.svg';
    } else if (url.toLowerCase().endsWith('.svg')) {
      isSvg = true;
      extension = '.svg';
    } else if (contentType != null) {
      if (contentType.contains('webp')) {
        extension = '.webp';
      } else if (contentType.contains('png')) {
        extension = '.png';
      } else if (contentType.contains('gif')) {
        extension = '.gif';
      } else if (contentType.contains('jpeg')) {
        extension = '.jpg';
      }
    }

    // Если это SVG - скачиваем, конвертируем в PNG
    if (isSvg) {
      log('🔄 Converting SVG to PNG...');
      final svgFile = File('${_cacheDir.path}/$urlHash.svg');
      await svgFile.writeAsBytes(response.bodyBytes);

      try {
        final pngFile = await _convertSvgToPng(svgFile, urlHash);
        // Удаляем временный SVG файл
        await svgFile.delete();
        return pngFile;
      } catch (e) {
        log('❌ Failed to convert SVG to PNG: $e');
        // Если конвертация не удалась, удаляем SVG и пробрасываем ошибку
        await svgFile.delete();
        rethrow;
      }
    }

    // Сохраняем в кеш обычные изображения
    final cacheFile = File('${_cacheDir.path}/$urlHash$extension');
    await cacheFile.writeAsBytes(response.bodyBytes);

    final sizeKb = (response.bodyBytes.length / 1024).toStringAsFixed(1);
    log('💾 Cached image: $urlHash$extension ($sizeKb KB)');

    return cacheFile;
  }

  /// Конвертировать SVG в PNG используя ImageMagick
  Future<File> _convertSvgToPng(File svgFile, String baseFileName) async {
    final pngPath = '${_cacheDir.path}/$baseFileName.png';

    // Проверяем наличие ImageMagick
    // Пробуем сначала 'magick' (IM v7), затем 'convert' (IM v6)
    String? command;
    try {
      final checkMagick = await Process.run('which', ['magick']);
      if (checkMagick.exitCode == 0) {
        command = 'magick';
      }
    } catch (_) {}

    command ??= 'convert'; // Fallback на старый convert

    // Используем ImageMagick для конвертации
    // -background white - белый фон
    // -flatten - применить фон (объединить слои)
    // -density 300 - высокое качество (300 DPI)
    // -resize 2048x2048> - максимальный размер 2048px (не увеличивать маленькие)
    final args = [
      if (command == 'magick') 'convert', // для IM v7 нужно: magick convert
      '-background', 'white',
      '-flatten',
      '-density', '300',
      '-resize', '2048x2048>',
      svgFile.path,
      pngPath,
    ];

    final result = await Process.run(command, args);

    if (result.exitCode != 0) {
      throw Exception(
        'ImageMagick convert failed: ${result.stderr}\n${result.stdout}',
      );
    }

    final pngFile = File(pngPath);
    if (!pngFile.existsSync()) {
      throw Exception('PNG file was not created: $pngPath');
    }

    final sizeKb = (pngFile.lengthSync() / 1024).toStringAsFixed(1);
    log('✅ Converted SVG to PNG: $baseFileName.png ($sizeKb KB)');

    return pngFile;
  }

  /// Очистить кеш изображений (опционально)
  void clearImageCache() {
    if (_cacheDir.existsSync()) {
      final files = _cacheDir.listSync().whereType<File>();
      for (final file in files) {
        file.deleteSync();
      }
      log('🗑️  Cleared ${files.length} cached images');
    }
  }

  /// Проверить валидность источника изображения (URL, локальный файл или File ID)
  bool _isValidImageUrl(String source) {
    if (source.isEmpty) return false;

    // 1. Проверка на HTTP(S) URL (приоритет!)
    if (source.startsWith('http://') || source.startsWith('https://')) {
      try {
        final uri = Uri.parse(source);

        // Проверка наличия хоста
        if (uri.host.isEmpty) {
          log('Invalid URL: no host for $source');
          return false;
        }

        // Опциональная проверка расширения файла
        final path = uri.path.toLowerCase();
        final validExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp'];
        final hasValidExtension = validExtensions.any(
          (ext) => path.endsWith(ext),
        );

        if (!hasValidExtension) {
          log('Warning: URL might not be a valid image: $source');
          // Не отклоняем, так как некоторые сервисы не используют расширения
        }

        return true;
      } catch (e) {
        log('Error parsing URL: $source, error: $e');
        return false;
      }
    }

    // 2. Проверка на File ID (обычно начинается с букв и не содержит слешей)
    if (!source.contains('/') &&
        !source.contains('\\') &&
        source.length > 10 &&
        RegExp(r'^[A-Za-z]').hasMatch(source)) {
      return true; // File ID всегда валиден
    }

    // 3. Проверка на локальный файл
    String filePath = source;
    if (source.startsWith('file://')) {
      filePath = source.substring(7);
    }

    // Если это похоже на путь к файлу (содержит слеши или начинается с /)
    if (source.contains('/') ||
        source.contains('\\') ||
        source.startsWith('/')) {
      final file = File(filePath);
      if (file.existsSync()) {
        return true; // Локальный файл существует
      }
      log('Warning: Local file does not exist: $filePath');
      return false;
    }

    // Неизвестный формат
    log('Unknown image source format: $source');
    return false;
  }

  /// Преобразовать ParseMode в Telegram ParseMode
  tg.ParseMode? _parseModeToTelegram(ParseMode mode) {
    switch (mode) {
      case ParseMode.html:
        return tg.ParseMode.html;
      case ParseMode.markdownV2:
        return tg.ParseMode.markdownV2;
      case ParseMode.none:
        return null;
    }
  }
}
