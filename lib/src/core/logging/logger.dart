import 'dart:io';

/// Глобальный логгер приложения
class AppLogger {
  static AppLogger? _instance;
  File? _logFile;
  IOSink? _logSink;
  bool _verbose = false;

  AppLogger._();

  /// Получить экземпляр логгера
  static AppLogger get instance {
    _instance ??= AppLogger._();
    return _instance!;
  }

  /// Инициализировать логгер
  ///
  /// [logFilePath] - путь к файлу логов (если null - только консоль)
  /// [verbose] - выводить ли логи в консоль дополнительно
  Future<void> initialize({
    String? logFilePath,
    bool verbose = false,
  }) async {
    _verbose = verbose;

    if (logFilePath != null) {
      _logFile = File(logFilePath);

      // Создаём директорию если её нет
      final logDir = _logFile!.parent;
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }

      // Открываем файл для записи (append mode)
      _logSink = _logFile!.openWrite(mode: FileMode.append);

      // Записываем заголовок сессии
      final now = DateTime.now().toIso8601String();
      await _write('\n${'=' * 80}\n');
      await _write('📝 Log session started at $now\n');
      await _write('${'=' * 80}\n\n');

      if (_verbose) {
        print('📝 Логи записываются в: $logFilePath');
      }
    }
  }

  /// Закрыть логгер
  Future<void> close() async {
    if (_logSink != null) {
      final now = DateTime.now().toIso8601String();
      await _write('\n${'=' * 80}\n');
      await _write('📝 Log session ended at $now\n');
      await _write('${'=' * 80}\n\n');

      await _logSink!.flush();
      await _logSink!.close();
      _logSink = null;
      _logFile = null;
    }
  }

  /// Записать сообщение в лог
  Future<void> _write(String message) async {
    if (_logSink != null) {
      _logSink!.write(message);
      await _logSink!.flush();
    }
  }

  /// Логировать сообщение (синхронно)
  void log(String message) {
    final timestamp = DateTime.now().toIso8601String();
    final logMessage = '[$timestamp] $message\n';

    // Пишем в файл синхронно (если инициализирован)
    if (_logSink != null) {
      _logSink!.write(logMessage);
      // НЕ flush'им здесь - будет flush при следующей записи или при close()
    }

    // Пишем в консоль если verbose или нет файла
    if (_verbose || _logSink == null) {
      stdout.write(message);
      if (!message.endsWith('\n')) {
        stdout.write('\n');
      }
    }
  }

  /// Принудительно сбросить буфер в файл
  Future<void> flush() async {
    if (_logSink != null) {
      await _logSink!.flush();
    }
  }

  /// Получить путь к файлу логов
  String? get logFilePath => _logFile?.path;
}

/// Глобальная функция для логирования (замена print)
void log(Object? message) {
  AppLogger.instance.log(message?.toString() ?? 'null');
}
