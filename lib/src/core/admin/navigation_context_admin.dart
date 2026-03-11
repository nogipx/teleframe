import 'package:get_it/get_it.dart';

import '../../domain/entities/navigation_context.dart';
import 'admin_guard.dart';

extension NavigationContextAdmin on NavigationContext {
  bool get isAdmin => GetIt.instance<AdminGuard>().isAdmin(this);
}