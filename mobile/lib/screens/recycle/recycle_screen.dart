import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../core/app_theme.dart';
import '../../../providers/data_providers.dart';
import 'qr_scanner_screen.dart';
import 'recycle_flow_screen.dart';

/// Recycle entry: the user's phone identifies a physical EcoLoop station by
/// scanning its QR (or entering the code / picking from the list). The STATION
/// camera — not the phone — then classifies the item; this screen never snaps a
/// photo and never talks to the AI endpoint.
class RecycleScreen extends ConsumerStatefulWidget {
  const RecycleScreen({super.key});

  @override
  ConsumerState<RecycleScreen> createState() => _RecycleScreenState();
}

class _RecycleScreenState extends ConsumerState<RecycleScreen> {
  final _codeController = TextEditingController();
  String? _manualError;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (code == null || !mounted) return;
    _useStationFromCode(code);
  }

  Future<void> _manual() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _manualError = 'Enter the station code shown on the unit.');
      return;
    }
    _useStationFromCode(code);
  }

  /// Resolves a scanned/typed code (e.g. `ST-001`) against the backend station
  /// list. Unknown stations are rejected — the deposit must target a real unit.
  Future<void> _useStationFromCode(String raw) async {
    final code = raw.trim().toUpperCase();
    final stations = await ref.read(stationsProvider.future);
    final match = stations.where((s) {
      return s.stationCode.toUpperCase() == code ||
          s.id.toUpperCase() == code;
    }).firstOrNull;
    if (match == null) {
      if (mounted) {
        setState(() => _manualError =
            'Unknown station "$code". Scan the QR on an EcoLoop station.');
      }
      return;
    }
    if (mounted) _start(match);
  }

  void _start(Station station) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecycleFlowScreen(station: station),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stationsAsync = ref.watch(stationsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Recycle')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.deepGreen,
                borderRadius: BorderRadius.circular(AppRadii.card),
              ),
              child: const Row(
                children: [
                  Icon(Icons.qr_code_scanner, color: AppColors.mint, size: 30),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Recycle at an EcoLoop station',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Scan the station QR, then place your item at the '
                          'opening. The station camera identifies and routes it '
                          '— your phone only confirms the drop.',
                          style: TextStyle(color: AppColors.mint, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: _scan,
              icon: const Icon(Icons.qr_code_scanner, size: 20),
              label: const Text('Scan station QR'),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(AppRadii.medium),
                border: Border.all(color: AppColors.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Enter station code',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.foreground),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _codeController,
                          textCapitalization: TextCapitalization.characters,
                          decoration: InputDecoration(
                            hintText: 'e.g. ST-001',
                            errorText: _manualError,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                          ),
                          onChanged: (_) {
                            if (_manualError != null) {
                              setState(() => _manualError = null);
                            }
                          },
                          onSubmitted: (_) => _manual(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        height: 46,
                        child: ElevatedButton(
                          onPressed: _manual,
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(0, 46),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                          ),
                          child: const Text('Go'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Available stations',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.foreground,
              ),
            ),
            const SizedBox(height: 8),
            stationsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  'Could not load stations. Check your connection.',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ),
              data: (stations) => stations.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        'No stations registered yet.',
                        style:
                            TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                    )
                  : Column(
                      children: [
                        for (final s in stations)
                          _StationTile(station: s, onTap: () => _start(s)),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StationTile extends StatelessWidget {
  final Station station;
  final VoidCallback onTap;

  const _StationTile({required this.station, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final online = station.status == 'online';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.medium),
        side: BorderSide(
            color: online ? AppColors.line : AppColors.danger.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.medium),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: online
                      ? AppColors.rewardBg
                      : AppColors.errorBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  online
                      ? Icons.recycling
                      : Icons.cloud_off_outlined,
                  color: online ? AppColors.green : AppColors.danger,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      station.name,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.foreground,
                      ),
                    ),
                    Text(
                      station.stationCode,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: online
                      ? AppColors.green.withValues(alpha: 0.12)
                      : AppColors.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  online ? 'Online' : 'Offline',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: online ? AppColors.green : AppColors.danger,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, size: 18, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}