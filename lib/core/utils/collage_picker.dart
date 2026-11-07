// |C.1.01.01|Core|Util|Dart|lib/core/utils/collage_picker.dart|—|v.0.0.02|Draft|—|
import 'package:flutter/services.dart';

/// Детерминированно выбирает коллаж из assets/collages/ по seed.
/// Предзагружается через [ensureLoaded] на старте приложения.
class CollagePicker {
  CollagePicker._();
  static final CollagePicker instance = CollagePicker._();

  List<String> _assets = const [];
  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      _assets = manifest
          .listAssets()
          .where((a) => a.startsWith('assets/collages/'))
          .where((a) {
            final l = a.toLowerCase();
            return l.endsWith('.jpg') ||
                l.endsWith('.jpeg') ||
                l.endsWith('.png') ||
                l.endsWith('.webp');
          })
          .toList(growable: false);
    } catch (_) {
      _assets = const [];
    }
    _loaded = true;
  }

  /// Синхронно возвращает путь к коллажу или null, если папка пуста.
  String? pick(String seed) {
    if (_assets.isEmpty) return null;
    return _assets[_fnv1a(seed) % _assets.length];
  }

  /// Стабильный FNV-1a 32-bit хеш.
  /// `String.hashCode` в Dart не гарантирован между версиями SDK и
  /// платформами — коллаж мог бы «прыгать» после обновления Flutter.
  int _fnv1a(String s) {
    var hash = 0x811c9dc5;
    for (var i = 0; i < s.length; i++) {
      hash ^= s.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }
}