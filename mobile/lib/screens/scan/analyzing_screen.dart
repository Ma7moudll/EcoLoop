import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../../../core/app_theme.dart';
import '../../../providers/providers.dart';
import 'prediction_result_screen.dart';

/// Shows a scanning animation while the image is sent to the backend AI,
/// then replaces itself with the prediction result. On error the user can
/// retake the photo.
class AnalyzingScreen extends ConsumerStatefulWidget {
  final List<int> imageBytes;

  const AnalyzingScreen({super.key, required this.imageBytes});

  @override
  ConsumerState<AnalyzingScreen> createState() => _AnalyzingScreenState();
}

class _AnalyzingScreenState extends ConsumerState<AnalyzingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.72,
      upperBound: 1.0,
    )..repeat(reverse: true);
    _analyze();
  }

  Future<void> _analyze() async {
    try {
      final classifier = ref.read(aiClassifierProvider);
      final prediction = await classifier.predictImage(widget.imageBytes);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => PredictionResultScreen(prediction: prediction),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to analyze the image.');
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _back() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEDF4F0),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_error == null) ...[
                  ScaleTransition(
                    scale: _pulse,
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: const BoxDecoration(
                        color: AppColors.green,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.center_focus_strong,
                          color: Colors.white, size: 38),
                    ),
                  ),
                  const SizedBox(height: 26),
                  const Text(
                    'Analyzing your waste…',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.foreground,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Identifying material & recyclability',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                  const SizedBox(height: 18),
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                ] else ...[
                  const Icon(Icons.error_outline,
                      size: 44, color: AppColors.danger),
                  const SizedBox(height: 14),
                  const Text(
                    'Analysis failed',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.foreground,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    onPressed: _back,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Retake photo'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}