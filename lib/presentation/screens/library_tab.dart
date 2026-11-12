// |P.3.02.02|Presentation|Screen|Dart|lib/presentation/screens/library_tab.dart|C.1.01.02, C.1.01.03, D.2.02.01, D.2.03.01, P.3.01.01, P.3.01.02|v.0.0.03|Draft|—|
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/permissions.dart';
import '../../core/utils/track_sharer.dart';
import '../../data/models/track.dart';
import '../../data/repositories/track_repository.dart';
import '../providers/audio_providers.dart';
import '../providers/track_providers.dart';

class LibraryTab extends ConsumerStatefulWidget {
  const LibraryTab({super.key});

  @override
  ConsumerState<LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends ConsumerState<LibraryTab> {
  bool _selectionMode = false;
  final Set<int> _selectedIds = {};

  // --- Синхронизация ---

  Future<void> _runSync() async {
    if (!mounted) return;
    final ok = await ensureAudioPermission(context);
    if (!ok) return;

    // WhatsApp/Telegram/MAX без MANAGE_EXTERNAL_STORAGE не прочитать.
    final hasAll = await hasManageExternalStorage();
    if (!hasAll) {
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Нужен доступ ко всем файлам'),
          content: const Text(
            'Чтобы находить MP3 в папках WhatsApp, Telegram, MAX и других '
            'мессенджеров, нужно разрешение «Доступ ко всем файлам».\n\n'
            'Открыть настройки и включить?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Не сейчас'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Открыть настройки'),
            ),
          ],
        ),
      );
      if (go == true) {
        await openManageExternalStorageSettings();
      }
      // Продолжаем синк без MANAGE_EXTERNAL_STORAGE — найдёт то,
      // что доступно (Download, Music, приватная папка).
    }

    final repo = ref.read(trackRepositoryProvider);
    ref.read(syncProgressProvider.notifier).state =
        const SyncProgress(current: 0, total: 0, fileName: '');

    try {
      final added = await repo.syncAll(
        onProgress: (p) {
          if (mounted) ref.read(syncProgressProvider.notifier).state = p;
        },
      );
      ref.invalidate(tracksProvider);
      if (mounted) {
        _snack(added == 0
            ? 'Новых треков не найдено'
            : 'Добавлено треков: $added');
      }
    } catch (e) {
      if (mounted) _snack('Ошибка синхронизации: $e');
    } finally {
      ref.read(syncProgressProvider.notifier).state = null;
    }
  }

  // --- Reorder ---

  Future<void> _move(List<Track> tracks, int index, int delta) async {
    final target = index + delta;
    if (target < 0 || target >= tracks.length) return;

    final list = List<Track>.from(tracks);
    final item = list.removeAt(index);
    list.insert(target, item);

    await ref.read(trackRepositoryProvider).db.rewriteOrder(list);
    ref.invalidate(tracksProvider);

    final handler = ref.read(audioHandlerProvider).requireValue;
    if (handler.queue.value.isNotEmpty) {
      await handler.reloadQueue(list.map(_toMediaItem).toList());
    }
  }

  // --- Удаление (одиночное) ---

  Future<void> _delete(Track track) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить из списка?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('«${track.displayTitle}» будет удалён из списка MP.'),
            const SizedBox(height: 12),
            Text(
              'Оригинальный файл на телефоне останется на месте — '
              'вы сможете снова добавить его через кнопку «Обновить».',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить из списка'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final handler = ref.read(audioHandlerProvider).requireValue;
    final trackIdStr = track.id?.toString();
    final wasCurrent = trackIdStr != null &&
        handler.mediaItem.value?.id == trackIdStr;
    final wasInQueue = trackIdStr != null &&
        handler.queue.value.any((mi) => mi.id == trackIdStr);

    if (wasCurrent) await handler.stop();

    await ref.read(trackRepositoryProvider).deleteTrack(track);
    ref.invalidate(tracksProvider);

    if (wasInQueue && !wasCurrent) {
      final remaining = handler.queue.value
          .where((mi) => mi.id != trackIdStr)
          .toList(growable: false);
      if (remaining.isEmpty) {
        await handler.stop();
      } else {
        await handler.reloadQueue(remaining);
      }
    }

    if (mounted) _snack('Удалён из списка');
  }

  // --- Удаление (массовое, из режима выбора) ---

  Future<void> _deleteSelected(List<Track> tracks) async {
    final selected = tracks
        .where((t) => t.id != null && _selectedIds.contains(t.id))
        .toList(growable: false);
    if (selected.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Удалить из списка ${selected.length} треков?'),
        content: const Text(
          'Треки будут удалены из списка MP. '
          'Оригинальные файлы на телефоне останутся на месте — '
          'их можно снова добавить через «Обновить».',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Удалить (${selected.length})'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final handler = ref.read(audioHandlerProvider).requireValue;
    final selectedIdStrs = selected
        .map((t) => t.id?.toString())
        .whereType<String>()
        .toSet();

    final wasInQueue =
        handler.queue.value.any((mi) => selectedIdStrs.contains(mi.id));

    final repo = ref.read(trackRepositoryProvider);
    for (final t in selected) {
      await repo.deleteTrack(t);
    }

    if (wasInQueue) {
      final remaining = handler.queue.value
          .where((mi) => !selectedIdStrs.contains(mi.id))
          .toList(growable: false);
      if (remaining.isEmpty) {
        await handler.stop();
      } else {
        await handler.reloadQueue(remaining);
      }
    }

    ref.invalidate(tracksProvider);
    _exitSelectionMode();

    if (mounted) _snack('Удалено из списка: ${selected.length}');
  }

  // --- Воспроизведение ---

  Future<void> _play(List<Track> tracks, int index) async {
    final handler = ref.read(audioHandlerProvider).requireValue;

    await handler.loadPlaylist(
      tracks.map(_toMediaItem).toList(),
      initialIndex: index,
    );

    if (mounted) {
      try {
        DefaultTabController.of(context).animateTo(0);
      } catch (e) {
        debugPrint('[play] tab switch failed: $e');
      }
    }

    await requestNotificationPermission();
    await handler.play();
  }

  MediaItem _toMediaItem(Track t) => MediaItem(
        id: t.id.toString(),
        title: t.displayTitle,
        artist: t.displayArtist,
        duration: t.duration,
        artUri: t.coverPath != null ? Uri.file(t.coverPath!) : null,
        extras: {'filePath': t.filePath},
      );

  // --- Share ---

  Future<void> _shareSingle(Track t) async {
    final ok = await TrackSharer.share([t]);
    if (!ok && mounted) _snack('Не удалось поделиться треком');
  }

  Future<void> _shareSelected(List<Track> tracks) async {
    final selected = tracks
        .where((t) => t.id != null && _selectedIds.contains(t.id))
        .toList(growable: false);
    if (selected.isEmpty) return;

    final capped = selected.length > TrackSharer.maxTracks
        ? selected.take(TrackSharer.maxTracks).toList(growable: false)
        : selected;

    final wasTrimmed = capped.length < selected.length;

    _exitSelectionMode();
    if (wasTrimmed) {
      _snack(
        'Отправляю первые ${TrackSharer.maxTracks} из ${selected.length}',
      );
    }
    final ok = await TrackSharer.share(capped);
    if (!ok && mounted) _snack('Не удалось поделиться');
  }

  // --- Selection mode ---

  void _enterSelectionMode(Track first) {
    setState(() {
      _selectionMode = true;
      _selectedIds
        ..clear()
        ..addIfNotNull(first.id);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelection(Track t) {
    if (t.id == null) return;
    setState(() {
      if (_selectedIds.contains(t.id)) {
        _selectedIds.remove(t.id);
      } else {
        _selectedIds.add(t.id!);
      }
    });
  }

  void _toggleSelectAll(List<Track> tracks) {
    setState(() {
      if (_selectedIds.length == tracks.length) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(tracks.map((t) => t.id).whereType<int>());
      }
    });
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    final asyncTracks = ref.watch(tracksProvider);
    final progress = ref.watch(syncProgressProvider);
    final tracks = asyncTracks.valueOrNull ?? const <Track>[];

    return PopScope(
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectionMode) _exitSelectionMode();
      },
      child: Column(
        children: [
          if (_selectionMode)
            _SelectionBar(
              selectedCount: _selectedIds.length,
              totalCount: tracks.length,
              onCancel: _exitSelectionMode,
              onToggleAll:
                  tracks.isEmpty ? null : () => _toggleSelectAll(tracks),
              onShare: _selectedIds.isEmpty
                  ? null
                  : () => _shareSelected(tracks),
              onDelete: _selectedIds.isEmpty
                  ? null
                  : () => _deleteSelected(tracks),
            ),
          if (progress != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LinearProgressIndicator(
                    value: progress.total == 0 ? null : progress.fraction,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    progress.total == 0
                        ? 'Поиск MP3…'
                        : 'Копирование ${progress.current}/${progress.total} '
                            '${progress.fileName}',
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          if (!_selectionMode)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: progress != null ? null : _runSync,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Обновить'),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: asyncTracks.when(
              data: (tracks) {
                if (tracks.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Список пуст. Нажмите «Обновить», чтобы найти MP3.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: tracks.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => _buildRow(tracks, i),
                );
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Ошибка: $e')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(List<Track> tracks, int i) {
    final t = tracks[i];
    final selected = t.id != null && _selectedIds.contains(t.id);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      selected: _selectionMode && selected,
      leading: SizedBox(
        width: 48,
        height: 48,
        child: t.coverPath != null
            ? Image.file(
                File(t.coverPath!),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.music_note),
              )
            : const Icon(Icons.music_note),
      ),
      title: Text(
        t.displayTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${t.displayArtist} • ${_fmt(t.duration)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: _selectionMode ? () => _toggleSelection(t) : () => _play(tracks, i),
      onLongPress: _selectionMode ? null : () => _enterSelectionMode(t),
      trailing: _selectionMode
          ? Checkbox(
              value: selected,
              onChanged: (_) => _toggleSelection(t),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 20,
                  onPressed: i == 0 ? null : () => _move(tracks, i, -1),
                  icon: const Icon(Icons.arrow_upward),
                  tooltip: 'Вверх',
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 20,
                  onPressed: i == tracks.length - 1
                      ? null
                      : () => _move(tracks, i, 1),
                  icon: const Icon(Icons.arrow_downward),
                  tooltip: 'Вниз',
                ),
                _LongPressIconButton(
                  icon: Icons.share_outlined,
                  tooltip:
                      'Поделиться\n(удерживайте — выбрать несколько)',
                  onTap: () => _shareSingle(t),
                  onLongPress: () => _enterSelectionMode(t),
                ),
                _LongPressIconButton(
                  icon: Icons.close,
                  tooltip:
                      'Удалить из списка\n(удерживайте — выбрать несколько)',
                  onTap: () => _delete(t),
                  onLongPress: () => _enterSelectionMode(t),
                ),
              ],
            ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _SelectionBar extends StatelessWidget {
  final int selectedCount;
  final int totalCount;
  final VoidCallback onCancel;
  final VoidCallback? onToggleAll;
  final VoidCallback? onShare;
  final VoidCallback? onDelete;

  const _SelectionBar({
    required this.selectedCount,
    required this.totalCount,
    required this.onCancel,
    required this.onToggleAll,
    required this.onShare,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allSelected = totalCount > 0 && selectedCount == totalCount;

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            IconButton(
              onPressed: onCancel,
              icon: const Icon(Icons.close),
              tooltip: 'Отмена',
            ),
            Checkbox(
              value: allSelected,
              onChanged:
                  onToggleAll == null ? null : (_) => onToggleAll!(),
            ),
            const Text('Все'),
            const SizedBox(width: 8),
            Text(
              '$selectedCount / $totalCount',
              style: theme.textTheme.titleSmall,
            ),
            const Spacer(),
            IconButton(
              onPressed: onShare,
              icon: const Icon(Icons.share),
              tooltip: 'Поделиться',
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Удалить из списка',
            ),
          ],
        ),
      ),
    );
  }
}

extension _AddIfNotNull<T> on Set<T> {
  void addIfNotNull(T? value) {
    if (value != null) add(value);
  }
}

/// Кнопка с иконкой: короткий тап — действие, долгое нажатие — вход в
/// режим выбора (используется для «Поделиться» и «Удалить»).
class _LongPressIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _LongPressIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      triggerMode: TooltipTriggerMode.manual,
      child: InkResponse(
        onTap: onTap,
        onLongPress: onLongPress,
        radius: 20,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 20),
        ),
      ),
    );
  }
}