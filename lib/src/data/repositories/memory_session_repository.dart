import '../../domain/entities/navigation_context.dart';
import '../../domain/repositories/session_repository.dart';

/// In-memory реализация репозитория сессий
///
/// Хранит контексты пользователей в памяти (данные теряются при перезапуске)
class MemorySessionRepository implements SessionRepository {
  final Map<int, NavigationContext> _sessions = {};

  @override
  Future<NavigationContext> getContext(int userId) async {
    // Если сессия существует - вернуть её
    if (_sessions.containsKey(userId)) {
      return _sessions[userId]!;
    }

    // Иначе создать новую сессию
    final context = NavigationContext(
      userId: userId,
      chatId: userId, // По умолчанию chatId = userId
    );
    _sessions[userId] = context;
    return context;
  }

  @override
  Future<void> saveContext(int userId, NavigationContext context) async {
    _sessions[userId] = context;
  }

  @override
  Future<void> clearContext(int userId) async {
    _sessions.remove(userId);
  }

  @override
  Future<bool> hasSession(int userId) async {
    return _sessions.containsKey(userId);
  }
}
