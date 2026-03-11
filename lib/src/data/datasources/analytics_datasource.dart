import 'dart:io';

import '../../core/logging/logger.dart';
import 'package:sembast/sembast_io.dart';
import 'package:path/path.dart' as path;

/// Источник данных для аналитики
///
/// Использует отдельный файл analytics.db рядом с belyash_store.db
class AnalyticsDatasource {
  static const String _dbName = 'analytics.db';
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    await _initDatabase();
    return _database!;
  }

  Future<void> _initDatabase() async {
    final dbPath = await _getDatabasePath();
    final dbFile = File(path.join(dbPath, _dbName));

    if (!dbFile.parent.existsSync()) {
      await dbFile.parent.create(recursive: true);
    }

    _database = await databaseFactoryIo.openDatabase(dbFile.path);
    log('📊 Analytics database initialized at: ${dbFile.path}');
  }

  Future<String> _getDatabasePath() async {
    final scriptPath = Platform.script.toFilePath();
    final binDir = Directory(scriptPath).parent.path;
    return path.join(binDir, '.belyash_store_data', 'database');
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
