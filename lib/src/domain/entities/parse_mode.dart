/// Режим парсинга текста сообщений Telegram
enum ParseMode {
  /// HTML форматирование: <b>bold</b>, <i>italic</i>, <code>code</code>, etc.
  html,

  /// Markdown V2 форматирование (строгий синтаксис, требует экранирования)
  markdownV2,

  /// Plain text (без форматирования)
  none,
}
