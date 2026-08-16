import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/app_theme.dart';
import 'analyzing_screen.dart';

/// Scan entry: full-screen camera preview with a capture shutter, plus a
/// gallery fallback. On capture the image bytes are passed up; the flow then
/// runs Analyzing → Result → Station → Deposit → Success.
///
/// The [scan] entry keeps the MVP simple: one frame in, one prediction out.
class ScanFlowRoot extends ConsumerStatefulWidget {
  const ScanFlowRoot({super.key});

  @override
  ConsumerState<ScanFlowRoot> createState() => _ScanFlowRootState();
}

class _ScanFlowRootState extends ConsumerState<ScanFlowRoot> {
  CameraController? _camera;
  List<CameraDescription>? _cameras;
  String? _error;
  bool _ready = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
    } catch (_) {
      _cameras = null;
    }
    if (!mounted) return;
    final back = _cameras?.where((c) => c.lensDirection == CameraLensDirection.back).firstOrNull ??
        _cameras?.firstOrNull;
    if (back == null) {
      setState(() => _error = 'Camera unavailable. Use the gallery instead.');
      return;
    }
    final controller = CameraController(back, ResolutionPreset.medium);
    try {
      await controller.initialize();
    } catch (e) {
      setState(() => _error = 'Camera failed to start. Use the gallery instead.');
      return;
    }
    if (!mounted) return;
    _camera = controller;
    setState(() => _ready = true);
  }

  @override
  void dispose() {
    _camera?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final camera = _camera;
    if (camera == null || _busy) return;
    setState(() => _busy = true);
    try {
      final file = await camera.takePicture();
      final bytes = await file.readAsBytes();
      _open(bytes);
    } catch (_) {
      _showError('Capture failed. Try the gallery instead.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickFromGallery() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        imageQuality: 88,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      _open(bytes);
    } catch (_) {
      _showError('Could not read the selected image.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _open(List<int> bytes) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => AnalyzingScreen(imageBytes: bytes),
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_ready && _camera != null)
            CameraPreview(_camera!) // pixels
          else
            _Fallback(onGallery: _pickFromGallery, error: _error),
          // Controls
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: Colors.white, size: 26),
                    ),
                    const Spacer(),
                    const Text(
                      'Scan Waste',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 26),
                  ],
                ),
              ),
            ),
          ),
          if (_ready && _camera != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 60,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Center the item inside the frame',
                      style: TextStyle(color: Colors.white, fontSize: 12.5),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FloatingActionButton.large(
                        heroTag: 'shutter',
                        backgroundColor: Colors.white,
                        onPressed: _busy ? null : _capture,
                        child: _busy
                            ? const SizedBox(
                                width: 26,
                                height: 26,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5, color: AppColors.green),
                              )
                            : const Icon(Icons.camera_alt, color: Colors.black, size: 30),
                      ),
                      const SizedBox(width: 18),
                      FloatingActionButton.small(
                        heroTag: 'gallery',
                        backgroundColor: Colors.white24,
                        onPressed: _busy ? null : _pickFromGallery,
                        child: const Icon(Icons.photo_library_outlined,
                            color: Colors.white),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Non-camera fallback (permission denied / no device). Offers the gallery as
/// the only capture path so the scan flow still works.
class _Fallback extends StatelessWidget {
  final VoidCallback onGallery;
  final String? error;

  const _Fallback({required this.onGallery, this.error});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined,
                  size: 46, color: Colors.white38),
              const SizedBox(height: 14),
              Text(
                error ?? 'Camera is not available.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white38),
                ),
                onPressed: onGallery,
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: const Text('Choose from gallery'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}