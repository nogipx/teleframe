import '../entities/navigation_context.dart';

/// Абстрактный репозиторий для управления сессиями пользователей
abstract class SessionRepository {
  /// Получить контекст навигации для пользователя
  ///
  /// Создает новый контекст, если сессия не существует
  Future<NavigationContext> getContext(int userId);

  /// Сохранить контекст навигации пользователя
  Future<void> saveContext(int userId, NavigationContext context);

  /// Очистить контекст пользователя (удалить сессию)
  Future<void> clearContext(int userId);

  /// Проверить наличие активной сессии для пользователя
  Future<bool> hasSession(int userId);
}
