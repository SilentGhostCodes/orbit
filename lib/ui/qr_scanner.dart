import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:orbit/theme/orbit_theme.dart';

/// Opens the camera and returns the first QR code's text, or null if the user backs out.
Future<String?> scanQr(BuildContext context) =>
    Navigator.of(context, rootNavigator: true).push<String>(MaterialPageRoute(builder: (_) => const _QrScannerPage()));

class _QrScannerPage extends StatefulWidget {
  const _QrScannerPage();

  @override
  State<_QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<_QrScannerPage> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      title: const Text('QR-код', style: OrbitText.sheetTitle),
      actions: [
        IconButton(icon: const Icon(Icons.flash_on_rounded), onPressed: _controller.toggleTorch),
      ],
    ),
    body: Stack(
      alignment: Alignment.center,
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: (capture) {
            final value = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
            if (value == null || _done) return;
            _done = true;
            Navigator.of(context).pop(value.trim());
          },
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'Нет доступа к камере.\nРазрешите его в настройках Android.',
                textAlign: TextAlign.center,
                style: OrbitText.body.copyWith(color: OrbitColors.textSecondary),
              ),
            ),
          ),
        ),
        IgnorePointer(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: OrbitColors.accent, width: 2),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
      ],
    ),
  );
}
