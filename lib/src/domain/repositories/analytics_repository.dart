import '../entities/user_analytics.dart';

/// Интерфейс репозитория аналитики пользователей
abstract interface class AnalyticsRepository {
  /// Полный снимок аналитики пользователя
  Future<UserAnalytics> getAll(int userId);

  /// Аналитика всех пользователей (для детального просмотра)
  Future<List<UserAnalytics>> getAllUsers();


  // ── Счётчики ──────────────────────────────────

  Future<void> increment(int userId, String event, {int by = 1});
  Future<int> getCount(int userId, String event);

  // ── Флаги ─────────────────────────────────────

  Future<void> setFlag(int userId, String flag, {bool value = true});
  Future<bool> getFlag(int userId, String flag);

  // ── Посещения экранов ─────────────────────────

  Future<void> markVisited(int userId, String routeId);
  Future<bool> hasVisited(int userId, String routeId);
  Future<List<String>> getVisitedRoutes(int userId);
}