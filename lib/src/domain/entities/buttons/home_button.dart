import '../keyboard_button.dart';

class HomeButton extends KeyboardButton {
  static const defaultEmoji = '🏠';

  HomeButton._({
    required super.text,
  }) : super(
         callbackData: 'nav:home',
         action: const HomeAction(),
       );

  factory HomeButton({String text = 'На главную'}) {
    return HomeButton._(text: text);
  }

  factory HomeButton.emoji({
    String text = 'На главную',
    String emoji = '🏠',
  }) {
    final buttonText = emoji.isNotEmpty ? '$emoji $text' : text;
    return HomeButton._(text: buttonText);
  }
}
