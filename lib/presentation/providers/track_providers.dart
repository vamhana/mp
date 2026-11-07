// |P.3.01.02|Presentation|Provider|Dart|lib/presentation/providers/track_providers.dart|D.2.01.01, D.2.01.02, D.2.01.03, D.2.02.01, D.2.03.01|v.0.0.01|Draft|—|
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/file_copier.dart';
import '../../data/datasources/local_media_scanner.dart';
import '../../data/datasources/track_database.dart';
import '../../data/models/track.dart';
import '../../data/repositories/track_repository.dart';

final trackDatabaseProvider = Provider<TrackDatabase>((_) => TrackDatabase());
final mediaScannerProvider = Provider<LocalMediaScanner>((_) => LocalMediaScanner());
final fileCopierProvider = Provider<FileCopier>((_) => FileCopier());

final trackRepositoryProvider = Provider<TrackRepository>((ref) {
  return TrackRepository(
    db: ref.watch(trackDatabaseProvider),
    scanner: ref.watch(mediaScannerProvider),
    copier: ref.watch(fileCopierProvider),
  );
});

/// Список треков (обновляется через `ref.invalidate`).
final tracksProvider = FutureProvider<List<Track>>((ref) {
  return ref.watch(trackRepositoryProvider).getAllTracks();
});

/// Прогресс текущей синхронизации (null = нет активной синхронизации).
final syncProgressProvider = StateProvider<SyncProgress?>((_) => null);
