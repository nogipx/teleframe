import '../../domain/entities/navigation_context.dart';
import '../../domain/entities/screen_state.dart';

/// Фабрика для создания экранов
typedef ScreenFactory = ScreenState Function(NavigationContext context);

/// Реестр маршрутов приложения
///
/// Управляет регистрацией и созданием экранов по их ID
class RouteRegistry {
  final Map<String, ScreenFactory> _routes = {};
  ScreenFactory? _notFoundFactory;

  /// ID маршрута стартового экрана (при /start)
  late String _startRoute;

  /// ID маршрута домашнего экрана (для возврата "домой")
  late String _homeRoute;

  /// Зарегистрировать маршрут с фабрикой создания экрана
  void register(String routeId, ScreenFactory factory) {
    if (_routes.containsKey(routeId)) {
      throw StateError('Route "$routeId" is already registered');
    }
    _routes[routeId] = factory;
  }

  /// Зарегистрировать несколько маршрутов сразу
  void registerAll(Map<String, ScreenFactory> routes) {
    routes.forEach((routeId, factory) {
      register(routeId, factory);
    });
  }

  /// Установить фабрику для незарегистрированных маршрутов (NotFound экран)
  void setNotFoundFactory(ScreenFactory factory) {
    _notFoundFactory = factory;
  }

  /// Установить ID стартового маршрута (при /start)
  void setStartRoute(String routeId) {
    _startRoute = routeId;
  }

  /// Получить ID стартового маршрута
  String get startRoute => _startRoute;

  /// Установить ID домашнего маршрута (для возврата "домой")
  void setHomeRoute(String routeId) {
    _homeRoute = routeId;
  }

  /// Получить ID домашнего маршрута
  String get homeRoute => _homeRoute;

  /// Создать экран по ID маршрута
  ///
  /// Если маршрут не зарегистрирован и установлен NotFoundFactory,
  /// вернёт NotFound экран. Иначе выбросит исключение.
  ScreenState createScreen(String routeId, NavigationContext context) {
    final factory = _routes[routeId];
    if (factory == null) {
      if (_notFoundFactory != null) {
        return _notFoundFactory!(context);
      }
      throw StateError('Route "$routeId" is not registered');
    }
    return factory(context);
  }

  /// Проверить, зарегистрирован ли маршрут
  bool hasRoute(String routeId) => _routes.containsKey(routeId);

  /// Получить список всех зарегистрированных маршрутов
  List<String> get registeredRoutes => _routes.keys.toList();
}
