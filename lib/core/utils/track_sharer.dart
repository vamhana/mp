// |C.1.01.03|Core|Util|Dart|lib/core/utils/track_sharer.dart|D.2.02.01|v.0.0.01|Draft|—|
import 'package:share_plus/share_plus.dart';

import '../../data/models/track.dart';

/// Открывает системный диалог «Поделиться» (Android Share Sheet).
/// В диалоге автоматически показываются установленные мессенджеры
/// и «недавние контакты» (Direct Share), поддерживающие ACTION_SEND.
class TrackSharer {
  TrackSharer._();

  /// Максимум треков для отправки за один раз.
  static const int maxTracks = 10;

  static Future<void> share(List<Track> tracks) async {
    if (tracks.isEmpty) return;

    final take = tracks.take(maxTracks).toList(growable: false);
    final files = take
        .map((t) => XFile(t.filePath, mimeType: 'audio/mpeg'))
        .toList(growable: false);

    if (files.isEmpty) return;

    final text = files.length == 1
        ? '${take.first.displayTitle} — ${take.first.displayArtist}'
        : '${files.length} треков из MP';

    await Share.shareXFiles(
      files,
      subject: files.length == 1 ? take.first.displayTitle : 'MP',
      text: text,
    );
  }
}