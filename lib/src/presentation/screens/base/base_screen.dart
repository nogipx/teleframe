import '../../../domain/entities/parse_mode.dart';
import '../../../domain/entities/screen_state.dart';

/// Базовый класс для всех экранов приложения
///
/// Предоставляет общую функциональность и утилиты для экранов
abstract class BaseScreen extends ScreenState with FormattingMixin {
  @override
  ParseMode get parseMode => ParseMode.html;
}

mixin FormattingMixin {
  /// Форматировать цену в рублях
  String formatPrice(int priceInRubles) {
    return '$priceInRubles ₽';
  }

  /// Форматировать вес в граммах
  String formatWeight(int weightInGrams) {
    if (weightInGrams >= 1000) {
      final kg = weightInGrams / 1000;
      return '${kg.toStringAsFixed(kg.truncateToDouble() == kg ? 0 : 1)} кг';
    }
    return '$weightInGrams г';
  }

  /// Создать разделительную линию
  String get divider => '─' * 30;

  /// Создать заголовок секции
  String sectionHeader(String title) {
    return '\n━━━ $title ━━━\n';
  }

  // HTML форматирование (если parseMode == ParseMode.html)
  String bold(String text) => '<b>$text</b>';
  String italic(String text) => '<i>$text</i>';
  String code(String text) => '<code>$text</code>';
  String pre(String text) => '<pre>$text</pre>';
  String underline(String text) => '<u>$text</u>';
  String strike(String text) => '<s>$text</s>';
  String link(String text, String url) => '<a href="$url">$text</a>';

  // MarkdownV2 форматирование (если parseMode == ParseMode.markdownV2)
  // Внимание: текст должен быть уже экранирован через escapeMarkdownV2()
  String mdBold(String text) => '*$text*';
  String mdItalic(String text) => '_${text}_';
  String mdCode(String text) => '`$text`';
  String mdPre(String text, [String? language]) =>
      language != null ? '```$language\n$text\n```' : '```\n$text\n```';
  String mdUnderline(String text) => '__${text}__';
  String mdStrike(String text) => '~$text~';
  String mdLink(String text, String url) => '[$text]($url)';

  /// Экранировать специальные символы для MarkdownV2
  String escapeMarkdownV2(String text) {
    const specialChars = [
      '_',
      '*',
      '[',
      ']',
      '(',
      ')',
      '~',
      '`',
      '>',
      '#',
      '+',
      '-',
      '=',
      '|',
      '{',
      '}',
      '.',
      '!',
    ];

    var escaped = text;
    for (final char in specialChars) {
      escaped = escaped.replaceAll(char, '\\$char');
    }
    return escaped;
  }

  String formatDate(DateTime date) {
    final months = [
      'января',
      'февраля',
      'марта',
      'апреля',
      'мая',
      'июня',
      'июля',
      'августа',
      'сентября',
      'октября',
      'ноября',
      'декабря',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String formatTime(DateTime date) {
    return '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
