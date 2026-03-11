import '../keyboard_button.dart';

/// Кнопка с URL-ссылкой
///
/// При нажатии открывает указанный URL в браузере/приложении
class LinkButton extends KeyboardButton {
  final String targetUrl;

  LinkButton._({
    required super.text,
    required this.targetUrl,
  }) : super(
         callbackData: 'link:${Uri.parse(targetUrl).host}',
         action: const EmptyAction(),
       );

  /// Создать кнопку со ссылкой
  factory LinkButton({
    required String text,
    required String url,
  }) {
    return LinkButton._(
      text: text,
      targetUrl: url,
    );
  }

  /// Создать кнопку со ссылкой и эмодзи
  factory LinkButton.emoji({
    required String text,
    required String url,
    String emoji = '🔗',
  }) {
    final buttonText = emoji.isNotEmpty ? '$emoji $text' : text;
    return LinkButton._(
      text: buttonText,
      targetUrl: url,
    );
  }
}
