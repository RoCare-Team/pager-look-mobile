import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/network/upload.dart';
import '../../../core/theme/app_theme.dart';

/// One step of the guided scan. `center` is matched against the Aadhaar photo;
/// `left`/`right` prove the head actually moved.
class _ScanPose {
  const _ScanPose(this.id, this.title, this.hint, this.icon);
  final String id;
  final String title;
  final String hint;
  final IconData? icon;
}

const List<_ScanPose> _scanPoses = [
  _ScanPose('center', 'Look straight', 'Keep your face inside the oval', null),
  _ScanPose('left', 'Turn your head left', 'Slowly, keep the phone still', Icons.arrow_back_rounded),
  _ScanPose('right', 'Turn your head right', 'Slowly, keep the phone still', Icons.arrow_forward_rounded),
];

/// Hold time per pose before the frame is taken automatically.
const Duration _holdTime = Duration(milliseconds: 2200);

/// Opens the full-screen guided face scan. Returns `{center, left, right}`
/// frames once all three are captured, or null if the user backs out.
Future<Map<String, PickedDoc>?> openFaceScan(BuildContext context) {
  return Navigator.of(context, rootNavigator: true).push<Map<String, PickedDoc>>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => const _FaceScanPage()),
  );
}

class _FaceScanPage extends StatefulWidget {
  const _FaceScanPage();

  @override
  State<_FaceScanPage> createState() => _FaceScanPageState();
}

class _FaceScanPageState extends State<_FaceScanPage> with SingleTickerProviderStateMixin {
  CameraController? _camera;
  late final AnimationController _hold = AnimationController(vsync: this, duration: _holdTime);
  final Map<String, PickedDoc> _frames = {};
  int _step = 0;
  bool _flash = false;
  bool _closed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _closed = true;
    _hold.dispose();
    _camera?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        front,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (_closed) {
        await controller.dispose();
        return;
      }
      setState(() => _camera = controller);
      await _runScan();
    } on CameraException catch (e) {
      if (mounted) {
        setState(() => _error = e.code == 'CameraAccessDenied'
            ? 'Camera access is off. Allow it in Settings to scan your face.'
            : 'Could not open the camera.');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not open the camera.');
    }
  }

  Future<void> _runScan() async {
    // A moment to settle into the oval before the first hold starts.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    for (var i = 0; i < _scanPoses.length; i++) {
      if (_closed) return;
      setState(() => _step = i);
      await _hold.forward(from: 0).orCancel.catchError((_) {});
      if (_closed) return;
      final frame = await _takeFrame(_scanPoses[i].id);
      if (frame == null) return;
      _frames[_scanPoses[i].id] = frame;
    }
    if (!_closed && mounted) Navigator.of(context).pop(Map<String, PickedDoc>.of(_frames));
  }

  Future<PickedDoc?> _takeFrame(String id) async {
    final camera = _camera;
    if (camera == null) return null;
    try {
      final shot = await camera.takePicture();
      HapticFeedback.lightImpact();
      if (mounted) setState(() => _flash = true);
      Future<void>.delayed(const Duration(milliseconds: 160), () {
        if (mounted) setState(() => _flash = false);
      });
      return PickedDoc(
        path: shot.path,
        name: 'face_$id.jpg',
        size: await File(shot.path).length(),
        mimeType: 'image/jpeg',
      );
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not take the photo. Please try again.');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pose = _scanPoses[_step];
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  // ── Top bar: close + step dots ─────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Close',
                          icon: const Icon(Icons.close_rounded, color: Colors.white),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const Spacer(),
                        for (var i = 0; i < _scanPoses.length; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            width: i == _step ? 24 : 8,
                            height: 8,
                            margin: const EdgeInsets.only(left: 6),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(99),
                              color: _frames.containsKey(_scanPoses[i].id)
                                  ? AppColors.success
                                  : (i == _step ? Colors.white : Colors.white24),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Prompt ─────────────────────────────────────────────────
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Column(
                      key: ValueKey(_error ?? pose.id),
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (pose.icon == Icons.arrow_back_rounded && _error == null) ...[
                              const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 26),
                              const SizedBox(width: 8),
                            ],
                            Text(
                              _error == null ? pose.title : 'Face scan stopped',
                              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white),
                            ),
                            if (pose.icon == Icons.arrow_forward_rounded && _error == null) ...[
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 26),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            _error ?? pose.hint,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 14.5, color: Colors.white70),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Camera in an oval with the hold ring ───────────────────
                  Expanded(child: Center(child: _buildViewfinder())),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: _error != null
                        ? SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: AppColors.brand600,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Close', style: TextStyle(fontWeight: FontWeight.w700)),
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.lock_outline_rounded, size: 15, color: Colors.white54),
                              SizedBox(width: 6),
                              Text('Photos are encrypted and only used to verify you',
                                  style: TextStyle(fontSize: 12.5, color: Colors.white54)),
                            ],
                          ),
                  ),
                ],
              ),
              IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _flash ? 0.7 : 0,
                  duration: const Duration(milliseconds: 120),
                  child: Container(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildViewfinder() {
    const width = 260.0;
    const height = 340.0;
    final camera = _camera;
    final previewSize = camera?.value.previewSize;

    final Widget preview = (camera != null && camera.value.isInitialized && previewSize != null)
        ? FittedBox(
            fit: BoxFit.cover,
            // previewSize is reported in landscape; the phone is held upright.
            child: SizedBox(width: previewSize.height, height: previewSize.width, child: CameraPreview(camera)),
          )
        : const ColoredBox(
            color: Color(0xFF1A1A1A),
            child: Center(child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2)),
          );

    return SizedBox(
      width: width + 24,
      height: height + 24,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ClipOval(child: SizedBox(width: width, height: height, child: preview)),
          AnimatedBuilder(
            animation: _hold,
            builder: (_, __) => CustomPaint(
              size: const Size(width + 16, height + 16),
              painter: _OvalRingPainter(progress: _hold.value),
            ),
          ),
        ],
      ),
    );
  }
}

/// Oval track with a green arc that fills while the user holds the pose.
class _OvalRingPainter extends CustomPainter {
  _OvalRingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final track = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;
    canvas.drawOval(rect, track);
    if (progress <= 0) return;

    final fill = Paint()
      ..color = AppColors.success
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5;
    // Fill clockwise from the top of the oval.
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * progress, false, fill);
  }

  @override
  bool shouldRepaint(_OvalRingPainter old) => old.progress != progress;
}
