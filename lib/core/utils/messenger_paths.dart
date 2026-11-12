// |C.1.01.06|Core|Util|Dart|lib/core/utils/messenger_paths.dart|—|v.0.0.05|Draft|—|
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;

class MessengerPaths {
  MessengerPaths._();

  static const packages = <String>[
    'com.whatsapp', 'com.whatsapp.w4b',
    'org.telegram.messenger', 'org.telegram.plus',
    'org.telegram.messenger.web', 'org.telegram.BifToGram',
    'org.thunderdog.challegram',
    'com.viber.voip', 'org.thoughtcrime.securesms', 'com.discord',
    'ru.oneme.app', 'ru.oneme', 'ru.max', 'ru.max.messenger',
    'com.max', 'com.max.messenger',
    'ru.ok.android', 'com.vkontakte.android',
    'com.snapchat.android', 'com.facebook.orca',
    'com.instagram.android', 'com.linkedin.android',
    'com.microsoft.teams', 'com.slack',
  ];

  static const sharedSubdirs = <String>[
    'Download', 'Downloads', 'Music',
    'WhatsApp/Media', 'WhatsApp/Media/WhatsApp Audio',
    'WhatsApp/Media/WhatsApp Voice Notes', 'WhatsApp/Media/WhatsApp Audio/Sent',
    'Music/WhatsApp Audio',
    'Telegram', 'Telegram/Telegram Audio', 'Music/Telegram',
    'Documents/Telegram',
    'Viber', 'Signal',
    'Music/MAX', 'Music/Max', 'Music/MAX/audio',
    'MAX', 'Download/MAX', 'Pictures/MAX', 'Movies/MAX',
    'Documents/MAX', 'Documents/MAX/audio',
  ];

  /// Подпапки в `Android/data/<pkg>/`, где мессенджеры складывают аудио.
  /// На большинстве Android 11+ недоступны приложению, но пробуем:
  /// на старых прошивках / с root может прочитаться.
  ///
  /// `cache/upload` у MAX содержит и «оригиналы» (`Мама.mp3`), и
  /// «обработанные» (`1000029392__Вежливые слова.mp3`), и мусор
  /// (`content__com.android...`). Дубли отфильтруем ниже по имени.
  static const restrictedDataSubdirs = <String>[
    'cache/upload',
    'cache/upload/audio',
    'files/audio',
    'files/media/audio',
    'files/Downloads',
  ];

  static const nameHints = <String>[
    'telegram', 'whatsapp', 'viber', 'signal', 'discord',
    'vkontakte', 'vk', 'ok', 'youtube', 'messenger', 'snapchat',
    'max', 'oneme', 'element', 'threema', 'wechat', 'line',
    'challegram', 'thunder', 'bifto',
  ];

  /// Имена, которые являются копиями/кэшем, а не оригиналами.
  /// `content__...` — DocumentProvider-кэш MAX.
  /// `123456__name.mp3` — обработанная копия, часто дублирует `name.mp3`.
  static bool isLikelyDuplicate(String fileName) {
    if (fileName.toLowerCase().startsWith('content__')) return true;
    final m = RegExp(r'^(-?\d+)__').firstMatch(fileName);
    if (m != null) {
      final id = int.tryParse(m.group(1) ?? '0') ?? 0;
      // Для MAX отрицательные id не используются, а положительные — это
      // уже MediaStore-копия, оригинал обычно рядом без префикса.
      if (id > 0) return true;
    }
    return false;
  }

  static Future<Set<String>> discoverAll(
    Iterable<String> externalRoots,
  ) async {
    final roots = <String>{};
    final discoveredPackages = <String>[];
    final visibleRestricted = <String>[];

    for (final ext in externalRoots) {
      // 1. Общие подпапки.
      for (final sub in sharedSubdirs) {
        final p = '$ext/$sub';
        try {
          if (await Directory(p).exists()) roots.add(p);
        } catch (_) {}
      }

      // 2. Android/media/<pkg>.
      for (final pkg in packages) {
        final p = '$ext/Android/media/$pkg';
        try {
          if (await Directory(p).exists()) roots.add(p);
        } catch (_) {}
      }

      // 3. Android/data/<pkg>/… — обычно невидимо. Пробуем.
      for (final pkg in packages) {
        for (final sub in restrictedDataSubdirs) {
          final p = '$ext/Android/data/$pkg/$sub';
          try {
            if (await Directory(p).exists()) {
              roots.add(p);
              visibleRestricted.add(p);
            }
          } catch (_) {}
        }
      }

      // 4. Android/media/* — все подпапки.
      final mediaRoot = Directory('$ext/Android/media');
      try {
        if (await mediaRoot.exists()) {
          await for (final e in mediaRoot.list(followLinks: false)) {
            if (e is Directory) {
              roots.add(e.path);
              discoveredPackages.add(e.path.split('/').last);
            }
          }
        }
      } catch (_) {}

      // 5. Эвристика по именам.
      try {
        await for (final e in Directory(ext).list(followLinks: false)) {
          if (e is! Directory) continue;
          final name =
              e.path.split(Platform.pathSeparator).last.toLowerCase();
          if (nameHints.any(name.contains)) roots.add(e.path);
        }
      } catch (_) {}
    }

    debugPrint(
      '[messenger-paths] Android/media packages: $discoveredPackages',
    );
    debugPrint(
      '[messenger-paths] Android/data/<pkg>/…: видны ${visibleRestricted.length}'
      '${visibleRestricted.isNotEmpty ? " ($visibleRestricted)" : ""}',
    );
    return roots;
  }
}