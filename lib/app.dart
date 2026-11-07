// |A.1.01.01|App|Root|Dart|lib/app.dart|P.3.02.01|v.0.0.03|Draft|—|
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'presentation/providers/audio_providers.dart';
import 'presentation/screens/home_screen.dart';

class MpApp extends StatelessWidget {
  const MpApp({super.key});

  static const _seed = Color(0xFF7C4DFF);

  @override
  Widget build(BuildContext context) {
    final light = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: _seed),
      useMaterial3: true,
    );
    final dark = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seed,
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    );

    return MaterialApp(
      title: 'MP',
      debugShowCheckedModeBanner: false,
      theme: light,
      darkTheme: dark,
      themeMode: ThemeMode.system,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _StartupGate(),
    );
  }
}

class _StartupGate extends ConsumerWidget {
  const _StartupGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final init = ref.watch(audioHandlerProvider);

    if (init.hasError) {
      return _StartupErrorScreen(error: init.error!);
    }

    // Пока грузится — чёрный экран (визуально = нативный splash).
    // Никаких иконок/текста/прогресса.
    if (init.isLoading) {
      return const ColoredBox(color: Colors.black, child: SizedBox.expand());
    }

    return const HomeScreen();
  }
}

class _StartupErrorScreen extends StatelessWidget {
  final Object error;
  const _StartupErrorScreen({required this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64),
              const SizedBox(height: 16),
              const Text(
                'Не удалось запустить приложение',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '$error',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}