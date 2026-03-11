import '../keyboard_button.dart';
import '../navigation_context.dart';

typedef ActionButtonHandler =
    Future<HandlerResult?> Function(NavigationContext);

class ActionButton extends KeyboardButton {
  final String actionName;
  final ActionButtonHandler handler;

  ActionButton._({
    required super.text,
    required this.actionName,
    required this.handler,
  }) : super(callbackData: 'action:$actionName', action: CustomAction(handler));

  factory ActionButton({
    required String text,
    required String actionName,
    required ActionButtonHandler handler,
  }) {
    return ActionButton._(text: text, actionName: actionName, handler: handler);
  }

  factory ActionButton.emoji({
    required String text,
    required String actionName,
    required ActionButtonHandler handler,
    String emoji = '',
  }) {
    final buttonText = emoji.isNotEmpty ? '$emoji $text' : text;
    return ActionButton._(
      text: buttonText,
      actionName: actionName,
      handler: handler,
    );
  }
}
