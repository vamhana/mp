// lib/presentation/screens/settings_screen.dart
// |P.3.02.04|Presentation|Screen|Dart|lib/presentation/screens/settings_screen.dart|C.1.01.02, P.3.01.02|v.0.0.05|Draft|—|
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/utils/share_receiver.dart';
import '../../core/utils/permissions.dart';
import '../../data/models/track.dart';
import '../providers/track_providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with WidgetsBindingObserver {
  bool _loading = true;
  bool _needPermission = false;
  bool _hasAllFiles = true;
  String? _error;
  List<_FoundMp3> _files = const [];

  bool _selectionMode = false;
  final Set<String> _selectedPaths = {};

  bool _bulkPermissionError = false;

  bool _bulkDeleting = false;
  bool _bulkCancelled = false;
  int _bulkCurrent = 0;
  int _bulkTotal = 0;
  String? _bulkCurrentFile;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !_loading &&
        !_needPermission &&
        !_bulkDeleting &&
        _error == null) {
      _init();
    }
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = null;
      _needPermission = false;
      _selectionMode = false;
      _selectedPaths.clear();
    });

    final ok = await requestAudioPermission();
    if (!ok) {
      if (mounted) {
        setState(() {
          _loading = false;
          _needPermission = true;
        });
      }
      return;
    }

    // Проверяем «Все файлы». Без него Android/media/<чужой.пакет>
    // (WhatsApp, Telegram, MAX и т.д.) недоступны.
    final hasAll = await hasManageExternalStorage();
    debugPrint('[settings] MANAGE_EXTERNAL_STORAGE: $hasAll');

    try {
      final scanner = ref.read(mediaScannerProvider);

      final audio = await scanner.scanAllMp3();
      final currentIds = audio.map((a) => a.id).toSet();
      final pathToId = <String, int>{};
      for (final a in audio) {
        if (a.data.isNotEmpty) pathToId[a.data] = a.id;
      }
      debugPrint('[settings] MediaStore: ${pathToId.length} mp3(s)');

      try {
        final localFiles =
            await scanner.scanLocalFiles(pathToId.keys.toSet());
        for (final lf in localFiles) {
          pathToId[lf.path] = -1;
        }
        if (localFiles.isNotEmpty) {
          debugPrint('[settings] +${localFiles.length} local file(s)');
        }
      } catch (e) {
        debugPrint('[settings] scanLocalFiles failed: $e');
      }

      await _cleanupOrphanedRecords(currentIds);

      final files = await _scanAllMp3(pathToId);
      debugPrint('[settings] scan → ${files.length} file(s)');

      if (!mounted) return;
      setState(() {
        _hasAllFiles = hasAll;
        _files = files;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[settings] init failed: $e');
      if (mounted) {
        setState(() {
          _hasAllFiles = hasAll;
          _loading = false;
          _error = 'Ошибка: $e';
        });
      }
    }
  }

  Future<void> _askAllFilesAccess() async {
    final granted = await requestManageExternalStoragePermission();
    if (!mounted) return;
    if (granted) {
      await _init();
    } else {
      _snack(
        'Нужно включить «Доступ ко всем файлам» в системных настройках',
      );
    }
  }

  Future<void> _cleanupOrphanedRecords(Set<int> currentMediaIds) async {
    try {
      final repo = ref.read(trackRepositoryProvider);
      final tracks = await repo.getAllTracks();
      if (tracks.isEmpty) return;

      var pruned = 0;
      for (final t in tracks) {
        var orphaned = false;
        if (!await File(t.filePath).exists()) {
          orphaned = true;
        } else if (t.mediaStoreId > 0 &&
            !currentMediaIds.contains(t.mediaStoreId)) {
          orphaned = true;
        }

        if (orphaned) {
          debugPrint(
            '[cleanup] prune id=${t.id} mediaStoreId=${t.mediaStoreId} '
            '"${t.displayTitle}"',
          );
          await repo.deleteTrack(t);
          pruned++;
        }
      }

      if (pruned > 0) {
        debugPrint('[cleanup] pruned $pruned record(s)');
        ref.invalidate(tracksProvider);
      }
    } catch (e) {
      debugPrint('[cleanup] failed: $e');
    }
  }

  Future<List<_FoundMp3>> _scanAllMp3(Map<String, int> pathToId) async {
    final result = <_FoundMp3>[];

    for (final entry in pathToId.entries) {
      try {
        var file = File(entry.key);
        if (!await file.exists()) {
          final decoded = Uri.decodeFull(entry.key);
          if (decoded != entry.key) file = File(decoded);
        }
        final stat = await file.stat();
        if (stat.type == FileSystemEntityType.notFound) continue;
        result.add(_FoundMp3(
          path: file.path,
          sizeBytes: stat.size,
          isBundled: false,
          mediaStoreId: entry.value > 0 ? entry.value : null,
        ));
      } catch (_) {}
    }

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final mp3Dir = Directory('${appDir.path}/mp3_library');
      if (await mp3Dir.exists()) {
        await _walk(mp3Dir, result, pathToId);
      }
    } catch (e) {
      debugPrint('[settings] app walk failed: $e');
    }

    result.sort((a, b) =>
        a.path.toLowerCase().compareTo(b.path.toLowerCase()));
    return result;
  }

  Future<void> _walk(
    Directory dir,
    List<_FoundMp3> out,
    Map<String, int> pathToId,
  ) async {
    try {
      await for (final entity
          in dir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final path = entity.path;
        if (!path.toLowerCase().endsWith('.mp3')) continue;
        if (pathToId.containsKey(path)) continue;

        final fileName = path.split(Platform.pathSeparator).last;
        final m = RegExp(r'^(-?\d+)__').firstMatch(fileName);
        if (m != null) {
          final id = int.tryParse(m.group(1) ?? '0') ?? 0;
          if (id >= 0) continue;
        }

        try {
          final stat = await entity.stat();
          out.add(_FoundMp3(
            path: path,
            sizeBytes: stat.size,
            isBundled: true,
            mediaStoreId: null,
          ));
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[settings] walk error at ${dir.path}: $e');
    }
  }

  Future<void> _requestPermissionAndRetry() async {
    final ok = await ensureAudioPermission(context);
    if (ok) await _init();
  }

  List<Track> _findMatchingTracks(_FoundMp3 item, List<Track> tracks) {
    final itemBase = item.fileName;
    final itemBaseNoPrefix =
        itemBase.contains('__') ? itemBase.split('__').last : itemBase;

    return tracks.where((t) {
      if (item.mediaStoreId != null &&
          t.mediaStoreId == item.mediaStoreId) {
        return true;
      }
      if (t.filePath == item.path) return true;
      final tBase = t.filePath.split(Platform.pathSeparator).last;
      if (tBase.endsWith('__$itemBase')) return true;
      final tBaseNoPrefix =
          tBase.contains('__') ? tBase.split('__').last : tBase;
      if (tBaseNoPrefix == itemBaseNoPrefix) return true;
      return false;
    }).toList(growable: false);
  }

  Future<void> _purgeLibraryRecords(
    _FoundMp3 item, {
    List<Track>? knownTracks,
  }) async {
    final repo = ref.read(trackRepositoryProvider);
    final tracks = knownTracks ?? await repo.getAllTracks();
    for (final t in _findMatchingTracks(item, tracks)) {
      await repo.deleteTrack(t);
    }
  }

  Future<_DeleteResult> _deleteOne(
    _FoundMp3 item, {
    List<Track>? knownTracks,
    bool showAccessDialog = true,
  }) async {
    var file = File(item.path);
    if (!await file.exists()) {
      final decoded = Uri.decodeFull(item.path);
      if (decoded != item.path) file = File(decoded);
    }

    if (!await file.exists()) {
      await _purgeMediaStore(item.path);
      await _purgeLibraryRecords(item, knownTracks: knownTracks);
      return _DeleteResult.missing;
    }

    try {
      await file.delete();
    } on PathNotFoundException catch (e) {
      debugPrint('[delete] ENOENT after exists()=${item.path}: $e');
      if (showAccessDialog) {
        _showNoAccessDialog();
      } else {
        _bulkPermissionError = true;
      }
      return _DeleteResult.failed;
    } on FileSystemException catch (e) {
      if (e.osError?.errorCode == 13) {
        if (showAccessDialog) {
          _showNoAccessDialog();
        } else {
          _bulkPermissionError = true;
        }
      } else {
        debugPrint('[delete] file delete failed ${item.path}: $e');
      }
      return _DeleteResult.failed;
    } catch (e) {
      debugPrint('[delete] file delete failed ${item.path}: $e');
      return _DeleteResult.failed;
    }

    await _purgeMediaStore(item.path);
    await _purgeLibraryRecords(item, knownTracks: knownTracks);
    return _DeleteResult.deleted;
  }

  Future<void> _purgeMediaStore(String path) async {
    try {
      await ref.read(mediaScannerProvider).query.scanMedia(path);
    } catch (e) {
      debugPrint('[delete] scanMedia($path) failed: $e');
    }
  }

  Future<void> _delete(_FoundMp3 item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить файл с устройства?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.fileName),
            const SizedBox(height: 8),
            Text(item.path, style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 12),
            Text(
              'Файл будет безвозвратно удалён из памяти телефона. '
              'Если он есть в библиотеке MP — также будет убран оттуда.',
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
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final r = await _deleteOne(item);
    ref.invalidate(tracksProvider);
    switch (r) {
      case _DeleteResult.deleted:
        _snack('Файл удалён');
      case _DeleteResult.missing:
        _snack('Файла уже нет — запись убрана');
      case _DeleteResult.failed:
        _snack('Не удалось удалить файл');
    }
    await _init();
  }

  void _showDefaultPlayerDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сделать MP плеером по умолчанию?'),
        content: const Text(
          'Android не позволяет назначить приложение «по умолчанию» в один '
          'клик. Но можно выбрать MP как приложение для открытия mp3 — '
          'после этого при клике на любой аудиофайл будет открываться MP.\n\n'
          '1. Нажмите «Выбрать MP для mp3»\n'
          '2. В системном окне выберите MP и нажмите «Всегда»\n\n'
          'Также MP появится в меню «Поделиться» во всех приложениях — '
          'оттуда можно отправлять треки прямо в библиотеку.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ShareReceiver.openDefaultAppsSettings();
            },
            child: const Text('Настройки Android'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ShareReceiver.openMediaChooser();
            },
            child: const Text('Выбрать MP для mp3'),
          ),
        ],
      ),
    );
  }

  // --- Selection mode ---

  void _enterSelectionMode(_FoundMp3 first) {
    if (_bulkDeleting) return;
    setState(() {
      _selectionMode = true;
      _selectedPaths
        ..clear()
        ..add(first.path);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedPaths.clear();
    });
  }

  void _toggleSelection(_FoundMp3 f) {
    if (_bulkDeleting) return;
    setState(() {
      if (_selectedPaths.contains(f.path)) {
        _selectedPaths.remove(f.path);
      } else {
        _selectedPaths.add(f.path);
      }
    });
  }

  void _toggleSelectAll() {
    if (_bulkDeleting) return;
    setState(() {
      if (_selectedPaths.length == _files.length) {
        _selectedPaths.clear();
      } else {
        _selectedPaths
          ..clear()
          ..addAll(_files.map((f) => f.path));
      }
    });
  }

  Future<void> _deleteSelected() async {
    if (_bulkDeleting) return;

    final toDelete = _files
        .where((f) => _selectedPaths.contains(f.path))
        .toList(growable: false);
    if (toDelete.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Удалить ${toDelete.length} файлов?'),
        content: const Text(
          'Файлы будут безвозвратно удалены из памяти телефона. '
          'Записи в библиотеке MP для них также будут убраны.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text('Удалить (${toDelete.length})'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    _bulkPermissionError = false;
    _bulkCancelled = false;

    setState(() {
      _bulkDeleting = true;
      _bulkCurrent = 0;
      _bulkTotal = toDelete.length;
      _bulkCurrentFile = null;
    });

    List<Track> cachedTracks;
    try {
      cachedTracks = await ref.read(trackRepositoryProvider).getAllTracks();
    } catch (e) {
      debugPrint('[bulk-delete] getAllTracks failed: $e');
      cachedTracks = const [];
    }

    var deleted = 0;
    var missing = 0;
    var failed = 0;

    for (var i = 0; i < toDelete.length; i++) {
      if (_bulkCancelled) break;
      final item = toDelete[i];

      if (mounted) {
        setState(() {
          _bulkCurrent = i + 1;
          _bulkCurrentFile = item.fileName;
        });
      }

      final r = await _deleteOne(
        item,
        knownTracks: cachedTracks,
        showAccessDialog: false,
      );
      switch (r) {
        case _DeleteResult.deleted:
          deleted++;
        case _DeleteResult.missing:
          missing++;
        case _DeleteResult.failed:
          failed++;
      }
    }

    // Список мог сильно измениться — обновляем его уже после снятия
    // оверлея, но `_bulkDeleting` ещё true, чтобы `_init()` не мигнул
    // пустым состоянием.
    ref.invalidate(tracksProvider);
    _exitSelectionMode();

    final parts = <String>['Удалено: $deleted'];
    if (missing > 0) parts.add('уже не было: $missing');
    if (failed > 0) parts.add('ошибок: $failed');
    if (_bulkCancelled) parts.add('прервано на $_bulkCurrent');
    _snack(parts.join(', '));

    if (_bulkPermissionError) _showNoAccessDialog();

    await _init();

    if (mounted) {
      setState(() {
        _bulkDeleting = false;
        _bulkCurrentFile = null;
        _bulkCancelled = false;
      });
    }
  }

  void _showNoAccessDialog() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Нет доступа к файлу'),
        content: const Text(
          'Чтобы удалять файлы из общих папок (Download, Music и т.п.), '
          'нужен доступ ко всем файлам.\n\n'
          'Открыть настройки и включить его?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await openManageExternalStorageSettings();
            },
            child: const Text('Открыть настройки'),
          ),
        ],
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_bulkDeleting,
      onPopInvokedWithResult: (didPop, _) {
        // Пока идёт массовое удаление — кнопка «назад» игнорируется.
        if (!didPop && _bulkDeleting) return;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Все MP3 на устройстве'),
          actions: [
            IconButton(
              onPressed: _showDefaultPlayerDialog,
              icon: const Icon(Icons.star_outline),
              tooltip: 'Сделать плеером по умолчанию',
            ),
            IconButton(
              onPressed: _loading || _bulkDeleting ? null : _init,
              icon: const Icon(Icons.refresh),
              tooltip: 'Обновить',
            ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_needPermission) {
      return _PermissionPrompt(onRequest: _requestPermissionAndRetry);
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _init,
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
    }

    final content = Column(
      children: [
        if (!_hasAllFiles) _AllFilesAccessBanner(onGrant: _askAllFilesAccess),
        if (_selectionMode)
          _SelectionBar(
            selectedCount: _selectedPaths.length,
            totalCount: _files.length,
            onCancel: _exitSelectionMode,
            onToggleAll: _files.isEmpty ? null : _toggleSelectAll,
            onDelete: _selectedPaths.isEmpty ? null : _deleteSelected,
          )
        else
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Text(
                  'Найдено: ${_files.length}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                if (_files.isNotEmpty)
                  Text(
                    'долгое нажатие — выбрать',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: _files.isEmpty
              ? const Center(child: Text('MP3 не найдены'))
              : ListView.separated(
                  itemCount: _files.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final f = _files[i];
                    final selected = _selectedPaths.contains(f.path);
                    return ListTile(
                      selected: _selectionMode && selected,
                      title: Text(
                        f.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (f.isBundled)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 2),
                              child: Text(
                                'в комплекте',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          Text(
                            f.path,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      onTap:
                          _selectionMode ? () => _toggleSelection(f) : null,
                      onLongPress: _selectionMode
                          ? null
                          : () => _enterSelectionMode(f),
                      trailing: _selectionMode
                          ? Checkbox(
                              value: selected,
                              onChanged: (_) => _toggleSelection(f),
                            )
                          : _DeleteIconButton(
                              onTap: () => _delete(f),
                              onLongPress: () => _enterSelectionMode(f),
                            ),
                    );
                  },
                ),
        ),
      ],
    );

    if (!_bulkDeleting) return content;

    // Модальный слой на время массового удаления: пользователь видит
    // прогресс, а весь список/чекбоксы заблокированы ModalBarrier'ом.
    return Stack(
      children: [
        content,
        const ModalBarrier(dismissible: false, color: Colors.black54),
        Center(child: _buildBulkDeleteCard()),
      ],
    );
  }

  Widget _buildBulkDeleteCard() {
    final value = _bulkTotal == 0
        ? null
        : (_bulkCurrent / _bulkTotal).clamp(0.0, 1.0);
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 8,
      margin: const EdgeInsets.symmetric(horizontal: 32),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Удаление $_bulkCurrent из $_bulkTotal',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: value),
            if (_bulkCurrentFile != null) ...[
              const SizedBox(height: 8),
              Text(
                _bulkCurrentFile!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _bulkCancelled
                    ? null
                    : () => setState(() => _bulkCancelled = true),
                style: TextButton.styleFrom(
                  foregroundColor: scheme.error,
                ),
                child: Text(
                  _bulkCancelled ? 'Останавливаю…' : 'Прервать',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Баннер «Нет доступа ко всем файлам». Показывается, когда
/// `MANAGE_EXTERNAL_STORAGE` не выдан — без него Android/media/<чужой.пакет>
/// (WhatsApp/Telegram/MAX) не читается.
class _AllFilesAccessBanner extends StatelessWidget {
  final VoidCallback onGrant;
  const _AllFilesAccessBanner({required this.onGrant});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Нет доступа к файлам из WhatsApp/Telegram/MAX',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: scheme.onErrorContainer,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Android 11+ скрывает папки мессенджеров без разрешения '
                    '«Доступ ко всем файлам».',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onErrorContainer,
                        ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: onGrant,
                    icon: const Icon(Icons.lock_open, size: 18),
                    label: const Text('Разрешить'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionPrompt extends StatelessWidget {
  final VoidCallback onRequest;
  const _PermissionPrompt({required this.onRequest});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.library_music_outlined, size: 64),
            const SizedBox(height: 16),
            Text(
              'Нужен доступ к аудиотеке',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Без разрешения приложение не увидит MP3-файлы.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRequest,
              icon: const Icon(Icons.lock_open),
              label: const Text('Разрешить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  final int selectedCount;
  final int totalCount;
  final VoidCallback onCancel;
  final VoidCallback? onToggleAll;
  final VoidCallback? onDelete;

  const _SelectionBar({
    required this.selectedCount,
    required this.totalCount,
    required this.onCancel,
    required this.onToggleAll,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final allSelected = totalCount > 0 && selectedCount == totalCount;

    return Material(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Отмена',
              onPressed: onCancel,
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
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const Spacer(),
            FilledButton.tonalIcon(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
              label: Text(
                selectedCount > 0 ? 'Удалить ($selectedCount)' : 'Удалить',
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

class _DeleteIconButton extends StatelessWidget {
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _DeleteIconButton({required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Удалить с устройства\n(удерживайте — выбрать несколько)',
      triggerMode: TooltipTriggerMode.manual,
      child: InkResponse(
        onTap: onTap,
        onLongPress: onLongPress,
        radius: 20,
        child: const Padding(
          padding: EdgeInsets.all(10),
          child: Icon(Icons.delete_outline, size: 22),
        ),
      ),
    );
  }
}

class _FoundMp3 {
  final String path;
  final int sizeBytes;
  final bool isBundled;
  final int? mediaStoreId;

  const _FoundMp3({
    required this.path,
    required this.sizeBytes,
    required this.isBundled,
    this.mediaStoreId,
  });

  String get fileName => path.split(Platform.pathSeparator).last;
}

enum _DeleteResult { deleted, missing, failed }