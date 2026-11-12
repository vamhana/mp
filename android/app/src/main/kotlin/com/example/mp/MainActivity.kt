package com.example.mp

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

/**
 * Наследуем AudioServiceActivity (обязательно для audio_service ^0.18.x),
 * иначе AudioService.init не привяжется к сервису и уведомление/фон
 * перестанут работать.
 *
 * AudioServiceActivity — подкласс FlutterActivity, поэтому onCreate /
 * onNewIntent / configureFlutterEngine / startActivity работают штатно.
 */
class MainActivity : AudioServiceActivity() {

    companion object {
        // Должно совпадать с AppChannels.share в lib/core/utils/channels.dart
        private const val CHANNEL = "com.example.mp/share"
    }

    private data class PendingFile(val path: String, val playImmediately: Boolean)

    private var pending: PendingFile? = null
    private var channel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        android.util.Log.i(
            "MP_LIFECYCLE",
            "onCreate instance=${hashCode()} action=${intent?.action} " +
                "engine=${flutterEngine?.hashCode()} " +
                "dartExecutor=${flutterEngine?.dartExecutor?.hashCode()}",
        )
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        android.util.Log.i(
            "MP_LIFECYCLE",
            "onNewIntent instance=${hashCode()} action=${intent.action} " +
                "engine=${flutterEngine?.hashCode()} " +
                "dartExecutor=${flutterEngine?.dartExecutor?.hashCode()}",
        )
        handleIntent(intent)
        deliverPending()
    }

    override fun onResume() {
        super.onResume()
        android.util.Log.i(
            "MP_LIFECYCLE",
            "onResume instance=${hashCode()} " +
                "engine=${flutterEngine?.hashCode()} " +
                "dartExecutor=${flutterEngine?.dartExecutor?.hashCode()}",
        )
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        when (intent.action) {
            Intent.ACTION_SEND -> {
                val uri = extractStreamUri(intent) ?: return
                val path = copyUriToTempFile(uri) ?: return
                pending = PendingFile(path, playImmediately = false)
            }
            Intent.ACTION_VIEW -> {
                val uri = intent.data ?: return
                val path = copyUriToTempFile(uri) ?: return
                pending = PendingFile(path, playImmediately = true)
            }
        }
    }

    private fun extractStreamUri(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }

    private fun copyUriToTempFile(uri: Uri): String? = try {
        val input = try {
            contentResolver.openInputStream(uri)
        } catch (_: Exception) {
            // Для схемы file:// (некоторые файловые менеджеры отдают так)
            if (uri.scheme == "file") uri.path?.let { FileInputStream(it) } else null
        } ?: return null

        val rawName = queryDisplayName(uri)?.takeIf { it.isNotBlank() }
            ?: "shared_audio.mp3"
        val safeName = rawName.replace(Regex("[\\\\/:*?\"<>|]"), "_")
        val out = File(cacheDir, safeName)
        FileOutputStream(out).use { input.copyTo(it) }
        input.close()
        out.absolutePath
    } catch (e: Exception) {
        e.printStackTrace()
        null
    }

    private fun queryDisplayName(uri: Uri): String? = try {
        contentResolver.query(uri, null, null, null, null)?.use { c ->
            if (!c.moveToFirst()) return@use null
            val idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (idx == -1) null else c.getString(idx)
        }
    } catch (_: Exception) { null }

    /**
     * Отдаём файл событием. `pending` очищаем ТОЛЬКО при успешной
     * доставке: если Dart-обработчик ещё не зарегистрирован (гонка при
     * старте или если onNewIntent сработал до initState), pending остаётся
     * и подберётся через getPendingFile на resume.
     */
    private fun deliverPending() {
        val ch = channel ?: return
        val p = pending ?: return
        // Если движок мёртв — канал бесполезен, оставляем pending
        // до следующего осмысленного resume
        if (flutterEngine?.dartExecutor == null) return
        ch.invokeMethod(
            "onSharedFile",
            mapOf("path" to p.path, "playImmediately" to p.playImmediately),
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    if (pending === p) pending = null
                }
                override fun error(code: String, message: String?, details: Any?) {
                    // Dart не готов — оставляем pending, заберёт takePending.
                }
                override fun notImplemented() {
                    // То же самое — оставляем pending.
                }
            },
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .also { ch ->
                ch.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "getPendingFile" -> {
                            val p = pending
                            pending = null
                            result.success(
                                p?.let {
                                    mapOf(
                                        "path" to it.path,
                                        "playImmediately" to it.playImmediately,
                                    )
                                }
                            )
                        }
                        "openDefaultAppsSettings" -> {
                            try {
                                openDefaultApps()
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("open_failed", e.message, null)
                            }
                        }
                        "openMediaChooser" -> {
                            try {
                                openMediaChooser()
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("open_failed", e.message, null)
                            }
                        }
                        else -> result.notImplemented()
                    }
                }
            }
    }

    private fun openDefaultApps() {
        val candidates = mutableListOf<Intent>()

        // Экран «Приложения по умолчанию» (API 24+)
        if (Build.VERSION.SDK_INT >= 24) {
            candidates.add(Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS))
        }

        // Резервный вариант — страница настроек самого приложения
        candidates.add(
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:$packageName"),
            )
        )

        for (intent in candidates) {
            try {
                startActivity(intent)
                return
            } catch (_: Exception) {
                // пробуем следующий вариант
            }
        }
    }

    private fun openMediaChooser() {
        // Chooser сам подтянет зарегистрированные приложения; создаём
        // «пробный» intent с mime-type audio/mpeg.
        val probe = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(Uri.parse("file:///dummy.mp3"), "audio/mpeg")
        }
        val chooser = Intent.createChooser(probe, "Открывать аудио через…")
        startActivity(chooser)
    }
}