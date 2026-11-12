// |C.1.01.03|Core|Util|Dart|lib/core/utils/track_sharer.dart|D.2.02.01|v.0.0.02|Draft|—|
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/models/track.dart';

class TrackSharer {
  TrackSharer._();

  static const int maxTracks = 10;

  static Future<void> share(List<Track> tracks) async {
    if (tracks.isEmpty) return;

    final take = tracks.take(maxTracks).toList(growable: false);

    // Готовим временную папку. Копируем туда файлы под человеческим
    // именем (из тегов), потому что в приватном хранилище они лежат
    // как "<mediaStoreId>__<originalName>.mp3" — этот префикс иначе
    // видит получатель в мессенджере.
    final tempRoot = await getTemporaryDirectory();
    final shareDir = Directory(p.join(tempRoot.path, 'mp_share'));
    // Чистим хвосты прошлой отправки (не удаляем сразу после share,
    // чтобы не гонки с получателем, который ещё читает файл).
    if (await shareDir.exists()) {
      try {
        await shareDir.delete(recursive: true);
      } catch (_) {}
    }
    await shareDir.create(recursive: true);

    final files = <XFile>[];
    final taken = <Track>[];

    for (final t in take) {
      final src = File(t.filePath);
      if (!await src.exists()) continue;

      final cleanName = _buildFileName(t);
      final dest = File(p.join(shareDir.path, cleanName));
      try {
        await src.copy(dest.path);
      } catch (_) {
        continue;
      }
      files.add(XFile(dest.path, mimeType: _mimeType(t.filePath)));
      taken.add(t);
    }

    if (files.isEmpty) return;

    final text = files.length == 1
        ? '${taken.first.displayTitle} — ${taken.first.displayArtist}'
        : '${files.length} треков из MP';

    await Share.shareXFiles(
      files,
      subject: files.length == 1 ? taken.first.displayTitle : 'MP',
      text: text,
    );
  }

  /// Только "Название.ext" — без исполнителя и без префикса "<id>__".
  static String _buildFileName(Track t) {
    var title = t.title.trim();
    var ext = _extOf(t.filePath);
    if (ext.isEmpty) ext = '.mp3';

    if (title.isEmpty) {
      var base = p.basenameWithoutExtension(t.filePath);
      base = base.replaceFirst(RegExp(r'^-?\d+__'), '');
      title = base;
    }

    final safe = title.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_');
    final trimmed = safe.length > 120 ? safe.substring(0, 120) : safe;
    return '${trimmed.isEmpty ? 'track' : trimmed}$ext';
  }

  static String _extOf(String path) {
    final i = path.lastIndexOf('.');
    if (i < 0 || i == path.length - 1) return '';
    return path.substring(i).toLowerCase();
  }

  static String _mimeType(String path) {
    switch (_extOf(path)) {
      case '.mp3':
        return 'audio/mpeg';
      case '.m4a':
        return 'audio/mp4';
      case '.aac':
        return 'audio/aac';
      case '.ogg':
        return 'audio/ogg';
      case '.opus':
        return 'audio/opus';
      case '.wav':
        return 'audio/wav';
      case '.flac':
        return 'audio/flac';
      default:
        return 'audio/*';
    }
  }
}