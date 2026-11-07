import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;
import 'package:on_audio_query/on_audio_query.dart';

class LocalMediaScanner {
  final OnAudioQuery _query = OnAudioQuery();

  OnAudioQuery get query => _query;

  Future<List<SongModel>> scanAllMp3() async {
    try {
      return await _queryOnce();
    } on PlatformException catch (e) {
      // on_audio_query 2.9.0 может бросать MissingPermissions, даже если
      // permission_handler считает, что разрешение выдано (race на Samsung).
      // Просим разрешение напрямую у плагина и повторяем ОДИН раз.
      if (e.code == 'MissingPermissions') {
        try {
          await _query.permissionsRequest();
        } catch (_) {}
        return await _queryOnce();
      }
      rethrow;
    }
  }

  Future<List<SongModel>> _queryOnce() async {
    final songs = await _query.querySongs(
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );
    return songs
        .where((s) =>
            s.data.toLowerCase().endsWith('.mp3') ||
            s.displayName.toLowerCase().endsWith('.mp3'))
        .toList();
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