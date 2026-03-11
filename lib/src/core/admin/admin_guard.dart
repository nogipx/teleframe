import '../../domain/entities/navigation_context.dart';

/// Хранит список допустимых username-ов администраторов и проверяет доступ.
///
/// Настраивается в [BotConfig.adminUsernames]:
/// ```dart
/// BotConfig(
///   adminUsernames: ['john_doe', 'alice'],
///   ...
/// )
/// ```
///
/// Username пользователя сохраняется в контекст при команде /start
/// под ключом `'_username'`.
class AdminGuard {
  final Set<String> _adminUsernames;

  AdminGuard({required List<String> adminUsernames})
    : _adminUsernames = adminUsernames.map((u) => u.toLowerCase()).toSet();

  /// Проверить, является ли пользователь из данного контекста администратором
  bool isAdmin(NavigationContext context) {
    final username = context.getData<String>('_username');
    if (username == null || username.isEmpty) return false;
    return _adminUsernames.contains(username.toLowerCase());
  }

  /// Список всех username-ов с правами администратора
  Set<String> get adminUsernames => Set.unmodifiable(_adminUsernames);
}
