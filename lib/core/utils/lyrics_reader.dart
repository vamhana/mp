// |C.1.01.04|Core|Util|Dart|lib/core/utils/lyrics_reader.dart|—|v.0.0.01|Draft|—|
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

/// Читает текст песни из ID3-тега (USLT) MP3-файла.
/// Возвращает null, если файла нет, тег битый или текста нет.
class LyricsReader {
  LyricsReader._();

  static Future<String?> read(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return null;

    try {
      final metadata = readMetadata(file, getImage: false);
      final lyrics = metadata?.lyrics;
      if (lyrics == null) return null;
      final trimmed = lyrics.trim();
      return trimmed.isEmpty ? null : trimmed;
    } catch (_) {
      return null;
    }
  }
}