// |D.2.01.04|Data|Datasource|Dart|lib/data/datasources/bundled_tracks_seeder.dart|D.2.01.01, D.2.01.03, D.2.02.01|v.0.0.01|Draft|—|
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';
import 'file_copier.dart';
import 'track_database.dart';

/// Копирует MP3 из `assets/preinstalled/` в приватное хранилище
/// и вставляет их в БД как «стартовый плейлист».
///
/// Логика:
/// - При каждом запуске перечисляет `assets/preinstalled/*.mp3`
/// - Для каждого проверяет `db.exists(-1..-N)` → создаёт только недостающие
/// - Idempotent: если пользователь удалил трек из UI — он не вернётся
///   (потому что `db.exists` вернёт false, но `prefs`-флаг будет true)
/// - Флаг `bundled_tracks_seeded_v1` ставится **только** если
///   хотя бы один трек был успешно вставлен. Пустая папка → retry.
class BundledTracksSeeder {
  BundledTracksSeeder._();
  static final BundledTracksSeeder instance = BundledTracksSeeder._();

  static const _seededKey = 'bundled_tracks_seeded_v2';
  static const _assetPrefix = 'assets/preinstalled/';
  static const int _maxBundled = 50;

  /// Возвращает количество добавленных треков.
  ///
  /// [force] — сбросить флаг и попробовать заново (для отладки).
  Future<int> seedIfNeeded({
    required TrackDatabase db,
    required FileCopier copier,
    bool force = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    if (force) {
      await prefs.remove(_seededKey);
      debugPrint('[seeder] force reset — re-seeding');
    }

    if (prefs.getBool(_seededKey) == true) {
      debugPrint('[seeder] skip — flag already set');
      return 0;
    }

    try {
      final assets = await _listBundledMp3();
      debugPrint('[seeder] found ${assets.length} bundled MP3(s)');
      if (assets.isEmpty) {
        // Не ставим флаг — вдруг файлы появятся после следующего билда.
        return 0;
      }

      var inserted = 0;
      var nextIndex = await db.nextOrderIndex();
      // Уникальные fakeId для новых треков; старые не трогаем.
      var nextFakeId = -DateTime.now().millisecondsSinceEpoch;

      for (final asset in assets.take(_maxBundled)) {
        final filename = asset.split('/').last;

        // Идемпотентность по имени файла, не по позиции в списке.
        // Позиционный fakeId ломался при добавлении новых песен: сдвиг
        // индексов → старые записи «закрывали» слоты новых.
        if (await db.existsByOriginalName(filename)) {
          debugPrint('[seeder] skip existing "$filename"');
          continue;
        }

        try {
          final bytes = await _loadAsset(asset);
          if (bytes.isEmpty) {
            debugPrint('[seeder] empty asset: $asset');
            continue;
          }

          final fakeId = nextFakeId--;

          final destFile = await _writeToPrivateStorage(
            copier: copier,
            bytes: bytes,
            mediaStoreId: fakeId,
            filename: filename,
          );

          final meta = _readMetadata(destFile, fallbackTitle: filename);
          final coverPath = meta.coverBytes != null
              ? await copier.saveCover(meta.coverBytes, fakeId)
              : null;

          final track = Track(
            mediaStoreId: fakeId,
            title: meta.title,
            artist: meta.artist,
            album: meta.album,
            durationMs: meta.durationMs,
            filePath: destFile.path,
            coverPath: coverPath,
            orderIndex: nextIndex++,
          );

          await db.insert(track);
          inserted++;
          debugPrint(
            '[seeder] + $asset → id=$fakeId, "${meta.title}" / "${meta.artist}"',
          );
        } catch (e) {
          debugPrint('[seeder] ERROR on $asset: $e');
        }
      }

      if (inserted > 0) {
        await prefs.setBool(_seededKey, true);
        debugPrint('[seeder] done, inserted $inserted');
      } else if (assets.isNotEmpty) {
        // Ассеты есть, но ничего не вставили — возможно все битые.
        // Не ставим флаг, чтобы была следующая попытка после обновления файлов.
        debugPrint('[seeder] nothing inserted, flag NOT set (retry next run)');
      }
      return inserted;
    } catch (e) {
      debugPrint('[seeder] fatal: $e');
      return 0;
    }
  }

  // --- Внутреннее ---

  Future<List<String>> _listBundledMp3() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final list = manifest
        .listAssets()
        .where((a) => a.startsWith(_assetPrefix))
        .where((a) => a.toLowerCase().endsWith('.mp3'))
        .toList()
      ..sort();
    return list;
  }

  Future<Uint8List> _loadAsset(String asset) async {
    final data = await rootBundle.load(asset);
    return data.buffer.asUint8List();
  }

  Future<File> _writeToPrivateStorage({
    required FileCopier copier,
    required Uint8List bytes,
    required int mediaStoreId,
    required String filename,
  }) async {
    final dir = await copier.mp3Dir;
    final file = File('${dir.path}/${mediaStoreId}__$filename');
    if (!await file.exists()) {
      await file.writeAsBytes(bytes, flush: true);
    }
    return file;
  }

  _BundledMeta _readMetadata(File file, {required String fallbackTitle}) {
    final fallback = fallbackTitle
        .replaceAll(RegExp(r'\.mp3$', caseSensitive: false), '');

    try {
      final m = readMetadata(file, getImage: true);
      if (m == null) return _BundledMeta(title: fallback, artist: '');

      final title = (m.title ?? '').trim();
      final artist = (m.artist ?? '').trim();
      final pictures = m.pictures;
      final cover = pictures.isNotEmpty ? pictures.first.bytes : null;

      return _BundledMeta(
        title: title.isEmpty ? fallback : title,
        artist: artist,
        album: m.album,
        durationMs: m.duration?.inMilliseconds ?? 0,
        coverBytes: cover,
      );
    } catch (e) {
      debugPrint('[seeder] readMetadata error on ${file.path}: $e');
      return _BundledMeta(title: fallback, artist: '');
    }
  }
}

class _BundledMeta {
  final String title;
  final String artist;
  final String? album;
  final int durationMs;
  final Uint8List? coverBytes;

  const _BundledMeta({
    required this.title,
    required this.artist,
    this.album,
    this.durationMs = 0,
    this.coverBytes,
  });
}