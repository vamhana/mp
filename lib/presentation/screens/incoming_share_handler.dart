// |P.3.02.05|Presentation|Screen|Dart|lib/presentation/screens/incoming_share_handler.dart|C.1.01.07, D.2.03.01, P.3.01.01, P.3.01.02|v.0.0.01|Draft|—|
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/share_receiver.dart';
import '../../data/models/track.dart';
import '../providers/audio_providers.dart';
import '../providers/track_providers.dart';

class IncomingShareHandler extends ConsumerStatefulWidget {
  final Widget child;
  const IncomingShareHandler({super.key, required this.child});

  @override
  ConsumerState<IncomingShareHandler> createState() => _IncomingShareHandlerState();
}

class _IncomingShareHandlerState extends ConsumerState<IncomingShareHandler>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ShareReceiver.init(_handle);
    _consumePending();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Страховка: если onNewIntent сработал раньше, чем зарегистрировался
    // Dart-обработчик, файл подберётся здесь при возврате в приложение.
    if (state == AppLifecycleState.resumed) _consumePending();
  }

  Future<void> _consumePending() async {
    final p = await ShareReceiver.takePending();
    if (p != null) await _handle(p);
  }

  Future<void> _handle(IncomingAudio incoming) async {
    if (!mounted) return;

    final repo = ref.read(trackRepositoryProvider);
    final track = await repo.importLocalFile(incoming.path);

    // Временный файл удаляем — копия уже в приватной папке.
    try {
      await File(incoming.path).delete();
    } catch (_) {}

    if (track == null) {
      if (mounted) _snack('Не удалось добавить трек');
      return;
    }

    ref.invalidate(tracksProvider);
    if (mounted) _snack('Добавлено: ${track.displayTitle}');

    if (incoming.playImmediately) await _play(track);
  }

  Future<void> _play(Track track) async {
    try {
      final tracks = await ref.read(tracksProvider.future);
      final idx = tracks.indexWhere((t) => t.id == track.id);
      if (idx < 0) return;

      final handler = ref.read(audioHandlerProvider).requireValue;
      await handler.loadPlaylist(
        tracks.map(_toMediaItem).toList(),
        initialIndex: idx,
      );
      await handler.play();
    } catch (_) {}
  }

  MediaItem _toMediaItem(Track t) => MediaItem(
        id: t.id.toString(),
        title: t.displayTitle,
        artist: t.displayArtist,
        duration: t.duration,
        artUri: t.coverPath != null ? Uri.file(t.coverPath!) : null,
        extras: {'filePath': t.filePath},
      );

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}