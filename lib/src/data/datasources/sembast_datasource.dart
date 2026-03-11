import '../../core/logging/logger.dart';
import 'dart:io';
import 'package:sembast/sembast_io.dart';
import 'package:path/path.dart' as path;

/// Источник данных для работы с Sembast БД
///
/// Предоставляет низкоуровневый доступ к базе данных
class SembastDatasource {
  static const String _dbName = 'belyash_store.db';
  Database? _database;

  /// Получить экземпляр базы данных
  ///
  /// Создает БД если она еще не инициализирована
  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    await _initDatabase();
    return _database!;
  }

  /// Инициализировать базу данных
  Future<void> _initDatabase() async {
    // Получить путь к директории для хранения данных
    final dbPath = await _getDatabasePath();
    final dbFile = File(path.join(dbPath, _dbName));

    // Создать директорию если не существует
    if (!dbFile.parent.existsSync()) {
      await dbFile.parent.create(recursive: true);
    }

    // Открыть базу данных
    _database = await databaseFactoryIo.openDatabase(dbFile.path);
    log('📦 Sembast database initialized at: ${dbFile.path}');
  }

  /// Получить путь к директории для хранения БД
  Future<String> _getDatabasePath() async {
    // Для CLI приложения используем директорию рядом со скриптом
    final scriptPath = Platform.script.toFilePath();
    final binDir = Directory(scriptPath).parent.path;
    return path.join(binDir, '.belyash_store_data', 'database');
  }

  /// Закрыть базу данных
  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
