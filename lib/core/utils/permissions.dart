// |C.1.01.02|Core|Util|Dart|lib/core/utils/permissions.dart|—|v.0.0.02|Draft|—|
import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

Future<Permission> _audioPermission() async {
  if (!Platform.isAndroid) {
    throw UnsupportedError(
      'Аудио-разрешение поддерживается только на Android',
    );
  }
  final info = await DeviceInfoPlugin().androidInfo;
  return info.version.sdkInt >= 33 ? Permission.audio : Permission.storage;
}

Future<bool> requestAudioPermission() async {
  final perm = await _audioPermission();
  var status = await perm.status;
  if (status.isGranted || status.isLimited) return true;
  status = await perm.request();
  return status.isGranted || status.isLimited;
}

Future<bool> requestNotificationPermission() async {
  if (!Platform.isAndroid) return false;
  final info = await DeviceInfoPlugin().androidInfo;
  if (info.version.sdkInt < 33) return true;
  final status = await Permission.notification.request();
  return status.isGranted;
}

Future<void> openAppSettingsPage() => openAppSettings();

/// Запрос аудио-разрешения с объясняющим диалогом и переходом в настройки.
/// Возвращает true, только если разрешение в итоге выдано.
Future<bool> ensureAudioPermission(BuildContext context) async {
  final perm = await _audioPermission();
  var status = await perm.status;

  if (status.isGranted || status.isLimited) return true;

  status = await perm.request();
  if (status.isGranted || status.isLimited) return true;

  if (!context.mounted) return false;

  if (status.isPermanentlyDenied) {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Нужен доступ к аудио'),
        content: const Text(
          'Без этого разрешения приложение не сможет найти MP3-файлы. '
          'Откройте настройки и разрешите доступ к медиатеке.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Настройки'),
          ),
        ],
      ),
    );
    if (go == true) await openAppSettings();
  } else {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Доступ не выдан'),
        content: const Text(
          'Разрешение на аудио не предоставлено. '
          'Приложение не сможет найти MP3-файлы.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
  }

  return false;
}

/// Полный доступ к файлам (Android 11+).
/// На Android < 11 достаточно обычного WRITE_EXTERNAL_STORAGE.
Future<bool> requestManageExternalStoragePermission() async {
  if (!Platform.isAndroid) return true;

  final info = await DeviceInfoPlugin().androidInfo;
  if (info.version.sdkInt < 30) {
    final status = await Permission.storage.request();
    return status.isGranted;
  }

  var status = await Permission.manageExternalStorage.status;
  if (status.isGranted) return true;

  status = await Permission.manageExternalStorage.request();
  return status.isGranted;
}

/// Проверяет, выдан ли доступ к «всем файлам» (Android 11+).
/// Не открывает никаких экранов — только читает статус.
Future<bool> hasManageExternalStorage() async {
  if (!Platform.isAndroid) return true;
  final info = await DeviceInfoPlugin().androidInfo;
  if (info.version.sdkInt < 30) return true;
  final status = await Permission.manageExternalStorage.status;
  return status.isGranted;
}

/// Открывает системный экран «All files access» для нашего приложения.
/// Возвращается сразу после запуска Settings (Android не ждёт,
/// когда пользователь что-то нажмёт).
/// Реальное состояние проверять через [hasManageExternalStorage]
/// на `AppLifecycleState.resumed`.
Future<void> openManageExternalStorageSettings() async {
  if (!Platform.isAndroid) return;
  final info = await DeviceInfoPlugin().androidInfo;
  if (info.version.sdkInt < 30) {
    await Permission.storage.request();
    return;
  }
  await Permission.manageExternalStorage.request();
}