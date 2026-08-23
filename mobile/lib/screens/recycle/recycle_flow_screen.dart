import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../core/api_client.dart';
import '../../../core/app_theme.dart';
import '../../../providers/data_providers.dart';
import '../../../providers/providers.dart';
import '../../../services/deposit_status_channel.dart';
import '../../../widgets/station/compartment_status.dart';
import 'deposit_result_screen.dart';

/// Recycle flow driven by the STATION camera (FINAL architecture).
///
/// 1. The phone identifies the physical station (QR / code / list) — it never
///    snaps a photo. `createSession` is capture-first: the backend publishes
///    `capture_request`, the station camera takes the frame, the backend runs
///    the real AI, and only then routes the carriage.
/// 2. This screen watches the live session (capture → analyzing → routing →
///    moving → …) over the WebSocket and renders the phase + compartment rack.
/// 3. Points are ONLY ever the terminal status the backend reports. Nothing
///    here is optimistic.
class RecycleFlowScreen extends ConsumerStatefulWidget {
  final Station station;

  const RecycleFlowScreen({super.key, required this.station});

  @override
  ConsumerState<RecycleFlowScreen> createState() => _RecycleFlowScreenState();
}

enum _FlowPhase { start, creating, live, error }

class _RecycleFlowScreenState extends ConsumerState<RecycleFlowScreen> {
  _FlowPhase _phase = _FlowPhase.start;
  Deposit? _session;
  Deposit? _live;
  String? _error;

  @override
  void initState() {
    super.initState();
    _begin();
  }

  Future<void> _begin() async {
    if (_phase == _FlowPhase.live) return;
    setState(() {
      _phase = _FlowPhase.creating;
      _session = null;
      _live = null;
      _error = null;
    });
    try {
      final repo = ref.read(depositRepositoryProvider);
      final session = await repo.createSession(stationId: widget.station.id);
      if (!mounted) return;
      setState(() {
        _session = session;
        _live = session;
        _phase = _FlowPhase.live;
      });
      _watch(session);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not start the session. Make sure the station is online.';
        _phase = _FlowPhase.error;
      });
    }
  }

  Future<void> _watch(Deposit session) async {
    try {
      final result = await ref
          .read(depositStatusChannelProvider)
          .awaitDeposit(session, onLive: (live) {
        if (!mounted) return;
        setState(() => _live = live);
      });
      if (!mounted) return;
      if (result.deposit.status.isTerminal) {
        _finish(result);
      } else {
        setState(() {
          _phase = _FlowPhase.error;
          _error =
              'The deposit ended in an unexpected state '
              '(${result.deposit.status.apiValue}). Please try again.';
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _phase = _FlowPhase.error;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'The station did not respond in time. Please retry.';
        _phase = _FlowPhase.error;
      });
    }
  }

  void _finish(
      ({Deposit deposit, int pointsAwarded, int challengeBonus}) result) {
    invalidateData(ref);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => DepositResultScreen(result: result),
      ),
    );
  }

  /// Cancels the live session on the BACKEND (so the station stops the flow
  /// and nothing can be awarded after the user leaves), then pops the screen.
  Future<void> _cancel() async {
    final session = _session;
    Navigator.of(context).pop();
    if (session == null || _phase != _FlowPhase.live) return;
    try {
      await ref
          .read(depositRepositoryProvider)
          .cancelSession(session.operationId);
    } catch (_) {
      // The backend expires abandoned sessions on its own; a failed cancel
      // (e.g. offline) must not block navigation.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.station.name),
        leading: _phase == _FlowPhase.live
            ? IconButton(
                tooltip: 'Cancel',
                icon: const Icon(Icons.close),
                onPressed: _cancel,
              )
            : null,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          children: [
            _StationBanner(station: widget.station),
            const SizedBox(height: 16),
            switch (_phase) {
              _FlowPhase.start || _FlowPhase.creating => const _CreatingView(),
              _FlowPhase.error => _ErrorView(message: _error ?? 'Deposit failed.', retry: _begin),
              _FlowPhase.live => _LiveView(live: _live ?? _session!),
            },
          ],
        ),
      ),
    );
  }
}

class _StationBanner extends StatelessWidget {
  final Station station;

  const _StationBanner({required this.station});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.deepGreen,
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on_outlined, color: AppColors.mint, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  station.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  station.stationCode,
                  style: const TextStyle(color: AppColors.mint, fontSize: 11),
                ),
              ],
            ),
          ),
          Icon(
            station.status == 'online' ? Icons.check_circle : Icons.cloud_off,
            color: station.status == 'online' ? AppColors.mint : Colors.white54,
            size: 18,
          ),
        ],
      ),
    );
  }
}

/// Renders the current live phase from the server. The station camera +
/// backend AI classify first (capture/analyzing); once routed, the compartment
/// rack highlights the target. Weight appears once the station measures it.
class _LiveView extends StatelessWidget {
  final Deposit live;

  const _LiveView({required this.live});

  @override
  Widget build(BuildContext context) {
    final status = live.status;
    final label = DepositStatusChannel.phaseLabel(status);
    final isCapturePhase = status.isCapturePhase;
    final targetClass = live.predictedClass;
    final hasRouted = !isCapturePhase &&
        live.expectedPosition > 0 &&
        !status.isTerminal;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            children: [
              if (isCapturePhase)
                const _CameraPulse()
              else
                Icon(
                  switch (status) {
                    DepositStatus.moving ||
                    DepositStatus.routing =>
                      Icons.sync_alt,
                    DepositStatus.ready ||
                    DepositStatus.detecting ||
                    DepositStatus.measuring =>
                      Icons.scale_outlined,
                    _ => Icons.recycling,
                  },
                  size: 42,
                  color: AppColors.green,
                ),
              const SizedBox(height: 14),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.foreground,
                ),
              ),
              const SizedBox(height: 8),
              if (isCapturePhase)
                const Text(
                  'Place your item at the station opening.\nThe station camera '
                  'identifies and routes it automatically.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, color: AppColors.muted),
                )
              else if (hasRouted)
                Text(
                  _routeCopy(status, targetClass),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.muted),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (targetClass != WasteClass.other || hasRouted) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(AppRadii.card),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              children: [
                Text(
                  hasRouted
                      ? 'Routing to compartment #${live.expectedPosition}'
                      : 'Station compartments',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.foreground,
                  ),
                ),
                const SizedBox(height: 12),
                CompartmentRack(
                  openClass: hasRouted ? targetClass : null,
                ),
                if (live.weightGrams > 0) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.monitor_weight_outlined,
                          size: 15, color: AppColors.muted),
                      const SizedBox(width: 6),
                      Text(
                        '${live.weightGrams.toStringAsFixed(1)} g',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.green,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.rewardBg,
            borderRadius: BorderRadius.circular(AppRadii.medium),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, size: 15, color: AppColors.green),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Points are awarded by the station after the physical drop '
                  'is confirmed. Keep the app open until it finishes.',
                  style: TextStyle(fontSize: 10.5, color: AppColors.deepGreen),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _routeCopy(DepositStatus status, WasteClass cls) => switch (status) {
        DepositStatus.routing => 'Moving the item to its compartment…',
        DepositStatus.moving => 'Carriage moving to compartment '
            '#${live.expectedPosition}…',
        DepositStatus.ready => 'Item in place — starting detection…',
        DepositStatus.detecting => 'Detecting the item…',
        DepositStatus.measuring => 'Measuring weight…',
        _ => 'Item identified as ${cls.label}.',
      };
}

class _CameraPulse extends StatefulWidget {
  const _CameraPulse();

  @override
  State<_CameraPulse> createState() => _CameraPulseState();
}

class _CameraPulseState extends State<_CameraPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.78,
      upperBound: 1.0,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _pulse,
      child: Container(
        width: 68,
        height: 68,
        decoration: const BoxDecoration(
          color: AppColors.green,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.sensors, color: Colors.white, size: 30),
      ),
    );
  }
}

class _CreatingView extends StatelessWidget {
  const _CreatingView();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 18),
          Text(
            'Starting session…',
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback retry;

  const _ErrorView({required this.message, required this.retry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.errorBg,
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline, size: 30, color: AppColors.danger),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.foreground,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: retry,
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}
