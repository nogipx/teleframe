import '../../../core/admin/navigation_context_admin.dart';
import '../../../domain/entities/navigation_context.dart';
import '../base/base_screen.dart';

/// Базовый класс для экранов, доступных только администраторам.
///
/// Доступ проверяется через [AdminGuard] — список разрешённых username-ов
/// задаётся в [BotConfig.adminUsernames].
///
/// Пример использования:
/// ```dart
/// class MyAdminScreen extends AdminScreen {
///   @override
///   String get routeId => Routes.admin_something.name;
///
///   @override
///   Future<String> getMessage(NavigationContext context) async => 'Панель управления';
///
///   @override
///   Future<List<List<KeyboardButton>>> getButtons(NavigationContext context) async => [];
/// }
/// ```
abstract class AdminScreen extends BaseScreen {
  @override
  bool canAccess(NavigationContext context) => context.isAdmin;
}