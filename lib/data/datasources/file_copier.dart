// |D.2.01.01|Data|Datasource|Dart|lib/data/datasources/file_copier.dart|—|v.0.0.02|Draft|—|
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

class FileCopier {
  Directory? _mp3Dir;
  Directory? _coversDir;

  Future<Directory> get mp3Dir async {
    if (_mp3Dir != null) return _mp3Dir!;
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/mp3_library');
    if (!await dir.exists()) await dir.create(recursive: true);
    _mp3Dir = dir;
    return dir;
  }

  Future<Directory> get coversDir async {
    if (_coversDir != null) return _coversDir!;
    final base = await mp3Dir;
    final dir = Directory('${base.path}/covers');
    if (!await dir.exists()) await dir.create(recursive: true);
    _coversDir = dir;
    return dir;
  }

  /// Копирует MP3 в приватную папку. Возвращает путь к копии.
  /// Имя файла: `<mediaStoreId>__<originalName>` — гарантирует уникальность.
  Future<String> copyMp3({
    required int mediaStoreId,
    required String sourcePath,
    required String originalName,
  }) async {
    final dir = await mp3Dir;
    final safeName = _sanitize(originalName);
    final dest = File('${dir.path}/${mediaStoreId}__$safeName');
    if (await dest.exists()) return dest.path;

    final src = File(sourcePath);
    if (!await src.exists()) {
      throw FileSystemException('Исходный файл не найден', sourcePath);
    }
    await src.copy(dest.path);
    return dest.path;
  }

  /// Сохраняет обложку, определяя формат по magic bytes.
  /// Возвращает путь или null, если bytes пусты / формат не распознан.
  Future<String?> saveCover(Uint8List? bytes, int mediaStoreId) async {
    if (bytes == null || bytes.isEmpty) return null;

    final ext = _detectImageExtension(bytes);
    if (ext == null) return null;

    final dir = await coversDir;
    final file = File('${dir.path}/$mediaStoreId.$ext');
    if (!await file.exists()) {
      await file.writeAsBytes(bytes, flush: true);
    }
    return file.path;
  }

  Future<void> deleteFileQuietly(String? path) async {
    if (path == null) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  String _sanitize(String name) {
    final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return cleaned.isEmpty ? 'track.mp3' : cleaned;
  }

  /// Определяет расширение изображения по первым байтам (JPEG/PNG/WebP).
  String? _detectImageExtension(Uint8List b) {
    // JPEG: FF D8 FF
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
      return 'jpg';
    }
    // PNG: 89 50 4E 47 0D 0A 1A 0A
    if (b.length >= 8 &&
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47 &&
        b[4] == 0x0D &&
        b[5] == 0x0A &&
        b[6] == 0x1A &&
        b[7] == 0x0A) {
      return 'png';
    }
    // WebP: RIFF....WEBP
    if (b.length >= 12 &&
        b[0] == 0x52 &&
        b[1] == 0x49 &&
        b[2] == 0x46 &&
        b[3] == 0x46 &&
        b[8] == 0x57 &&
        b[9] == 0x45 &&
        b[10] == 0x42 &&
        b[11] == 0x50) {
      return 'webp';
    }
    return null;
  }
}