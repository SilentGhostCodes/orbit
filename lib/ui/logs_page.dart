import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orbit/state/providers.dart';
import 'package:orbit/theme/orbit_theme.dart';
import 'package:orbit/widgets/orbit_widgets.dart';

/// The VPN service's own log (start, stop, errors) and Xray's error log, newest last.
class LogsPage extends ConsumerStatefulWidget {
  const LogsPage({super.key});

  @override
  ConsumerState<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends ConsumerState<LogsPage> {
  String _text = '';

  List<File> get _files {
    final xray = File(ref.read(bootProvider).logPath);
    return [File('${xray.parent.path}/service.log'), xray];
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final parts = <String>[];
    for (final f in _files) {
      if (!await f.exists()) continue;
      final content = await f.readAsString();
      // the last 64 KB is plenty and keeps the page quick
      final tail = content.length > 65536 ? content.substring(content.length - 65536) : content;
      if (tail.trim().isNotEmpty) parts.add('── ${f.uri.pathSegments.last} ──\n${tail.trim()}');
    }
    if (mounted) setState(() => _text = parts.join('\n\n'));
  }

  @override
  Widget build(BuildContext context) {
    final debug = ref.watch(settingsProvider.select((s) => s.debugLog));
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: const Text('Логи', style: OrbitText.sheetTitle),
        actions: [
          IconButton(tooltip: 'Обновить', icon: const Icon(Icons.refresh_rounded), onPressed: _load),
          IconButton(
            tooltip: 'Скопировать',
            icon: const Icon(Icons.copy_rounded),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _text));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Логи скопированы')));
              }
            },
          ),
          IconButton(
            tooltip: 'Очистить',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () async {
              for (final f in _files) {
                if (await f.exists()) await f.writeAsString('');
              }
              await _load();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: OrbitSwitchTile(
              title: 'Подробные логи',
              subtitle: 'Применится при следующем подключении',
              value: debug,
              onChanged: (v) => ref.read(settingsProvider.notifier).change((s) => s.copyWith(debugLog: v), reconnect: true),
            ),
          ),
          Expanded(
            child: _text.isEmpty
                ? const Center(child: Text('Логи пусты', style: OrbitText.caption))
                : SingleChildScrollView(
                    reverse: true,
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(_text, style: OrbitText.mono.copyWith(fontSize: 11, height: 1.5)),
                  ),
          ),
        ],
      ),
    );
  }
}
