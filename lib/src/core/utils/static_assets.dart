import '../logging/logger.dart';
import 'dart:io';

/// Утилита для работы со статическими файлами бота
///
/// Все статические файлы хранятся в папке .belyash_store_data рядом с запускаемым файлом
class StaticAssets {
  static Directory? _staticDir;

  /// Название папки для статических файлов
  static const String staticDirName = '.belyash_store_data';

  /// Подпапки
  static const String imagesSubdir = 'images';
  static const String videosSubdir = 'videos';
  static const String documentsSubdir = 'documents';

  /// Инициализировать статические ресурсы
  ///
  /// Создаёт папку .belyash_static и подпапки, если их нет
  static Future<void> initialize() async {
    final staticDir = _getStaticDirectory();

    // Создать основную папку
    if (!await staticDir.exists()) {
      await staticDir.create(recursive: true);
      log('📁 Created static directory: ${staticDir.path}');
    }

    // Создать подпапки
    final subdirs = [imagesSubdir, videosSubdir, documentsSubdir];
    for (final subdir in subdirs) {
      final dir = Directory('${staticDir.path}/$subdir');
      if (!await dir.exists()) {
        await dir.create();
        log('📁 Created subdirectory: ${dir.path}');
      }
    }

    _staticDir = staticDir;
  }

  /// Получить путь к статической директории
  static Directory _getStaticDirectory() {
    if (_staticDir != null) return _staticDir!;

    // Получаем путь к запускаемому файлу
    final scriptPath = Platform.script.toFilePath();
    final scriptDir = Directory(scriptPath).parent.path;

    return Directory('$scriptDir/$staticDirName');
  }

  /// Получить абсолютный путь к изображению
  ///
  /// Пример: `StaticAssets.image('product.png')` → `/path/.belyash_static/images/product.png`
  static String image(String fileName) {
    final dir = _getStaticDirectory();
    return '${dir.path}/$imagesSubdir/$fileName';
  }

  /// Получить абсолютный путь к видео
  static String video(String fileName) {
    final dir = _getStaticDirectory();
    return '${dir.path}/$videosSubdir/$fileName';
  }

  /// Получить абсолютный путь к документу
  static String document(String fileName) {
    final dir = _getStaticDirectory();
    return '${dir.path}/$documentsSubdir/$fileName';
  }

  /// Получить список всех изображений
  static List<String> listImages() {
    final dir = Directory('${_getStaticDirectory().path}/$imagesSubdir');
    if (!dir.existsSync()) return [];

    return dir
        .listSync()
        .whereType<File>()
        .where((file) {
          final ext = file.path.toLowerCase();
          return ext.endsWith('.jpg') ||
              ext.endsWith('.jpeg') ||
              ext.endsWith('.png') ||
              ext.endsWith('.gif') ||
              ext.endsWith('.webp');
        })
        .map((file) => file.path)
        .toList();
  }

  /// Проверить существование изображения
  ///
  /// Пример: `StaticAssets.hasImage('product.png')` → true/false
  static bool hasImage(String fileName) {
    return File(image(fileName)).existsSync();
  }

  /// Проверить существование видео
  static bool hasVideo(String fileName) {
    return File(video(fileName)).existsSync();
  }

  /// Проверить существование документа
  static bool hasDocument(String fileName) {
    return File(document(fileName)).existsSync();
  }

  /// Получить путь к изображению или пустую строку если не существует
  ///
  /// Удобно для использования в списках с автоматической фильтрацией
  static String imageOrEmpty(String fileName) {
    final path = image(fileName);
    return File(path).existsSync() ? path : '';
  }

  /// Получить путь к видео или пустую строку если не существует
  static String videoOrEmpty(String fileName) {
    final path = video(fileName);
    return File(path).existsSync() ? path : '';
  }

  /// Копировать файл в статическую директорию
  ///
  /// Пример: `StaticAssets.copyToImages('/tmp/photo.png', 'product.png')`
  static Future<String> copyToImages(String sourcePath, String targetName) async {
    await initialize();
    final sourceFile = File(sourcePath);
    final targetPath = image(targetName);
    await sourceFile.copy(targetPath);
    log('📋 Copied $sourcePath → $targetPath');
    return targetPath;
  }

  /// Получить размер файла в байтах
  static int? getFileSize(String filePath) {
    final file = File(filePath);
    return file.existsSync() ? file.lengthSync() : null;
  }

  /// Получить информацию о статической директории
  static Map<String, dynamic> getInfo() {
    final dir = _getStaticDirectory();
    final exists = dir.existsSync();

    if (!exists) {
      return {
        'exists': false,
        'path': dir.path,
      };
    }

    final images = listImages();

    return {
      'exists': true,
      'path': dir.path,
      'images_count': images.length,
      'images': images.map((p) => p.split('/').last).toList(),
    };
  }

  /// Вывести информацию о статических ресурсах в консоль
  static void printInfo() {
    final info = getInfo();
    log('\n📦 Static Assets Info:');
    log('  Path: ${info['path']}');
    log('  Exists: ${info['exists']}');

    if (info['exists'] == true) {
      log('  Images: ${info['images_count']}');
      if (info['images_count'] > 0) {
        for (final img in info['images']) {
          final size = getFileSize(image(img as String));
          final sizeStr = size != null ? '(${(size / 1024).toStringAsFixed(1)} KB)' : '';
          log('    - $img $sizeStr');
        }
      }
    }
    log('');
  }
}
