import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../core/api_client.dart';
import '../../../core/app_config.dart';
import '../../../core/app_theme.dart';
import '../../../providers/data_providers.dart';
import '../../../providers/providers.dart';
import '../../../widgets/station/deposit_steps.dart';
import 'deposit_success_screen.dart';

/// Runs the physical deposit session against the backend. Points are awarded
/// ONLY by the server after a confirmed drop; this screen never writes points
/// locally. It shows the live session state (weight, compartment, expiry) and
/// surfaces mechanical rejections (wrong compartment / low weight) verbatim.
class DepositScreen extends ConsumerStatefulWidget {
  final Prediction prediction;

  const DepositScreen({super.key, required this.prediction});

  @override
  ConsumerState<DepositScreen> createState() => _DepositScreenState();
}

enum _DepositPhase { creating, ready, submitting, rejected, error }

class _DepositScreenState extends ConsumerState<DepositScreen> {
  _DepositPhase _phase = _DepositPhase.creating;
  Deposit? _session;
  String? _message;
  bool _placed = false;

  @override
  void initState() {
    super.initState();
    _createSession();
  }

  Future<void> _createSession() async {
    setState(() => _phase = _DepositPhase.creating);
    try {
      final repo = ref.read(depositRepositoryProvider);
      final session = await repo.createSession(
        predictionId: widget.prediction.predictionId,
        stationId: Station.defaultStation.id,
      );
      if (!mounted) return;
      setState(() {
        _session = session;
        _phase = _DepositPhase.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _message = 'Could not start the deposit session.';
        _phase = _DepositPhase.error;
      });
    }
  }

  Future<void> _placeItem() async {
    if (_phase != _DepositPhase.ready) return;
    setState(() => _placed = true);
  }

  Future<void> _confirmDrop() async {
    final session = _session;
    if (session == null || _phase != _DepositPhase.ready) return;
    setState(() => _phase = _DepositPhase.submitting);
    try {
      final repo = ref.read(depositRepositoryProvider);
      final result = await repo.confirm(
        operationId: session.operationId,
        actualPosition: session.expectedPosition,
        weightGrams: AppConfig.simulatedWeightGrams,
        mechanicalConfirmed: true,
      );
      if (!mounted) return;
      if (result.deposit.status == DepositStatus.rejected) {
        setState(() {
          _message = result.deposit.rejectReason ?? 'Deposit rejected.';
          _phase = _DepositPhase.rejected;
        });
        return;
      }
      invalidateData(ref);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => DepositSuccessScreen(
            result: result,
            prediction: widget.prediction,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _message = e.message;
        _phase = _DepositPhase.error;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = 'Deposit failed. Please try again.';
        _phase = _DepositPhase.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final compartment =
        compartmentForClass(widget.prediction.predictedClass);
    final busy = _phase == _DepositPhase.creating ||
        _phase == _DepositPhase.submitting;

    return Scaffold(
      appBar: AppBar(title: const Text('Deposit at station')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          children: [
            // Session header
            if (session != null) ...[
              Row(
                children: [
                  const Text(
                    'Operation',
                    style: TextStyle(fontSize: 11, color: AppColors.muted),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.line.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      session.operationId,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Compart. #${session.expectedPosition}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.fromHex(compartment.colorHex),
                    ),
                  ),
                  const DemoBadgeInline(),
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (busy) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 42),
                child: Center(child: CircularProgressIndicator()),
              ),
              Center(
                child: Text(
                  _phase == _DepositPhase.creating
                      ? 'Starting session…'
                      : 'Confirming deposit…',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ),
            ] else if (_phase == _DepositPhase.error ||
                _phase == _DepositPhase.rejected) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _phase == _DepositPhase.rejected
                      ? AppColors.orange.withValues(alpha: 0.1)
                      : AppColors.errorBg,
                  borderRadius: BorderRadius.circular(AppRadii.medium),
                ),
                child: Column(
                  children: [
                    Icon(
                      _phase == _DepositPhase.rejected
                          ? Icons.report_problem_outlined
                          : Icons.error_outline,
                      color: _phase == _DepositPhase.rejected
                          ? AppColors.orange
                          : AppColors.danger,
                      size: 30,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _message ?? 'Deposit rejected.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.foreground,
                      ),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _phase = _DepositPhase.ready;
                          _placed = false;
                        });
                      },
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            ] else
              _ReadySteps(
                session: session!,
                placed: _placed,
                onPlace: _placeItem,
                onDrop: _confirmDrop,
              ),
            const SizedBox(height: 18),
            // Always-visible guidance
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(AppRadii.medium),
                border: Border.all(color: AppColors.line),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.touch_app_outlined, size: 17, color: AppColors.muted),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Place the item at the station opening, wait for the '
                      'weight to register, then start the drop. The carriage '
                      'moves it into the correct compartment automatically.',
                      style: TextStyle(fontSize: 11, color: AppColors.muted),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadySteps extends StatelessWidget {
  final Deposit session;
  final bool placed;
  final VoidCallback onPlace;
  final VoidCallback onDrop;

  const _ReadySteps({
    required this.session,
    required this.placed,
    required this.onPlace,
    required this.onDrop,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DepositSteps(weightChecked: placed, deposited: false),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Station reading',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                  const Spacer(),
                  Text(
                    '${session.weightGrams.toStringAsFixed(1)} g',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.green,
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              _StepAction(
                step: 1,
                title: placed
                    ? 'Item placed — weight registered'
                    : 'Place the item at the opening',
                done: placed,
                onTap: placed ? null : onPlace,
              ),
              const SizedBox(height: 8),
              _StepAction(
                step: 2,
                title: placed ? 'Start the drop' : 'Mark placement first',
                done: false,
                onTap: placed ? onDrop : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepAction extends StatelessWidget {
  final int step;
  final String title;
  final bool done;
  final VoidCallback? onTap;

  const _StepAction({
    required this.step,
    required this.title,
    required this.done,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: done ? AppColors.rewardBg : AppColors.appSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: done ? AppColors.green : AppColors.line,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 13,
              backgroundColor:
                  done ? AppColors.green : AppColors.line.withValues(alpha: 0.7),
              child: done
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : Text(
                      '$step',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.muted,
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: done ? AppColors.green : AppColors.foreground,
                ),
              ),
            ),
            Icon(onTap == null && !done ? Icons.lock : Icons.chevron_right,
                size: 17, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

/// Small subtle mark for the demo-mode deposit (noisy, but honest).
class DemoBadgeInline extends StatelessWidget {
  const DemoBadgeInline({super.key});

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.demoMode) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.yellow.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        'DEMO',
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: Color(0xFF8a5a00),
        ),
      ),
    );
  }
}