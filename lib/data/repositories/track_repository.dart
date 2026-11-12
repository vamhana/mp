// |D.2.03.01|Data|Repository|Dart|lib/data/repositories/track_repository.dart|D.2.01.01, D.2.01.02, D.2.01.03, D.2.02.01|v.0.0.10|Draft|—|
import 'dart:io';
import 'package:on_audio_query/on_audio_query.dart';

import '../../core/utils/messenger_paths.dart';
import '../../core/utils/media_scanner.dart';
import '../../core/utils/permissions.dart';
import '../datasources/file_copier.dart';
import '../datasources/local_media_scanner.dart';
import '../datasources/track_database.dart';
import '../models/track.dart';

class SyncProgress {
  final int current;
  final int total;
  final String fileName;
  final bool done;
  final String? error;

  const SyncProgress({
    required this.current,
    required this.total,
    required this.fileName,
    this.done = false,
    this.error,
  });

  double get fraction => total == 0 ? 1 : current / total;
}

class TrackRepository {
  TrackRepository({
    required this.db,
    required this.scanner,
    required this.copier,
  });

  final TrackDatabase db;
  final LocalMediaScanner scanner;
  final FileCopier copier;

  final Set<String> _scannedPaths = {};

  Future<List<Track>> getAllTracks() => db.getAll();

  /// Импорт одного файла из share/view. Возвращает Track с уже
  /// проставленным `id` (иначе IncomingShareHandler не сможет найти
  /// его в списке для автозапуска).
  Future<Track?> importLocalFile(String sourcePath) async {
    try {
      final file = File(sourcePath);
      if (!await file.exists()) return null;

      final meta = await scanner.readFile(sourcePath);
      final localId = -DateTime.now().microsecondsSinceEpoch;

      // Сохраняем оригинальное имя с расширением — это формат-хинт
      // для just_audio и человеческое имя в настройках.
      final baseName = sourcePath.split(Platform.pathSeparator).last;
      final fileName = baseName.isNotEmpty ? baseName : '${meta.title}.mp3';

      final copiedPath = await copier.copyMp3(
        mediaStoreId: localId,
        sourcePath: sourcePath,
        originalName: fileName,
      );

      String? coverPath;
      if (meta.coverBytes != null) {
        coverPath = await copier.saveCover(meta.coverBytes!, localId);
      }

      final track = Track(
        mediaStoreId: localId,
        title: meta.title,
        artist: meta.artist,
        album: meta.album,
        durationMs: meta.durationMs,
        filePath: copiedPath,
        coverPath: coverPath,
        orderIndex: await db.nextOrderIndex(),
      );
      final newId = await db.insert(track);
      return track.copyWith(id: newId);
    } catch (e) {
      // ignore: avoid_print
      print('[import] failed for $sourcePath: $e');
      return null;
    }
  }

  Future<int> syncAll({void Function(SyncProgress)? onProgress}) async {
    // ── Этап 1. Медиатека (MediaStore) ────────────────────────────────
    await _kickMediaStore();

    final audio = await scanner.scanAllMp3();
    final toAdd = <SongModel>[];
    for (final a in audio) {
      if (a.data.isEmpty) continue;
      if (await _resolveRealPath(a.data) == null) continue;
      if (!await db.exists(a.id)) toAdd.add(a);
    }

    // ── Этап 2. Локальные файлы в известных папках ────────────────────
    final existingPaths =
        (await db.getAll()).map((t) => t.filePath).toSet();
    final localFiles = await scanner.scanLocalFiles(existingPaths);

    final total = toAdd.length + localFiles.length;
    if (total == 0) {
      onProgress?.call(const SyncProgress(
        current: 0, total: 0, fileName: '', done: true,
      ));
      return 0;
    }

    var added = 0;
    var current = 0;
    var nextIndex = await db.nextOrderIndex();

    var nextLocalId = -DateTime.now().millisecondsSinceEpoch;

    // ── Обработка аудио из MediaStore ────────────────────────────────
    for (final a in toAdd) {
      current++;
      onProgress?.call(SyncProgress(
        current: current,
        total: total,
        fileName: a.displayName,
      ));

      try {
        final sourcePath = await _resolveRealPath(a.data) ?? a.data;
        if (sourcePath.isEmpty) continue;

        final fileName = a.displayName.isNotEmpty
            ? a.displayName
            : '${a.id}.mp3';
        final copiedPath = await copier.copyMp3(
          mediaStoreId: a.id,
          sourcePath: sourcePath,
          originalName: fileName,
        );

        final art = await scanner.loadArtwork(a.id);
        final coverPath = await copier.saveCover(art, a.id);

        final track = Track(
          mediaStoreId: a.id,
          title: a.title,
          artist: a.artist ?? '',
          album: a.album,
          durationMs: a.duration ?? 0,
          filePath: copiedPath,
          coverPath: coverPath,
          orderIndex: nextIndex++,
        );
        await db.insert(track);
        added++;
      } catch (e) {
        // ignore: avoid_print
        print('Ошибка при копировании ${a.displayName}: $e');
      }
    }

    // ── Обработка локальных файлов ───────────────────────────────────
    for (final lf in localFiles) {
      current++;
      onProgress?.call(SyncProgress(
        current: current,
        total: total,
        fileName: lf.title,
      ));

      final localId = nextLocalId--;

      try {
        final copiedPath = await copier.copyMp3(
          mediaStoreId: localId,
          sourcePath: lf.path,
          originalName: lf.title,
        );

        String? coverPath;
        if (lf.coverBytes != null) {
          coverPath = await copier.saveCover(lf.coverBytes, localId);
        }

        final track = Track(
          mediaStoreId: localId,
          title: lf.title,
          artist: lf.artist,
          album: lf.album,
          durationMs: lf.durationMs,
          filePath: copiedPath,
          coverPath: coverPath,
          orderIndex: nextIndex++,
        );
        await db.insert(track);
        added++;
      } catch (e) {
        // ignore: avoid_print
        print('Ошибка при копировании локального файла ${lf.path}: $e');
      }
    }

    onProgress?.call(SyncProgress(
      current: current,
      total: total,
      fileName: '',
      done: true,
    ));
    return added;
  }

  Future<void> deleteTrack(Track track) async {
    if (track.id != null) await db.deleteById(track.id!);
    await copier.deleteFileQuietly(track.filePath);
    await copier.deleteFileQuietly(track.coverPath);
  }

  Future<void> moveUp(Track track, List<Track> currentList) =>
      _move(track, currentList, -1);

  Future<void> moveDown(Track track, List<Track> currentList) =>
      _move(track, currentList, 1);

  Future<void> _move(Track track, List<Track> currentList, int delta) async {
    final idx = currentList.indexWhere((t) => t.id == track.id);
    final target = idx + delta;
    if (idx < 0 || target < 0 || target >= currentList.length) return;
    final list = List<Track>.from(currentList);
    final item = list.removeAt(idx);
    list.insert(target, item);
    await db.rewriteOrder(list);
  }

  // --- Догоняющее сканирование ---

  Future<void> _kickMediaStore() async {
    if (!Platform.isAndroid) return;

    final hasAllFiles = await hasManageExternalStorage();
    if (!hasAllFiles) {
      // ignore: avoid_print
      print('[sync] MANAGE_EXTERNAL_STORAGE не выдан — '
          'Android/data/* недоступен, но Android/media/, Download/ и Music/ работают');
    }

    final roots = await _discoverMediaRoots();
    if (roots.isEmpty) return;

    // ignore: avoid_print
    print('[sync] roots: $roots');

    final candidates = await _collectCandidates(roots);
    if (candidates.isEmpty) return;

    // ignore: avoid_print
    print('[sync] kicking MediaStore for ${candidates.length} file(s) '
        'across ${roots.length} root(s)');

    final scanned = await MediaScanner.scanFiles(candidates);

    for (final path in candidates) {
      if (_scannedPaths.contains(path)) continue;
      try {
        await scanner.query.scanMedia(path);
      } catch (_) {}
    }

    if (scanned > 0) {
      _scannedPaths.addAll(candidates);
    } else {
      // ignore: avoid_print
      print('[sync] MediaScanner вернул 0 — повторим в следующий раз');
    }
  }

  Future<String?> _resolveRealPath(String path) async {
    if (path.isEmpty) return null;
    try {
      if (await File(path).exists()) return path;
    } catch (_) {}
    try {
      final decoded = Uri.decodeFull(path);
      if (decoded != path && await File(decoded).exists()) return decoded;
    } catch (_) {}
    return null;
  }

  Future<Set<String>> _discoverMediaRoots() async {
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

  Future<List<String>> _collectCandidates(Set<String> roots) async {
    const skipExtensions = <String>{
      '.jpg', '.jpeg', '.png', '.gif', '.webp', '.heic', '.heif',
      '.bmp', '.svg', '.ico', '.tiff', '.tif',
      '.mp4', '.mkv', '.webm', '.avi', '.mov', '.wmv', '.flv',
      '.m4v', '.mpg', '.mpeg', '.vob',
      '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx',
      '.txt', '.zip', '.rar', '.7z', '.tar', '.gz',
      '.apk', '.exe', '.dll', '.so', '.vcf', '.gpx', '.json',
      '.xml', '.html', '.css', '.js',
    };

    final candidates = <String>[];
    final seen = <String>{};

    Future<void> walk(Directory dir, int depth) async {
      if (depth < 0) return;
      try {
        await for (final e in dir.list(followLinks: false)) {
          if (e is File) {
            final p = e.path;
            if (_scannedPaths.contains(p)) continue;
            if (!seen.add(p)) continue;
            final lower = p.toLowerCase();
            if (skipExtensions.any((ext) => lower.endsWith(ext))) continue;
            candidates.add(p);
          } else if (e is Directory) {
            await walk(e, depth - 1);
          }
        }
      } catch (e) {
        // ignore: avoid_print
        print('[sync] walk failed at ${dir.path}: $e');
      }
    }

    for (final root in roots) {
      try {
        final dir = Directory(root);
        if (!await dir.exists()) continue;
        await walk(dir, 6);
      } catch (e) {
        // ignore: avoid_print
        print('[sync] root skipped $root: $e');
      }
    }

    return candidates;
  }
}