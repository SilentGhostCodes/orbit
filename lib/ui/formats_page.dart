import 'package:flutter/material.dart';
import 'package:orbit/theme/orbit_theme.dart';
import 'package:orbit/widgets/orbit_widgets.dart';

/// Настройки → Форматы подписок: what can be pasted or scanned into «Новая подписка».
class FormatsPage extends StatelessWidget {
  const FormatsPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(titleSpacing: 0, title: const Text('Форматы подписок', style: OrbitText.sheetTitle)),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text(
          'Вставь или отсканируй что угодно из списка — Orbit сам поймёт формат.',
          style: OrbitText.caption.copyWith(fontSize: 13, height: 1.4),
        ),
        const SectionLabel('Зашифрованные ссылки'),
        // not const: the cards take the accent, which the user can change
        _EncryptedCard(
          title: 'Happ',
          subtitle: 'Ссылки из приложения Happ',
          formats: const ['crypt', 'crypt2', 'crypt3', 'crypt4', 'crypt5'],
        ),
        const SizedBox(height: 10),
        _EncryptedCard(title: 'INCY', subtitle: 'Ссылки из приложения INCY', formats: const ['incy://crypt1']),
        const SizedBox(height: 4),
        const SectionLabel('Обычные'),
        const OrbitTile(title: 'Ссылка на подписку', value: 'https://'),
        const OrbitTile(title: 'Xray JSON', subtitle: 'Remnawave, Marzban'),
        const OrbitTile(title: 'Ссылки на серверы', subtitle: 'vless, vmess, trojan, ss, hy2'),
        const OrbitTile(title: 'base64', value: 'список ссылок', divider: false),
      ],
    ),
  );
}

class _EncryptedCard extends StatelessWidget {
  // ignore: prefer_const_constructors_in_immutables
  _EncryptedCard({required this.title, required this.subtitle, required this.formats});

  final String title;
  final String subtitle;
  final List<String> formats;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: OrbitColors.surface, borderRadius: BorderRadius.circular(16)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                // the accent is user-picked and mutable: never const
                color: OrbitColors.accent.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(Icons.lock_outline_rounded, size: 19, color: OrbitColors.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: OrbitText.bodyStrong),
                  const SizedBox(height: 2),
                  Text(subtitle, style: OrbitText.caption),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final f in formats)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: OrbitColors.surfaceHigh, borderRadius: BorderRadius.circular(7)),
                child: Text(f, style: OrbitText.mono.copyWith(fontSize: 11, color: OrbitColors.textPrimary)),
              ),
          ],
        ),
      ],
    ),
  );
}
