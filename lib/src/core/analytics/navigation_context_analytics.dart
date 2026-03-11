import 'package:get_it/get_it.dart';

import '../../domain/entities/navigation_context.dart';
import '../../domain/entities/user_analytics.dart';
import 'analytics_service.dart';

/// Extension для удобного доступа к аналитике из любого экрана.
///
/// userId берётся автоматически из контекста — не нужно передавать вручную.
///
/// Примеры:
/// ```dart
/// // Счётчик просмотров
/// await context.analytics.increment('product_view');
///
/// // Флаг "показали подсказку"
/// final alreadyShown = await context.analytics.getFlag('order_tip');
/// if (!alreadyShown) {
///   await context.analytics.setFlag('order_tip');
/// }
///
/// // Первое посещение экрана (посещения трекаются автоматически)
/// final isFirstVisit = !await context.analytics.hasVisited(routeId);
///
/// // Полный снимок для дебага
/// final all = await context.analytics.getAll();
/// ```
extension NavigationContextAnalytics on NavigationContext {
  //ignore: library_private_types_in_public_api
  _UserAnalyticsProxy get analytics =>
      _UserAnalyticsProxy(userId, GetIt.instance<AnalyticsService>());
}

/// Прокси, привязанный к конкретному userId.
///
/// Позволяет вызывать методы без повторного указания userId:
/// `context.analytics.increment('event')` вместо `service.increment(userId, 'event')`.
class _UserAnalyticsProxy {
  final int _userId;
  final AnalyticsService _service;

  const _UserAnalyticsProxy(this._userId, this._service);

  Future<UserAnalytics> getAll() => _service.getAll(_userId);

  Future<void> increment(String event, {int by = 1}) =>
      _service.increment(_userId, event, by: by);

  Future<int> getCount(String event) => _service.getCount(_userId, event);

  Future<void> setFlag(String flag, {bool value = true}) =>
      _service.setFlag(_userId, flag, value: value);

  Future<bool> getFlag(String flag) => _service.getFlag(_userId, flag);

  Future<bool> hasVisited(String routeId) =>
      _service.hasVisited(_userId, routeId);

  Future<List<String>> getVisitedRoutes() => _service.getVisitedRoutes(_userId);
}
