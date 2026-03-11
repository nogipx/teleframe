import '../logging/logger.dart';
import 'dart:async';

/// Watchdog для мониторинга активности бота
///
/// Перезапускает бота если нет обновлений в течение указанного времени
class BotWatchdog {
  final Duration inactivityThreshold;
  final Future<void> Function() onInactivity;
  final Duration checkInterval;

  Timer? _checkTimer;
  DateTime _lastActivity = DateTime.now();
  bool _isRunning = false;

  BotWatchdog({
    this.inactivityThreshold = const Duration(minutes: 5),
    this.checkInterval = const Duration(minutes: 1),
    required this.onInactivity,
  });

  /// Запустить watchdog
  void start() {
    if (_isRunning) return;

    _isRunning = true;
    _lastActivity = DateTime.now();

    _checkTimer = Timer.periodic(checkInterval, (_) async {
      final inactiveDuration = DateTime.now().difference(_lastActivity);

      if (inactiveDuration > inactivityThreshold) {
        log('⚠️ Bot inactive for ${inactiveDuration.inMinutes} minutes');
        log('🔄 Triggering restart...');

        try {
          await onInactivity();
          // Сбросить таймер после перезапуска
          heartbeat();
        } catch (e) {
          log('❌ Error during restart: $e');
        }
      }
    });

    log('👁️ Watchdog started (threshold: ${inactivityThreshold.inMinutes}m)');
  }

  /// Остановить watchdog
  void stop() {
    _checkTimer?.cancel();
    _checkTimer = null;
    _isRunning = false;
    log('👁️ Watchdog stopped');
  }

  /// Обновить время последней активности (heartbeat)
  void heartbeat() {
    _lastActivity = DateTime.now();
  }

  /// Получить время с последней активности
  Duration get timeSinceLastActivity {
    return DateTime.now().difference(_lastActivity);
  }

  bool get isRunning => _isRunning;
}
