import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import 'scan_routing.dart';

/// Camera scanner for PagerLook QR codes (`/scan`): company join QRs,
/// Professional ID / public profile QRs, and invitation / verification links.
/// The scanned link is mapped onto the matching in-app route by
/// [routeForScannedValue]. Join codes can also be typed in.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> with WidgetsBindingObserver {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
    formats: const [BarcodeFormat.qrCode],
  );
  final TextEditingController _code = TextEditingController();

  /// Set once a code has been accepted, so a burst of detections navigates once.
  bool _handled = false;

  /// The last unrecognised value, so it doesn't re-toast on every frame.
  String? _lastRejected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  /// Release the camera while the app is in the background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_controller.value.isInitialized) return;
    if (state == AppLifecycleState.resumed) {
      if (!_handled) _safely(_controller.start);
    } else if (state == AppLifecycleState.inactive) {
      _safely(_controller.stop);
    }
  }

  /// Camera calls can throw (no torch, already running…); never crash on them.
  Future<void> _safely(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _code.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled || !mounted || capture.barcodes.isEmpty) return;
    final raw = capture.barcodes.first.rawValue;
    if (raw == null || raw.trim().isEmpty) return;

    final route = routeForScannedValue(raw);
    if (route == null) {
      if (raw == _lastRejected) return;
      _lastRejected = raw;
      showToast("This isn't a PagerLook QR code. Try another one.", type: ToastType.error);
      return;
    }
    _go(route);
  }

  void _go(String route) {
    if (_handled) return;
    _handled = true;
    // Replacing this route disposes the controller, which releases the camera.
    context.pushReplacement(route);
  }

  void _submitCode() {
    final route = routeForJoinCode(_code.text);
    if (route == null) {
      showToast('Enter the join code shown under the QR, or paste a PagerLook link.', type: ToastType.error);
      return;
    }
    FocusScope.of(context).unfocus();
    _go(route);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR code'),
        actions: [
          IconButton(
            tooltip: 'Toggle flashlight',
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: () => _safely(_controller.toggleTorch),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            const PageIntro(
              title: 'Scan a PagerLook QR code',
              subtitle: 'Point your camera at a company joining QR or a Professional ID to open it.',
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.card),
              child: AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: AppColors.inkStrong,
                      child: MobileScanner(
                        controller: _controller,
                        onDetect: _onDetect,
                        errorBuilder: (context, error, child) => _ScannerError(error: error),
                      ),
                    ),
                    IgnorePointer(
                      child: Center(
                        child: FractionallySizedBox(
                          widthFactor: 0.65,
                          heightFactor: 0.65,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 2.5),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            AppCard(
              title: 'Enter code manually',
              subtitle: "Can't scan? Type the join code printed with the QR, or paste a PagerLook link.",
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppTextField(
                    controller: _code,
                    hint: 'Join code or link',
                    prefixIcon: Icons.keyboard_outlined,
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) => _submitCode(),
                  ),
                  const SizedBox(height: 12),
                  AppButton(label: 'Continue', onPressed: _submitCode),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScannerError extends StatelessWidget {
  const _ScannerError({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    final unsupported = error.errorCode == MobileScannerErrorCode.unsupported;
    final message = denied
        ? 'Camera access is turned off for PagerLook. Allow camera access in your device settings, '
            'or enter the code below.'
        : unsupported
            ? 'Scanning is not supported on this device. Enter the code below instead.'
            : 'The camera could not be started. Enter the code below instead.';

    return ColoredBox(
      color: AppColors.inkStrong,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                denied ? Icons.no_photography_outlined : Icons.videocam_off_outlined,
                size: 40,
                color: Colors.white.withValues(alpha: 0.85),
              ),
              const SizedBox(height: 12),
              Text(
                denied ? 'Camera permission needed' : 'Camera unavailable',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, height: 1.4, color: Colors.white.withValues(alpha: 0.75)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
