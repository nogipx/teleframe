import 'package:sembast/sembast_io.dart';

import '../../domain/entities/user_analytics.dart';
import '../../domain/repositories/analytics_repository.dart';
import '../datasources/analytics_datasource.dart';

/// Реализация репозитория аналитики через Sembast.
///
/// Все данные хранятся per-user в store `user_analytics`.
/// Агрегация происходит на лету при чтении через [getAllUsers].
class SembastAnalyticsRepository implements AnalyticsRepository {
  final AnalyticsDatasource _datasource;
  late final StoreRef<int, Map<String, dynamic>> _store;

  SembastAnalyticsRepository({required AnalyticsDatasource datasource})
    : _datasource = datasource {
    _store = intMapStoreFactory.store('user_analytics');
  }

  @override
  Future<UserAnalytics> getAll(int userId) async {
    final db = await _datasource.database;
    final record = await _store.record(userId).get(db);
    return _deserialize(userId, record);
  }

  // ── Счётчики ──────────────────────────────────

  @override
  Future<void> increment(int userId, String event, {int by = 1}) async {
    final db = await _datasource.database;
    await db.transaction((txn) async {
      final raw = await _store.record(userId).get(txn);
      final data = _mutableCopy(raw);
      final counters = _counters(data);
      counters[event] = (counters[event] ?? 0) + by;
      data['counters'] = counters;
      await _store.record(userId).put(txn, data);
    });
  }

  @override
  Future<int> getCount(int userId, String event) async {
    final db = await _datasource.database;
    final raw = await _store.record(userId).get(db);
    return _counters(raw ?? {})[event] ?? 0;
  }

  // ── Флаги ─────────────────────────────────────

  @override
  Future<void> setFlag(int userId, String flag, {bool value = true}) async {
    final db = await _datasource.database;
    await db.transaction((txn) async {
      final raw = await _store.record(userId).get(txn);
      final data = _mutableCopy(raw);
      final flags = _flags(data);
      flags[flag] = value;
      data['flags'] = flags;
      await _store.record(userId).put(txn, data);
    });
  }

  @override
  Future<bool> getFlag(int userId, String flag) async {
    final db = await _datasource.database;
    final raw = await _store.record(userId).get(db);
    return _flags(raw ?? {})[flag] ?? false;
  }

  // ── Посещения экранов ─────────────────────────

  @override
  Future<void> markVisited(int userId, String routeId) async {
    final db = await _datasource.database;
    await db.transaction((txn) async {
      final raw = await _store.record(userId).get(txn);
      final routes = _visitedRoutes(raw ?? {});
      if (routes.contains(routeId)) return;
      final data = _mutableCopy(raw);
      data['visitedRoutes'] = [...routes, routeId];
      await _store.record(userId).put(txn, data);
    });
  }

  @override
  Future<bool> hasVisited(int userId, String routeId) async {
    final db = await _datasource.database;
    final raw = await _store.record(userId).get(db);
    return _visitedRoutes(raw ?? {}).contains(routeId);
  }

  @override
  Future<List<String>> getVisitedRoutes(int userId) async {
    final db = await _datasource.database;
    final raw = await _store.record(userId).get(db);
    return List.unmodifiable(_visitedRoutes(raw ?? {}));
  }

  @override
  Future<List<UserAnalytics>> getAllUsers() async {
    final db = await _datasource.database;
    final records = await _store.find(db);
    return records.map((r) => _deserialize(r.key, r.value)).toList();
  }

  // ── Helpers ───────────────────────────────────

  Map<String, dynamic> _mutableCopy(Map<String, dynamic>? raw) =>
      raw != null ? Map<String, dynamic>.from(raw) : {};

  Map<String, int> _counters(Map raw) => (raw['counters'] as Map? ?? {}).map(
    (k, v) => MapEntry(k as String, (v as num).toInt()),
  );

  Map<String, bool> _flags(Map raw) => (raw['flags'] as Map? ?? {}).map(
    (k, v) => MapEntry(k as String, v as bool),
  );

  List<String> _visitedRoutes(Map raw) =>
      (raw['visitedRoutes'] as List? ?? []).map((e) => e as String).toList();

  UserAnalytics _deserialize(int userId, Map<String, dynamic>? raw) {
    if (raw == null) return UserAnalytics(userId: userId);
    return UserAnalytics(
      userId: userId,
      counters: _counters(raw),
      flags: _flags(raw),
      visitedRoutes: _visitedRoutes(raw),
    );
  }
}
