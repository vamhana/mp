// |P.3.02.03|Presentation|Screen|Dart|lib/presentation/screens/player_tab.dart|C.1.01.01, C.1.01.04, D.2.02.01, S.4.01.01, P.3.01.01, P.3.01.02|v.0.0.02|Draft|—|
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:marquee/marquee.dart';

import '../../core/utils/collage_picker.dart';
import '../../core/utils/lyrics_reader.dart';
import '../../data/models/track.dart';
import '../../services/audio_handler.dart';
import '../providers/audio_providers.dart';
import '../providers/track_providers.dart';

class PlayerTab extends ConsumerWidget {
  const PlayerTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.read(audioHandlerProvider).requireValue;

    return StreamBuilder<MediaItem?>(
      stream: handler.mediaItem,
      builder: (context, snapshot) {
        final mediaItem = snapshot.data;
        if (mediaItem == null) {
          return const Center(child: Text('Выберите трек в списке'));
        }
        final trackId = int.tryParse(mediaItem.id);

        return ref.watch(tracksProvider).when(
              data: (tracks) {
                if (tracks.isEmpty) {
                  return const Center(child: Text('Список пуст'));
                }
                Track? track;
                for (final t in tracks) {
                  if (t.id == trackId) {
                    track = t;
                    break;
                  }
                }
                if (track == null) {
                  return _MissingTrackView(onStop: handler.stop);
                }
                return _PlayerContent(track: track, handler: handler);
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Ошибка: $e')),
            );
      },
    );
  }
}

class _MissingTrackView extends StatelessWidget {
  final Future<void> Function() onStop;
  const _MissingTrackView({required this.onStop});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.music_off, size: 64),
            const SizedBox(height: 16),
            Text(
              'Трек больше недоступен',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Возможно, он был удалён из списка или заменён.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => onStop(),
              child: const Text('Остановить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerContent extends StatefulWidget {
  final Track track;
  final MpAudioHandler handler;

  const _PlayerContent({required this.track, required this.handler});

  @override
  State<_PlayerContent> createState() => _PlayerContentState();
}

class _PlayerContentState extends State<_PlayerContent> {
  bool _showLyrics = false;
  Future<String?>? _lyricsFuture;

  @override
  void didUpdateWidget(covariant _PlayerContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.filePath != widget.track.filePath) {
      _showLyrics = false;
      _lyricsFuture = null;
    }
  }

  void _toggleLyrics() {
    _lyricsFuture ??= LyricsReader.read(widget.track.filePath);
    setState(() => _showLyrics = !_showLyrics);
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final handler = widget.handler;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // === Обложка / текст с кнопкой «Т» в углу ===
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      child: _showLyrics ? _buildLyrics() : _buildCover(),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: _LyricsToggleButton(
                    active: _showLyrics,
                    onTap: _toggleLyrics,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // === Название (marquee при переполнении) ===
          _TitleLine(text: track.displayTitle),

          const SizedBox(height: 8),
          Text(
            track.displayArtist,
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 24),

          // === Seek + кнопки ===
          StreamBuilder<PlaybackState>(
            stream: handler.playbackState,
            builder: (context, stateSnap) {
              final playing = stateSnap.data?.playing ?? false;

              return StreamBuilder<Duration>(
                stream: handler.positionStream,
                builder: (context, posSnap) {
                  final position = posSnap.data ?? Duration.zero;

                  return Column(
                    children: [
                      _SeekBar(
                        position: position,
                        duration: track.duration,
                        onSeek: handler.seek,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            iconSize: 48,
                            onPressed: handler.skipToPrevious,
                            icon: const Icon(Icons.skip_previous),
                          ),
                          IconButton(
                            iconSize: 72,
                            onPressed:
                                playing ? handler.pause : handler.play,
                            icon: Icon(
                              playing
                                  ? Icons.pause_circle_filled
                                  : Icons.play_circle_filled,
                            ),
                          ),
                          IconButton(
                            iconSize: 48,
                            onPressed: handler.skipToNext,
                            icon: const Icon(Icons.skip_next),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCover() {
    final track = widget.track;
    if (track.coverPath == null) return _collageOrIcon();

    return Image.file(
      File(track.coverPath!),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _collageOrIcon(),
    );
  }

  Widget _collageOrIcon() {
    final track = widget.track;
    final collageAsset = CollagePicker.instance
        .pick(track.id?.toString() ?? track.filePath);
    if (collageAsset != null) {
      return Image.asset(collageAsset, fit: BoxFit.cover);
    }
    return const Icon(Icons.music_note, size: 80);
  }

  Widget _buildLyrics() {
    return FutureBuilder<String?>(
      future: _lyricsFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final lyrics = snap.data;
        if (lyrics == null || lyrics.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                'Текст песни не найден в метаданных',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
          child: Text(
            lyrics,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        );
      },
    );
  }
}

class _LyricsToggleButton extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;

  const _LyricsToggleButton({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? Colors.deepPurple : Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(10),
          child: Text(
            'Т',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }
}

/// Название трека. Если влезает — обычный `Text` по центру.
/// Если нет — `Marquee` (плавная прокрутка). Высота всегда одна строка,
/// поэтому кнопки управления больше не съезжают.
class _TitleLine extends StatelessWidget {
  final String text;
  const _TitleLine({required this.text});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.headlineSmall!;
    final scaler = MediaQuery.textScalerOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final tp = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
          textScaler: scaler,
        )..layout();

        if (tp.width <= constraints.maxWidth) {
          return Text(
            text,
            style: style,
            textAlign: TextAlign.center,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
          );
        }
        return SizedBox(
          height: tp.height,
          child: Marquee(
            text: text,
            style: style,
            velocity: 40,
            blankSpace: 60,
            numberOfRounds: 1,
            textDirection: TextDirection.ltr,
          ),
        );
      },
    );
  }
}

class _SeekBar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;

  const _SeekBar({
    required this.position,
    required this.duration,
    required this.onSeek,
  });

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final maxMs = widget.duration.inMilliseconds > 0
        ? widget.duration.inMilliseconds.toDouble()
        : 1.0;
    final currentMs =
        (_dragValue ?? widget.position.inMilliseconds.toDouble())
            .clamp(0.0, maxMs);

    return Column(
      children: [
        Slider(
          value: currentMs,
          max: maxMs,
          onChangeStart: (v) => setState(() => _dragValue = v),
          onChanged: (v) => setState(() => _dragValue = v),
          onChangeEnd: (v) {
            widget.onSeek(Duration(milliseconds: v.toInt()));
            setState(() => _dragValue = null);
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_fmt(Duration(milliseconds: currentMs.toInt()))),
              Text(_fmt(widget.duration)),
            ],
          ),
        ),
      ],
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}