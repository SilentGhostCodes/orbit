import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orbit/core/libxray.dart';
import 'package:orbit/state/providers.dart';
import 'package:orbit/theme/orbit_theme.dart';
import 'package:orbit/widgets/orbit_widgets.dart';

final _xrayVersionProvider = FutureProvider.autoDispose<String>((ref) => LibXray.version());

class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boot = ref.watch(bootProvider);
    final version = boot.version;
    final build = boot.build.isEmpty ? null : boot.build;
    final xray = ref.watch(_xrayVersionProvider).value;
    return Scaffold(
      appBar: AppBar(titleSpacing: 0, title: const Text('О приложении', style: OrbitText.sheetTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        children: [
          const Center(child: OrbitLogo(size: 72)),
          const SizedBox(height: 18),
          const Center(child: Text('Orbit', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700))),
          const SizedBox(height: 6),
          Center(
            child: Text('Версия $version${build == null ? '' : ' · сборка $build'}', style: OrbitText.caption),
          ),
          const SizedBox(height: 28),
          OrbitTile(title: 'Версия приложения', value: version),
          if (build != null) OrbitTile(title: 'Сборка', value: build),
          OrbitTile(title: 'Ядро', value: xray == null ? 'Xray-core' : 'Xray-core $xray'),
          const OrbitTile(title: 'Протоколы', value: 'VLESS, VMess, Trojan, Shadowsocks, Hysteria2'),
          const OrbitTile(title: 'Подписки', value: 'Xray JSON, ссылки, base64, incy://, happ://'),
          if (boot.device != null) ...[
            OrbitTile(
              title: 'Устройство',
              subtitle: 'Android ${boot.device!.osVersion}'.trim(),
              value: boot.device!.model.isEmpty ? null : boot.device!.model,
            ),
            OrbitTile(
              title: 'HWID',
              subtitle: boot.device!.hwid,
              divider: false,
              trailing: const Icon(Icons.copy_rounded, size: 18, color: OrbitColors.textSecondary),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: boot.device!.hwid));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('HWID скопирован')));
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}
