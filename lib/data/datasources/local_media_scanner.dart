// |D.2.01.02|Data|Datasource|Dart|lib/data/datasources/local_media_scanner.dart|D.2.01.01, C.1.01.06|v.0.0.07|Draft|—|
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show PlatformException;
import 'package:on_audio_query/on_audio_query.dart';

import '../../core/utils/messenger_paths.dart';

class LocalMediaScanner {
  final OnAudioQuery _query = OnAudioQuery();

  OnAudioQuery get query => _query;

  static const Set<String> supportedExtensions = {
    '.mp3', '.m4a', '.aac', '.ogg', '.opus', '.wav', '.flac',
    '.amr', '.3gp', '.m4b', '.m4p', '.mp2',
  };

  /// «Музыка» из MediaStore (is_music = 1).
  Future<List<SongModel>> scanAllMp3() async {
    try {
      return await _querySongs();
    } on PlatformException catch (e) {
      if (e.code == 'MissingPermissions') {
        try {
          await _query.permissionsRequest();
        } catch (_) {}
        return await _querySongs();
      }
      rethrow;
    }
  }

  Future<List<SongModel>> _querySongs() async {
    final songs = await _query.querySongs(
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );
    return songs.where(_isSupported).toList();
  }

  Future<List<LocalAudioFile>> scanLocalFiles(Set<String> existingPaths) async {
    final result = <LocalAudioFile>[];
    final seen = <String>{};

    final roots = await _discoverRoots();
    debugPrint('[local-scan] roots: ${roots.length} (${roots.join(", ")})');

    for (final root in roots) {
      try {
        final dir = Directory(root);
        if (!await dir.exists()) {
          debugPrint('[local-scan] skip (not exists) $root');
          continue;
        }
        final before = result.length;
        await _walk(dir, 6, seen, existingPaths, result);
        debugPrint('[local-scan] $root → +${result.length - before} file(s)');
      } catch (e) {
        // Скорее всего Permission denied для Android/media/<чужой.пакет>
        debugPrint('[local-scan] ACCESS ERROR on $root: $e');
      }
    }
    return result;
  }

  Future<void> _walk(
    Directory dir,
    int depth,
    Set<String> seen,
    Set<String> existingPaths,
    List<LocalAudioFile> out,
  ) async {
    if (depth < 0) return;
    try {
      await for (final e in dir.list(followLinks: false)) {
        if (e is File) {
          final p = e.path;
          if (seen.contains(p) || existingPaths.contains(p)) continue;
          seen.add(p);
          if (!_isSupportedPath(p)) continue;

          // Оригиналы из cache/upload MAX: пропускаем кэш и `<id>__`-копии.
          final baseName = p.split(Platform.pathSeparator).last;
          if (MessengerPaths.isLikelyDuplicate(baseName)) {
            debugPrint('[local-scan] skip duplicate: $p');
            continue;
          }

          final meta = _readMeta(p);
          out.add(LocalAudioFile(
            path: p,
            title: meta.title,
            artist: meta.artist,
            album: meta.album,
            durationMs: meta.durationMs,
            coverBytes: meta.coverBytes,
          ));
        } else if (e is Directory) {
          await _walk(e, depth - 1, seen, existingPaths, out);
        }
      }
    } on FileSystemException catch (e) {
      // Permission denied / ENOENT — папка недоступна без MANAGE_EXTERNAL_STORAGE
      debugPrint('[local-scan] walk denied at ${dir.path}: ${e.message}');
    } catch (e) {
      debugPrint('[local-scan] walk failed at ${dir.path}: $e');
    }
  }

  bool _isSupported(SongModel s) {
    final data = s.data.toLowerCase();
    final name = s.displayName.toLowerCase();
    return supportedExtensions.any(
      (ext) => data.endsWith(ext) || name.endsWith(ext),
    );
  }

  bool _isSupportedPath(String path) {
    final lower = path.toLowerCase();
    return supportedExtensions.any((ext) => lower.endsWith(ext));
  }

  /// Публичный вариант `_readMeta` — для импорта из share/view,
  /// где файл лежит во временной папке и в MediaStore его нет.
  Future<LocalAudioFile> readFile(String path) async {
    final meta = _readMeta(path);
    return LocalAudioFile(
      path: path,
      title: meta.title,
      artist: meta.artist,
      album: meta.album,
      durationMs: meta.durationMs,
      coverBytes: meta.coverBytes,
    );
  }

  _LocalMeta _readMeta(String path) {
    try {
      final m = readMetadata(File(path), getImage: true);
      if (m == null) return _LocalMeta(title: _fallbackTitle(path));
      final title = (m.title ?? '').trim();
      final artist = (m.artist ?? '').trim();
      final pictures = m.pictures;
      final cover = pictures.isNotEmpty ? pictures.first.bytes : null;
      return _LocalMeta(
        title: title.isEmpty ? _fallbackTitle(path) : title,
        artist: artist,
        album: m.album,
        durationMs: m.duration?.inMilliseconds ?? 0,
        coverBytes: cover,
      );
    } catch (_) {
      return _LocalMeta(title: _fallbackTitle(path));
    }
  }

  String _fallbackTitle(String path) {
    var name = path.split(Platform.pathSeparator).last;
    name = name.replaceAll(RegExp(r'\.[A-Za-z0-9]+$'), '');
    name = name.replaceFirst(RegExp(r'^-?\d+__'), '');
    return name;
  }

  /// Все папки, где теоретически может лежать аудио.
  ///
  /// Список раньше был в разы короче, чем в `TrackRepository._discoverMediaRoots`,
  /// из-за чего `Android/media/ru.oneme.app` (MAX), `.../com.vkontakte.android`,
  /// `.../ru.ok.android`, `.../org.thoughtcrime.securesms`, `.../com.discord`
  /// не сканировались и аудио оттуда не подхватывалось.
  Future<Set<String>> _discoverRoots() async {
    final rawExternal = <String>{};

    for (final probe in const ['/storage/emulated/0', '/sdcard']) {
      try {
        if (await Directory(probe).exists()) rawExternal.add(probe);
      } catch (_) {}
    }
    try {
      await for (final e
          in Directory('/storage/emulated').list(followLinks: false)) {
        if (e is Directory) rawExternal.add(e.path);
      }
    } catch (_) {}
    try {
      await for (final e in Directory('/storage').list(followLinks: false)) {
        if (e is Directory) {
          final name = e.path.split(Platform.pathSeparator).last;
          if (name != 'emulated' && name != 'self') {
            rawExternal.add(e.path);
          }
        }
      }
    } catch (_) {}

    final externalRoots = <String>{};
    for (final r in rawExternal) {
      try {
        externalRoots.add(await Directory(r).resolveSymbolicLinks());
      } catch (_) {
        externalRoots.add(r);
      }
    }

    return MessengerPaths.discoverAll(externalRoots);
  }

  Future<Uint8List?> loadArtwork(int songId, {int size = 500}) async {
    try {
      return await _query.queryArtwork(
        songId,
        ArtworkType.AUDIO,
        size: size,
        quality: 100,
      );
    } catch (_) {
      return null;
    }
  }
}

class LocalAudioFile {
  final String path;
  final String title;
  final String artist;
  final String? album;
  final int durationMs;
  final Uint8List? coverBytes;

  const LocalAudioFile({
    required this.path,
    required this.title,
    required this.artist,
    this.album,
    required this.durationMs,
    this.coverBytes,
  });
}

class _LocalMeta {
  final String title;
  final String artist;
  final String? album;
  final int durationMs;
  final Uint8List? coverBytes;

  const _LocalMeta({
    required this.title,
    this.artist = '',
    this.album,
    this.durationMs = 0,
    this.coverBytes,
  });
}