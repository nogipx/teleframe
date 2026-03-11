import '../keyboard_button.dart';

/// Кнопка для копирования текста в буфер обмена
///
/// При нажатии копирует указанный текст (требует Bot API 7.0+)
/// Telegram автоматически показывает уведомление "Copied to clipboard"
class CopyButton extends KeyboardButton {
  final String textToCopy;

  CopyButton._({
    required super.text,
    required this.textToCopy,
  }) : super(
         callbackData: 'copy:${textToCopy.hashCode}',
         action: const EmptyAction(),
       );

  /// Создать кнопку для копирования
  ///
  /// [buttonText] - текст на кнопке
  /// [textToCopy] - текст, который будет скопирован
  factory CopyButton({
    required String buttonText,
    required String textToCopy,
  }) {
    return CopyButton._(
      text: buttonText,
      textToCopy: textToCopy,
    );
  }

  /// Создать кнопку для копирования с эмодзи
  factory CopyButton.emoji({
    required String buttonText,
    required String textToCopy,
    String emoji = '📋',
  }) {
    final text = emoji.isNotEmpty ? '$emoji $buttonText' : buttonText;
    return CopyButton._(
      text: text,
      textToCopy: textToCopy,
    );
  }
}
