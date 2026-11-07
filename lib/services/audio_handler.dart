// |S.4.01.01|Services|Audio|Dart|lib/services/audio_handler.dart|—|v.0.0.02|Draft|—|
import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

/// Полноценный аудио-хендлер, управляющий очередью воспроизведения.
class MpAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  MpAudioHandler() {
    // Зацикливание: после последнего трека — первый.
    _player.setLoopMode(LoopMode.all);

    // Транслируем события от just_audio в playbackState для audio_service
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);

    // Следим за сменой трека в just_audio и обновляем текущий mediaItem
    _player.currentIndexStream.listen((index) {
      if (index != null && index < queue.value.length) {
        mediaItem.add(queue.value[index]);
      }
    });
  }

  /// Стрим текущей позиции для плавного ползунка.
  Stream<Duration> get positionStream => _player.positionStream;

  // --- Управление ---

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => _player.seekToNext();

  @override
  Future<void> skipToPrevious() => _player.seekToPrevious();

  @override
  Future<void> skipToQueueItem(int index) async {
    final seq = _player.sequence;
    if (seq == null || index < 0 || index >= seq.length) return;
    await _player.seek(Duration.zero, index: index);
    await play();
  }

  /// Обработка кнопки «Крестик» в уведомлении.
  @override
  Future<void> stop() async {
    await _player.stop();
    queue.add([]);
    mediaItem.add(null);
    await super.stop();
  }

  /// Перезагружает очередь с сохранением текущего трека и позиции.
  Future<void> reloadQueue(List<MediaItem> items) async {
    if (items.isEmpty) {
      await stop();
      return;
    }

    final currentId = mediaItem.value?.id;
    final position = _player.position;
    final wasPlaying = _player.playing;

    var initialIndex = 0;
    if (currentId != null) {
      final found = items.indexWhere((i) => i.id == currentId);
      if (found >= 0) initialIndex = found;
    }

    await loadPlaylist(items, initialIndex: initialIndex);
    if (position > Duration.zero) {
      await _player.seek(position);
    }
    if (wasPlaying) {
      await _player.play();
    }
  }

  // --- Загрузка плейлиста ---

  Future<void> loadPlaylist(
    List<MediaItem> items, {
    int initialIndex = 0,
  }) async {
    queue.add(items);

    // Синхронно выставляем текущий трек — иначе PlayerTab
    // на холодном старте успевает отрисоваться с mediaItem == null.
    if (initialIndex >= 0 && initialIndex < items.length) {
      mediaItem.add(items[initialIndex]);
    }

    final audioSources = items.map((item) {
      return AudioSource.file(
        item.extras!['filePath'] as String,
        tag: item,
      );
    }).toList();

    await _player.setAudioSource(
      ConcatenatingAudioSource(children: audioSources),
      initialIndex: initialIndex,
    );
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
      systemActions: const {
        MediaAction.seek,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    );
  }
}