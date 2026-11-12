// |C.1.01.03|Core|Util|Dart|lib/core/utils/track_sharer.dart|D.2.02.01|v.0.0.04|Draft|—|
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/models/track.dart';

class TrackSharer {
  TrackSharer._();

  static const int maxTracks = 10;

  /// Возвращает true, если системный диалог «Поделиться» был показан.
  /// false — если шарить нечего (нет файлов) или share_plus упал.
  static Future<bool> share(List<Track> tracks) async {
    if (tracks.isEmpty) return false;

    final take = tracks.take(maxTracks).toList(growable: false);

    // Готовим временную папку. Копируем туда файлы под человеческим
    // именем (из тегов), потому что в приватном хранилище они лежат
    // как "<mediaStoreId>__<originalName>.mp3" — этот префикс иначе
    // видит получатель в мессенджере.
    final tempRoot = await getTemporaryDirectory();
    final shareDir = Directory(p.join(tempRoot.path, 'mp_share'));
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
      final exists = await src.exists();
      debugPrint(
        '[share] id=${t.id} msId=${t.mediaStoreId} '
        'exists=$exists path=${t.filePath}',
      );
      if (!exists) continue;

      final cleanName = _buildFileName(t);
      final dest = File(p.join(shareDir.path, cleanName));
      try {
        await src.copy(dest.path);
      } catch (e) {
        debugPrint('[share] copy failed ${src.path} → ${dest.path}: $e');
        continue;
      }
      files.add(XFile(dest.path, mimeType: _mimeType(t.filePath)));
      taken.add(t);
    }

    debugPrint('[share] prepared ${files.length}/${take.length} files');

    if (files.isEmpty) {
      debugPrint('[share] no files to share (sources missing?)');
      return false;
    }

    final text = files.length == 1
        ? '${taken.first.displayTitle} — ${taken.first.displayArtist}'
        : '${files.length} треков из MP';

    try {
      await Share.shareXFiles(
        files,
        subject: files.length == 1 ? taken.first.displayTitle : 'MP',
        text: text,
      );
      return true;
    } catch (e) {
      debugPrint('[share] shareXFiles failed: $e');
      return false;
    }
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

  /// Возвращает расширение файла или пустую строку.
  ///
  /// Берёт только последний сегмент пути, чтобы точки в именах папок
  /// (`com.example.mp`) не путались с расширением. Валидное расширение —
  /// короткое, только буквы/цифры, начинается с точки. Всё остальное
  /// (например, `.mp/app_flutter/...`) — не расширение, отбрасываем.
  ///
  /// ВАЖНО: этот метод ДОЛЖЕН быть объявлен ровно один раз в классе.
  static String _extOf(String path) {
    final base = path.split(RegExp(r'[\\/]')).last;
    final i = base.lastIndexOf('.');
    if (i <= 0 || i == base.length - 1) return '';
    final ext = base.substring(i).toLowerCase();
    if (!RegExp(r'^\.[a-z0-9]{1,6}$').hasMatch(ext)) return '';
    return ext;
  }

  /// Никогда не возвращаем audio/* — на Android share_plus на
  /// wildcard-MIME молча падает без исключения. Если расширение
  /// неизвестно (старые треки, импортированные как тег без .ext),
  /// отдаём audio/mpeg — это самый совместимый fallback.
  static String _mimeType(String path) {
    switch (_extOf(path)) {
      case '.mp3':
      case '.mp2':
        return 'audio/mpeg';
      case '.m4a':
      case '.m4b':
      case '.m4p':
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
      case '.amr':
        return 'audio/amr';
      case '.3gp':
        return 'audio/3gpp';
      default:
        return 'audio/mpeg';
    }
  }
}