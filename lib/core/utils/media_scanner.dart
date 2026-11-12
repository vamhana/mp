// |C.1.01.05|Core|Util|Dart|lib/core/utils/media_scanner.dart|D.2.01.02|v.0.0.01|Draft|—|
import 'dart:io' show Platform;
import 'channels.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

/// Обёртка над `MediaScannerConnection.scanFile()` (Android).
/// На прочих платформах — no-op.
class MediaScanner {
  MediaScanner._();
  static const _channel = MethodChannel(AppChannels.mediaScanner);

  /// Принудительно индексирует файлы в MediaStore.
  /// Возвращает количество успешно проиндексированных файлов.
  /// Ошибки канала глушим — сканирование не должно валить syncAll.
  static Future<int> scanFiles(List<String> paths) async {
    if (!Platform.isAndroid) return 0;
    if (paths.isEmpty) return 0;
    try {
      final n = await _channel.invokeMethod<int>('scanFiles', {
        'paths': paths,
      });
      return n ?? 0;
    } on MissingPluginException {
      // На случай запуска на неподходящей сборке (web, старый APK).
      return 0;
    } on PlatformException catch (e) {
      debugPrint('[media_scanner] scanFiles failed: $e');
      return 0;
    }
  }
}