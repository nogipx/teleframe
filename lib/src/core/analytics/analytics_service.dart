import '../../domain/entities/user_analytics.dart';
import '../../domain/repositories/analytics_repository.dart';

/// Сервис аналитики.
///
/// Данные хранятся per-user. Переходы и клики пишутся в [UserAnalytics.counters]
/// с префиксами `flow:` и `click:`. Агрегация происходит на лету при чтении.
///
/// Доступ из экранов через extension на [NavigationContext]:
/// ```dart
/// await context.analytics.increment('my_event');
/// final first = !await context.analytics.hasVisited(routeId);
/// ```
class AnalyticsService {
  final AnalyticsRepository _repository;

  AnalyticsService({required AnalyticsRepository repository})
      : _repository = repository;

  Future<UserAnalytics> getAll(int userId) => _repository.getAll(userId);

  Future<List<UserAnalytics>> getAllUsers() => _repository.getAllUsers();

  Future<void> increment(int userId, String event, {int by = 1}) =>
      _repository.increment(userId, event, by: by);

  Future<int> getCount(int userId, String event) =>
      _repository.getCount(userId, event);

  Future<void> setFlag(int userId, String flag, {bool value = true}) =>
      _repository.setFlag(userId, flag, value: value);

  Future<bool> getFlag(int userId, String flag) =>
      _repository.getFlag(userId, flag);

  Future<void> markVisited(int userId, String routeId) =>
      _repository.markVisited(userId, routeId);

  Future<bool> hasVisited(int userId, String routeId) =>
      _repository.hasVisited(userId, routeId);

  Future<List<String>> getVisitedRoutes(int userId) =>
      _repository.getVisitedRoutes(userId);

  // ── Трекинг навигации и кликов ────────────────

  /// Трекинг перехода: экран + переход между экранами.
  /// Вызывается fire-and-forget из NavigationManager.
  Future<void> trackNavigation({
    required int userId,
    required String routeId,
    String? previousRoute,
  }) async {
    await _repository.markVisited(userId, routeId);
    if (previousRoute != null && previousRoute != routeId) {
      await _repository.increment(userId, 'flow:$previousRoute→$routeId');
    }
  }

  /// Трекинг клика по кнопке.
  /// Вызывается fire-and-forget из CallbackHandler.
  Future<void> trackClick(int userId, String buttonText) =>
      _repository.increment(userId, 'click:$buttonText');
}