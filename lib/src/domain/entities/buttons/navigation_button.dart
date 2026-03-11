import '../keyboard_button.dart';

class NavigationButton extends KeyboardButton {
  final String targetRoute;
  final Map<String, dynamic>? params;

  NavigationButton._({
    required super.text,
    required this.targetRoute,
    required this.params,
  }) : super(
         callbackData: _generateCallbackData(targetRoute, params),
         action: NavigateAction(targetRoute, params: params),
       );

  /// Генерировать уникальный callbackData на основе маршрута и параметров
  static String _generateCallbackData(
    String targetRoute,
    Map<String, dynamic>? params,
  ) {
    if (params == null || params.isEmpty) {
      return 'nav:$targetRoute';
    }

    // Добавляем хеш параметров для уникальности
    final paramsStr = params.entries
        .map((e) => '${e.key}=${e.value}')
        .join('&');
    return 'nav:$targetRoute#$paramsStr';
  }

  factory NavigationButton({
    required String text,
    required String targetRoute,
    Map<String, dynamic>? params,
  }) {
    return NavigationButton._(
      text: text,
      targetRoute: targetRoute,
      params: params,
    );
  }

  factory NavigationButton.emoji({
    required String text,
    required String targetRoute,
    Map<String, dynamic>? params,
    String emoji = '➡️',
  }) {
    final buttonText = emoji.isNotEmpty ? '$emoji $text' : text;
    return NavigationButton._(
      text: buttonText,
      targetRoute: targetRoute,
      params: params,
    );
  }
}
