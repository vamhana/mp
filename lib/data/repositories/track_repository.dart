// |D.2.03.01|Data|Repository|Dart|lib/data/repositories/track_repository.dart|D.2.01.01, D.2.01.02, D.2.01.03, D.2.02.01|v.0.0.02|Draft|—|
import 'dart:io';
import 'package:on_audio_query/on_audio_query.dart';

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

  Future<List<Track>> getAllTracks() => db.getAll();

  Future<int> syncAll({void Function(SyncProgress)? onProgress}) async {
    final songs = await scanner.scanAllMp3();
    if (songs.isEmpty) {
      onProgress?.call(const SyncProgress(
        current: 0, total: 0, fileName: '', done: true,
      ));
      return 0;
    }

    final toAdd = <SongModel>[];
    for (final s in songs) {
      // Пропускаем фантомы MediaStore: файла нет — не добавляем.
      if (s.data.isEmpty) continue;
      if (!await File(s.data).exists()) continue;

      if (!await db.exists(s.id)) toAdd.add(s);
    }

    if (toAdd.isEmpty) {
      onProgress?.call(const SyncProgress(
        current: 0, total: 0, fileName: '', done: true,
      ));
      return 0;
    }

    var added = 0;
    var current = 0;
    var nextIndex = await db.nextOrderIndex();

    for (final s in toAdd) {
      current++;
      onProgress?.call(SyncProgress(
        current: current,
        total: toAdd.length,
        fileName: s.displayName,
      ));

      try {
        final sourcePath = s.data;
        if (sourcePath.isEmpty) continue;

        final fileName = s.displayName.isNotEmpty
            ? s.displayName
            : '${s.id}.mp3';
        final copiedPath = await copier.copyMp3(
          mediaStoreId: s.id,
          sourcePath: sourcePath,
          originalName: fileName,
        );

        final art = await scanner.loadArtwork(s.id);
        final coverPath = await copier.saveCover(art, s.id);

        final track = Track(
          mediaStoreId: s.id,
          title: s.title,
          artist: s.artist ?? '',
          album: s.album,
          durationMs: s.duration ?? 0,
          filePath: copiedPath,
          coverPath: coverPath,
          orderIndex: nextIndex++,
        );
        await db.insert(track);
        added++;
      } catch (e) {
        // ignore: avoid_print
        print('Ошибка при копировании ${s.displayName}: $e');
      }
    }

    onProgress?.call(SyncProgress(
      current: current,
      total: toAdd.length,
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
}
