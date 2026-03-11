import 'package:sembast/sembast.dart';

import '../../domain/entities/navigation_context.dart';
import '../../domain/entities/sent_message.dart';
import '../../domain/repositories/session_repository.dart';
import '../datasources/sembast_datasource.dart';

/// Sembast реализация репозитория сессий
///
/// Хранит контексты пользователей в Sembast БД (данные сохраняются при перезапуске)
class SembastSessionRepository implements SessionRepository {
  final SembastDatasource _datasource;
  late final StoreRef<int, Map<String, dynamic>> _store;

  SembastSessionRepository({required SembastDatasource datasource})
    : _datasource = datasource {
    _store = intMapStoreFactory.store('sessions');
  }

  @override
  Future<NavigationContext> getContext(int userId) async {
    final db = await _datasource.database;

    // Получить запись из БД
    final record = await _store.record(userId).get(db);

    // Если записи нет - создать новую сессию
    if (record == null) {
      return NavigationContext(
        userId: userId,
        chatId: userId, // По умолчанию chatId = userId
      );
    }

    // Десериализовать контекст из БД
    return _deserializeContext(record);
  }

  @override
  Future<void> saveContext(int userId, NavigationContext context) async {
    final db = await _datasource.database;

    // Сериализовать контекст
    final data = _serializeContext(context);

    // Сохранить в БД
    await _store.record(userId).put(db, data);
  }

  @override
  Future<void> clearContext(int userId) async {
    final db = await _datasource.database;
    await _store.record(userId).delete(db);
  }

  @override
  Future<bool> hasSession(int userId) async {
    final db = await _datasource.database;
    final record = await _store.record(userId).get(db);
    return record != null;
  }

  /// Сериализовать NavigationContext в Map для хранения в БД
  Map<String, dynamic> _serializeContext(NavigationContext context) {
    return {
      'userId': context.userId,
      'chatId': context.chatId,
      'navigationStack': context.navigationStack,
      'data': context.data,
      'lastMessages': context.lastMessages
          .map(
            (msg) => {
              'messageId': msg.messageId,
              'type': msg.type.name,
              'content': msg.content,
              'additionalMessageIds': msg.additionalMessageIds,
            },
          )
          .toList(),
    };
  }

  /// Десериализовать NavigationContext из Map БД
  NavigationContext _deserializeContext(Map<String, dynamic> data) {
    return NavigationContext(
      userId: data['userId'] as int,
      chatId: data['chatId'] as int,
      navigationStack:
          (data['navigationStack'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      data:
          (data['data'] as Map<dynamic, dynamic>?)?.map(
            (key, value) => MapEntry(key as String, value),
          ) ??
          {},
      lastMessages:
          (data['lastMessages'] as List<dynamic>?)?.map((e) {
            final map = e as Map<dynamic, dynamic>;
            return SentMessage(
              messageId: map['messageId'] as int,
              type: MessageType.values.byName(map['type'] as String),
              content: map['content'] as String?,
              additionalMessageIds:
                  (map['additionalMessageIds'] as List<dynamic>?)
                      ?.map((id) => id as int)
                      .toList() ??
                  [],
            );
          }).toList() ??
          [],
    );
  }
}
