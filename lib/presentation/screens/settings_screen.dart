import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/utils/permissions.dart';
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
  String? _error;
  List<_FoundMp3> _files = const [];

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
    // Пересканируем только если уже есть разрешение — иначе не спамим.
    if (state == AppLifecycleState.resumed &&
        !_loading &&
        !_needPermission &&
        _error == null) {
      _init();
    }
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = null;
      _needPermission = false;
    });

    // 1. Разрешение — ДО любого обращения к MediaStore.
    //    Иначе `on_audio_query` падает с "Reply already submitted".
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

    try {
      // 2. Один-единственный вызов scanAllMp3 за всю инициализацию.
      final scanner = ref.read(mediaScannerProvider);
      final songs = await scanner.scanAllMp3();

      final currentIds = songs.map((s) => s.id).toSet();
      final pathToId = <String, int>{};
      for (final s in songs) {
        if (s.data.isNotEmpty) pathToId[s.data] = s.id;
      }
      debugPrint('[settings] MediaStore: ${pathToId.length} mp3(s)');

      // 3. Cleanup по уже готовому набору id.
      await _cleanupOrphanedRecords(currentIds);

      // 4. Список: MediaStore + bundled.
      final files = await _scanAllMp3(pathToId);
      debugPrint('[settings] scan → ${files.length} file(s)');

      if (!mounted) return;
      setState(() {
        _files = files;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[settings] init failed: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Ошибка: $e';
        });
      }
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

    // 1. MP3 из MediaStore
    for (final entry in pathToId.entries) {
      try {
        final stat = await File(entry.key).stat();
        result.add(_FoundMp3(
          path: entry.key,
          sizeBytes: stat.size,
          isBundled: false,
          mediaStoreId: entry.value,
        ));
      } catch (_) {
        // Фантом MediaStore — файла нет, пропускаем.
      }
    }

    // 2. Bundled из приватной папки
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
          if (id >= 0) continue; // прячем копии обычных треков
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

  Future<void> _delete(_FoundMp3 item) async {
    // ... без изменений, как было в прошлой версии
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

    try {
      final file = File(item.path);
      if (!await file.exists()) {
        _snack('Файл не найден');
        return;
      }

      await file.delete();

      final repo = ref.read(trackRepositoryProvider);
      final tracks = await repo.getAllTracks();
      final itemBase = item.fileName;
      final itemBaseNoPrefix =
          itemBase.contains('__') ? itemBase.split('__').last : itemBase;

      final matching = tracks.where((t) {
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
      }).toList();

      debugPrint(
        '[delete] item="${item.fileName}" mediaStoreId=${item.mediaStoreId} '
        '→ matched ${matching.length}',
      );
      for (final t in matching) {
        await repo.deleteTrack(t);
      }
      ref.invalidate(tracksProvider);

      _snack(
        matching.isEmpty
            ? 'Файл удалён'
            : 'Файл удалён (удалено из библиотеки: ${matching.length})',
      );
      await _init();
    } on FileSystemException catch (e) {
      if (e.osError?.errorCode == 13) {
        _showNoAccessDialog();
      } else {
        _snack('Не удалось удалить. ${e.osError?.message ?? e.message}');
      }
    } catch (e) {
      _snack('Ошибка: $e');
    }
  }

  void _showNoAccessDialog() {
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Все MP3 на устройстве'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _init,
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: _buildBody(),
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

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'Найдено: ${_files.length}',
            style: Theme.of(context).textTheme.bodySmall,
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
                    return ListTile(
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
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Удалить с устройства',
                        onPressed: () => _delete(f),
                      ),
                    );
                  },
                ),
        ),
      ],
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