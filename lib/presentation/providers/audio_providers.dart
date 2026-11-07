// |P.3.01.01|Presentation|Provider|Dart|lib/presentation/providers/audio_providers.dart|S.4.01.01|v.0.0.01|Draft|—|
import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/collage_picker.dart';
import '../../data/datasources/bundled_tracks_seeder.dart';
import '../../services/audio_handler.dart';
import 'track_providers.dart';

/// Инициализирует всё приложение и возвращает готовый аудио-хендлер.
///
/// Порядок:
/// 1. Коллажи (быстро, ~10 мс)
/// 2. `AudioService.init` (~0.5–1.5 с на холодном старте)
/// 3. Bundled-треки (только при первом запуске)
///
/// Пока провайдер в `loading`, `MpApp` показывает `SplashScreen`.
/// Хендлер никогда не инвалидируется — `AudioService.init` должен
/// вызываться ровно один раз за запуск.
final audioHandlerProvider = FutureProvider<MpAudioHandler>((ref) async {
  await CollagePicker.instance.ensureLoaded();

  final handler = await AudioService.init(
    builder: () => MpAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.mp.audio',
      androidNotificationChannelName: 'MP — воспроизведение',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      androidNotificationIcon: 'mipmap/ic_launcher',
    ),
  );

  try {
    await BundledTracksSeeder.instance.seedIfNeeded(
      db: ref.read(trackDatabaseProvider),
      copier: ref.read(fileCopierProvider),
    );
  } catch (_) {
    // Никогда не блокируем запуск из-за предзагруженных треков.
  }

  return handler;
});