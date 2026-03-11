/// Аналитические данные конкретного пользователя
class UserAnalytics {
  final int userId;

  /// Счётчики событий (например 'product_view', 'button_click')
  final Map<String, int> counters;

  /// Булевые флаги (например 'saw_welcome_tip', 'completed_onboarding')
  final Map<String, bool> flags;

  /// Список посещённых маршрутов (routeId)
  final List<String> visitedRoutes;

  const UserAnalytics({
    required this.userId,
    Map<String, int>? counters,
    Map<String, bool>? flags,
    List<String>? visitedRoutes,
  }) : counters = counters ?? const {},
       flags = flags ?? const {},
       visitedRoutes = visitedRoutes ?? const [];

  /// Получить значение счётчика (0 если не установлен)
  int getCount(String event) => counters[event] ?? 0;

  /// Получить значение флага (false если не установлен)
  bool getFlag(String flag) => flags[flag] ?? false;

  /// Проверить, был ли пользователь на указанном экране
  bool hasVisited(String routeId) => visitedRoutes.contains(routeId);
}
