import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:daemon_launcher/daemon_launcher.dart';
import 'package:path/path.dart' as p;

import '../bot/belyash_bot.dart';
import '../logging/logger.dart';

/// Переменные окружения для daemon режима
class _DaemonEnv {
  static const daemonFlag = 'TELEFRAME_DAEMON';
  static const pidFile = 'TELEFRAME_PID_FILE';
  static const logFile = 'TELEFRAME_LOG_FILE';

  static bool isDaemonProcess() => Platform.environment[daemonFlag] == 'true';
}

/// Запустить Telegram бота с поддержкой daemon режима.
///
/// [appName] — название приложения (используется в логах и выводе CLI)
/// [version] — версия приложения
/// [arguments] — аргументы командной строки (из `main`)
/// [buildConfig] — фабрика [BotConfig] из распарсенных аргументов
/// [extraFlags] — дополнительные флаги CLI специфичные для приложения
/// [dataDirName] — имя папки для данных (pid, logs, db)
///
/// Пример:
/// ```dart
/// void main(List<String> args) => bootstrapBot(
///   appName: 'My Bot',
///   version: '1.0.0',
///   arguments: args,
///   buildConfig: (results) => BotConfig(
///     token: results.option('token')!,
///     startRoute: Routes.start.name,
///     screenFactories: myScreenFactories,
///   ),
/// );
/// ```
Future<void> bootstrapBot({
  required String appName,
  required String version,
  required List<String> arguments,
  required BotConfig Function(ArgResults results) buildConfig,
  List<void Function(ArgParser parser)> extraArgs = const [],
  String dataDirName = '.teleframe_data',
}) async {
  return runZonedGuarded(
    () async => await _run(
      appName: appName,
      version: version,
      arguments: arguments,
      buildConfig: buildConfig,
      extraArgs: extraArgs,
      dataDirName: dataDirName,
    ),
    (error, stackTrace) {
      log('❌ Uncaught error in main zone: $error');
      log('Stack trace: $stackTrace');
      exit(1);
    },
  );
}

Future<void> _run({
  required String appName,
  required String version,
  required List<String> arguments,
  required BotConfig Function(ArgResults results) buildConfig,
  required List<void Function(ArgParser parser)> extraArgs,
  required String dataDirName,
}) async {
  final parser = _buildParser(appName, extraArgs);

  try {
    final results = parser.parse(arguments);

    if (results.flag('help')) {
      print('Usage: dart <script> <flags>');
      print(parser.usage);
      return;
    }
    if (results.flag('version')) {
      print('$appName version: $version');
      return;
    }

    final verbose = results.flag('verbose');
    final daemonMode = results.flag('daemon');
    final stopMode = results.flag('stop');
    final restartMode = results.flag('restart');

    // Пути к данным
    final scriptPath = Platform.script.toFilePath();
    final binDir = Directory(scriptPath).parent.path;
    final dataDir = p.join(binDir, dataDirName);
    final pidFilePath = p.join(dataDir, '$appName.pid');
    final logFilePath = p.join(dataDir, 'logs', '$appName.log');

    if (stopMode) {
      await _stopDaemon(pidFilePath, verbose);
      return;
    }

    if (restartMode) {
      await _stopDaemon(pidFilePath, verbose);
      await Future.delayed(Duration(seconds: 1));
      await _launchDaemon(
        appName,
        arguments,
        verbose,
        pidFilePath,
        logFilePath,
      );
      return;
    }

    if (daemonMode) {
      await _stopDaemon(pidFilePath, verbose, silent: true);
      await Future.delayed(Duration(seconds: 1));
      await _launchDaemon(
        appName,
        arguments,
        verbose,
        pidFilePath,
        logFilePath,
      );
      return;
    }

    // Обычный / daemon дочерний запуск
    final isDaemon = _DaemonEnv.isDaemonProcess();

    await AppLogger.instance.initialize(
      logFilePath: isDaemon ? logFilePath : null,
      verbose: verbose || !isDaemon,
    );

    await _writePidFile();

    log('🚀 Starting $appName v$version...');

    final config = buildConfig(results);
    final bot = TeleframeBot(config);

    ProcessSignal.sigterm.watch().listen((_) async {
      log('Получен SIGTERM, завершение...');
      await AppLogger.instance.close();
      exit(0);
    });
    ProcessSignal.sigint.watch().listen((_) async {
      log('Получен SIGINT, завершение...');
      await AppLogger.instance.close();
      exit(0);
    });

    try {
      await bot.start();
      log('⚠️  bot.start() вернул управление (не должно происходить)');
    } catch (e, stackTrace) {
      log('❌ Fatal error in bot.start(): $e');
      log('Stack trace: $stackTrace');
      await AppLogger.instance.close();
      exit(1);
    }
  } on FormatException catch (e) {
    print(e.message);
    print('');
    print(parser.usage);
  } catch (e, stackTrace) {
    log('❌ Unexpected error: $e');
    log('Stack trace: $stackTrace');
    await AppLogger.instance.close();
    exit(1);
  }
}

ArgParser _buildParser(
  String appName,
  List<void Function(ArgParser parser)> extraArgs,
) {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Показать справку.')
    ..addFlag('version', negatable: false, help: 'Показать версию.')
    ..addFlag('verbose', abbr: 'v', negatable: false, help: 'Подробный вывод.')
    ..addOption(
      'token',
      abbr: 't',
      help: 'Токен Telegram бота.',
      mandatory: true,
    )
    ..addFlag(
      'daemon',
      negatable: false,
      help: 'Запустить как фоновый процесс.',
    )
    ..addFlag('stop', negatable: false, help: 'Остановить фоновый процесс.')
    ..addFlag(
      'restart',
      negatable: false,
      help: 'Перезапустить фоновый процесс.',
    );

  for (final configure in extraArgs) {
    configure(parser);
  }

  return parser;
}

Future<void> _stopDaemon(
  String pidFilePath,
  bool verbose, {
  bool silent = false,
}) async {
  final pidFileManager = PidFileManager(pidFilePath);
  final pid = pidFileManager.readPidSync();

  if (pid == null) {
    if (!silent) print('ℹ️  Daemon не запущен (PID файл не найден)');
    return;
  }

  if (!pidFileManager.isProcessRunning(pid)) {
    if (!silent) print('ℹ️  Процесс с PID $pid не найден');
    await pidFileManager.remove();
    return;
  }

  if (verbose) print('Остановка процесса с PID $pid...');

  try {
    Process.killPid(pid, ProcessSignal.sigterm);

    for (var i = 0; i < 10; i++) {
      await Future.delayed(Duration(milliseconds: 500));
      if (!pidFileManager.isProcessRunning(pid)) break;
    }

    if (pidFileManager.isProcessRunning(pid)) {
      if (verbose) print('Процесс не завершился, отправка SIGKILL...');
      Process.killPid(pid, ProcessSignal.sigkill);
      await Future.delayed(Duration(milliseconds: 500));
    }

    await pidFileManager.remove();
    if (!silent) print('✅ Daemon остановлен (PID: $pid)');
  } catch (e) {
    if (!silent) print('❌ Ошибка остановки процесса: $e');
  }
}

Future<void> _launchDaemon(
  String appName,
  List<String> originalArgs,
  bool verbose,
  String pidFilePath,
  String logFilePath,
) async {
  await Directory(p.dirname(pidFilePath)).create(recursive: true);
  await Directory(p.dirname(logFilePath)).create(recursive: true);

  final pidFileManager = PidFileManager(pidFilePath);
  final launcher = DaemonLauncher(
    pidFileManager: pidFileManager,
    logFilePath: logFilePath,
  );

  await DaemonLog.initialize(logFilePath, appName);

  final childArgs = originalArgs
      .where((arg) => !['--daemon', '--stop', '--restart'].contains(arg))
      .toList();

  final environment = Map<String, String>.from(Platform.environment)
    ..[_DaemonEnv.daemonFlag] = 'true'
    ..[_DaemonEnv.pidFile] = pidFilePath
    ..[_DaemonEnv.logFile] = logFilePath;

  final executableArgs = RuntimeInvocationBuilder.build(childArgs);

  if (verbose) {
    print('Запуск в фоновом режиме...');
    print('PID файл: $pidFilePath');
    print('Лог файл: $logFilePath');
  }

  final result = await launcher.launch(
    executableArgs: executableArgs,
    environment: environment,
    workingDirectory: Directory.current.path,
  );

  if (result.success) {
    print('✅ $appName запущен в фоновом режиме (PID: ${result.pid})');
    print('📝 Логи: $logFilePath');
    exit(0);
  } else {
    print('❌ Ошибка запуска в фоновом режиме');
    print('📝 Проверьте логи: $logFilePath');
    exit(1);
  }
}

Future<void> _writePidFile() async {
  final pidFilePath = Platform.environment[_DaemonEnv.pidFile];
  if (pidFilePath != null && pidFilePath.isNotEmpty) {
    final pidFileManager = PidFileManager(pidFilePath);
    await pidFileManager.writePid(pid);
    log('📝 PID файл создан: $pidFilePath (PID: $pid)');
  }
}
