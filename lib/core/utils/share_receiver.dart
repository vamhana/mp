// |C.1.01.07|Core|Util|Dart|lib/core/utils/share_receiver.dart|—|v.0.0.01|Draft|—|
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

import 'channels.dart';

class IncomingAudio {
  final String path;
  final bool playImmediately;
  const IncomingAudio({required this.path, required this.playImmediately});
}

/// Мост к MainActivity.kt: принимает файлы из ACTION_SEND / ACTION_VIEW.
class ShareReceiver {
  ShareReceiver._();
  static const _channel = MethodChannel(AppChannels.share);

  /// Регистрирует обработчик новых входящих файлов.
  /// Вызывать один раз после того, как Flutter готов принимать файлы.
  static void init(void Function(IncomingAudio) onFile) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onSharedFile') {
        final map = call.arguments;
        if (map is Map && map['path'] is String) {
          onFile(IncomingAudio(
            path: map['path'] as String,
            playImmediately: map['playImmediately'] == true,
          ));
        }
      }
      return null;
    });
  }

  /// Забрать файл, пришедший до готовности Dart (холодный старт или
  /// `onNewIntent` без зарегистрированного обработчика).
  static Future<IncomingAudio?> takePending() async {
    try {
      final map = await _channel.invokeMethod<Map>('getPendingFile');
      if (map is Map && map['path'] is String) {
        return IncomingAudio(
          path: map['path'] as String,
          playImmediately: map['playImmediately'] == true,
        );
      }
    } catch (e) {
      debugPrint('[share] takePending failed: $e');
    }
    return null;
  }

  static Future<void> openDefaultAppsSettings() async {
    try {
      await _channel.invokeMethod('openDefaultAppsSettings');
    } catch (e) {
      debugPrint('[share] openDefaultAppsSettings failed: $e');
    }
  }

  static Future<void> openMediaChooser() async {
    try {
      await _channel.invokeMethod('openMediaChooser');
    } catch (e) {
      debugPrint('[share] openMediaChooser failed: $e');
    }
  }
}