import '../keyboard_button.dart';

class BackButton extends KeyboardButton {
  static const defaultEmoji = '◀️';

  BackButton._({
    required super.text,
  }) : super(
         callbackData: 'nav:back',
         action: const BackAction(),
       );

  factory BackButton({String text = 'Назад'}) {
    return BackButton._(text: text);
  }

  factory BackButton.emoji({
    String text = 'Назад',
    String emoji = '◀️',
  }) {
    final buttonText = emoji.isNotEmpty ? '$emoji $text' : text;
    return BackButton._(text: buttonText);
  }
}
