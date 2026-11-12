// |C.1.01.08|Core|Util|Dart|lib/core/utils/channels.dart|—|v.0.0.01|Draft|—|

/// Единая точка правды для всех MethodChannel / notification channel ID.
///
/// Меняем `applicationId` — правим только этот файл (и, соответственно,
/// `CHANNEL` companion-объект в `MainActivity.kt`). Всё остальное
/// продолжает работать без массовых search-replace.
class AppChannels {
  AppChannels._();

  // MethodChannel — значения должны совпадать с Kotlin.
  static const share = 'com.example.mp/share';
  static const mediaScanner = 'com.example.mp/media_scanner';

  // Уведомление audio_service.
  // ВАЖНО: этот ID нельзя менять после релиза — пользователи увидят
  // новый системный канал уведомлений вместо существующего.
  static const notificationChannelId = 'com.example.mp.audio';
  static const notificationChannelName = 'MP — воспроизведение';
  static const notificationIcon = 'mipmap/ic_launcher';
}