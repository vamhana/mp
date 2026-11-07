// |P.3.02.01|Presentation|Screen|Dart|lib/presentation/screens/home_screen.dart|P.3.02.02, P.3.02.03, P.3.02.04|v.0.0.02|Draft|—|
import 'package:flutter/material.dart';

import 'library_tab.dart';
import 'player_tab.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('MP'),
          actions: [
            IconButton(
              icon: const Icon(Icons.help_outline),
              tooltip: 'Как пользоваться',
              onPressed: () => _showHelp(context),
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Настройки',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SettingsScreen(),
                ),
              ),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.play_circle_outline), text: 'Плеер'),
              Tab(icon: Icon(Icons.list), text: 'Список'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            PlayerTab(),
            LibraryTab(),
          ],
        ),
      ),
    );
  }

  void _showHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Как пользоваться MP'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: const [
              _HelpSection(
                title: '📋 Список',
                text:
                    'Вкладка «Список» показывает вашу коллекцию MP3. '
                    'Стрелки ↑ ↓ меняют порядок, ✕ удаляет из списка '
                    '(файл на телефоне остаётся).',
              ),
              SizedBox(height: 12),
              _HelpSection(
                title: '🔄 Обновить',
                text:
                    'Нажмите «Обновить», чтобы просканировать память телефона '
                    'и добавить новые MP3 в список. Старые останутся на месте.',
              ),
              SizedBox(height: 12),
              _HelpSection(
                title: '📤 Поделиться',
                text:
                    'Иконка ➦ рядом с треком открывает меню «Поделиться» — '
                    'можно отправить песню в мессенджер или контакту.\n\n'
                    'Для нескольких песен: долгое нажатие на трек → '
                    'выбор до 10 штук → кнопка «Поделиться» сверху.',
              ),
              SizedBox(height: 12),
              _HelpSection(
                title: '▶ Плеер',
                text:
                    'Вкладка «Плеер» показывает текущий трек, обложку и '
                    'управление. Кнопка «Т» на обложке переключает её на '
                    'текст песни (если он есть в метаданных).',
              ),
              SizedBox(height: 12),
              _HelpSection(
                title: '⚙ Настройки',
                text:
                    'Шестерёнка в правом верхнем углу открывает список всех '
                    'MP3 на устройстве с путями к файлам. Оттуда можно '
                    'удалить файл с телефона безвозвратно.',
              ),
            ],
          ),
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
}

class _HelpSection extends StatelessWidget {
  final String title;
  final String text;

  const _HelpSection({required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          text,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}