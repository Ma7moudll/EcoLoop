import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../core/api_client.dart';
import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../core/idempotency_key.dart';
import '../providers/data_providers.dart';
import '../providers/providers.dart';
import '../widgets/brand_app_bar.dart';
import '../widgets/state_views.dart';

/// Rewards marketplace: exchange points for cash payouts, campus food
/// discounts and copy credit. Redemption is server-atomic; this screen only
/// collects the confirmation (and payout destination for cash rewards).
class RewardsScreen extends ConsumerWidget {
  const RewardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogAsync = ref.watch(rewardsCatalogProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BrandAppBar(
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                  builder: (_) => const MyRedemptionsScreen()),
            ),
            icon: const Icon(Icons.redeem_outlined, size: 18),
            label: const Text('My rewards',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: catalogAsync.when(
        loading: () => const LoadingView(message: 'Loading rewards…'),
        error: (e, _) => ErrorView(
          message: e is ApiException ? e.message : 'Could not load rewards.',
          onRetry: () => ref.invalidate(rewardsCatalogProvider),
        ),
        data: (catalog) {
          if (catalog.rewards.isEmpty) {
            return const EmptyView(
              icon: Icons.card_giftcard_outlined,
              title: 'No rewards available yet',
              subtitle:
                  'The admin team is preparing the catalog. Keep recycling — your points are safe.',
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _BalanceHeader(balance: catalog.balance),
              const SizedBox(height: 12),
              ...catalog.rewards.map(
                (r) => _RewardCard(
                  reward: r,
                  balance: catalog.balance,
                  onTap: () => _confirmRedeem(context, ref, r, catalog.balance),
                ),
              ),
              const SizedBox(height: 8),
              const _HowItWorks(),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmRedeem(
      BuildContext context, WidgetRef ref, Reward reward, int balance) async {
    final key = newIdempotencyKey();
    final destination = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.large)),
      ),
      builder: (_) => _RedeemSheet(reward: reward, balance: balance),
    );
    if (destination == null || !context.mounted) return;

    try {
      final result = await ref.read(dataRepositoryProvider).redeemReward(
            reward.id,
            idempotencyKey: key,
            destination: destination,
          );
      ref.invalidate(rewardsCatalogProvider);
      ref.invalidate(myRedemptionsProvider);
      ref.invalidate(currentUserProvider);
      if (!context.mounted) return;
      _showSuccess(context, reward, result.redemption.codeOrPending(),
          result.balance);
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
      );
      ref.invalidate(rewardsCatalogProvider);
    }
  }

  void _showSuccess(
      BuildContext context, Reward reward, String headline, int balance) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.large)),
      ),
      builder: (_) => _SuccessSheet(
          reward: reward, headline: headline, balance: balance),
    );
  }
}

extension on RewardRedemption {
  /// What the success sheet shows: the merchant code for code rewards, a
  /// pending note for cash payouts.
  String codeOrPending() =>
      redemptionCode ?? 'Request received — the admin team will process your payout.';
}

class _BalanceHeader extends StatelessWidget {
  final int balance;
  const _BalanceHeader({required this.balance});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.deepGreen, AppColors.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppRadii.small),
            ),
            child: const Icon(Icons.stars_outlined, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Your balance',
                  style: TextStyle(fontSize: 11, color: Colors.white70)),
              Text(Fmt.points(balance),
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
            ],
          ),
        ],
      ),
    );
  }
}

class _RewardCard extends StatelessWidget {
  final Reward reward;
  final int balance;
  final VoidCallback? onTap;

  const _RewardCard({
    required this.reward,
    required this.balance,
    this.onTap,
  });

  IconData get _icon {
    switch (reward.category) {
      case 'cash':
        return Icons.account_balance_wallet_outlined;
      case 'food':
        return Icons.local_cafe_outlined;
      case 'printing':
        return Icons.print_outlined;
      default:
        return Icons.sell_outlined;
    }
  }

  bool get _affordable => balance >= reward.pointsCost;
  bool get _soldOut => reward.stock != null && reward.stock! <= 0;

  @override
  Widget build(BuildContext context) {
    final disabled = !_affordable || _soldOut;
    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadii.medium),
            border: Border.all(color: AppColors.line.withValues(alpha: 0.6)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.rewardBg,
                  borderRadius: BorderRadius.circular(AppRadii.small),
                ),
                child: Icon(_icon, color: AppColors.green, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            reward.name,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: AppColors.foreground),
                          ),
                        ),
                        if (_soldOut)
                          const _Chip(label: 'Sold out',
                              bg: AppColors.errorBg, fg: AppColors.danger)
                        else
                          _Chip(label: '${reward.pointsCost} pts',
                              bg: AppColors.yellow.withValues(alpha: 0.14),
                              fg: const Color(0xFF8a5a00)),
                      ],
                    ),
                    if (reward.provider.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(reward.provider,
                            style: const TextStyle(
                                fontSize: 10.5, color: AppColors.muted)),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      _subtitle,
                      style: const TextStyle(
                          fontSize: 10.5, color: AppColors.muted),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            reward.valueLabel,
                            style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.green),
                          ),
                        ),
                        if (!_affordable && !_soldOut) ...[
                          const SizedBox(width: 6),
                          Text(
                            'Need ${reward.pointsCost - balance} more pts',
                            style: const TextStyle(
                                fontSize: 9.5, color: AppColors.muted),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _subtitle {
    if (reward.description.isNotEmpty) return reward.description;
    return reward.requiresDestination
        ? 'Paid out to your number by the admin team.'
        : 'Issued instantly as a code.';
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  const _Chip({required this.label, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 9.5, fontWeight: FontWeight.w800, color: fg)),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.appSurface,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: Border.all(color: AppColors.line.withValues(alpha: 0.6)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How it works',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.foreground)),
          SizedBox(height: 6),
          Text(
            '• Discount and printing rewards give you an instant code.\n'
            '• Cash rewards are reviewed by the admin team, then sent to your number.\n'
            '• Unused codes can be cancelled anytime to get your points back.',
            style: TextStyle(fontSize: 10.5, height: 1.5, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

/// Confirm-before-redeem sheet. Returns the payout destination string for
/// cash rewards ('' when none needed), or null when dismissed.
class _RedeemSheet extends StatefulWidget {
  final Reward reward;
  final int balance;
  const _RedeemSheet({required this.reward, required this.balance});

  @override
  State<_RedeemSheet> createState() => _RedeemSheetState();
}

class _RedeemSheetState extends State<_RedeemSheet> {
  final _destination = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _destination.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.reward.requiresDestination &&
        _destination.text.trim().length < 6) {
      setState(() => _error =
          'Enter the ${widget.reward.provider} number that should receive the payout.');
      return;
    }
    Navigator.of(context).pop(_destination.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.reward;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(r.name,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.foreground)),
          const SizedBox(height: 4),
          Text('${r.valueLabel} · ${r.pointsCost} pts',
              style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 14),
          if (r.requiresDestination) ...[
            TextField(
              controller: _destination,
              keyboardType: TextInputType.phone,
              autofocus: true,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+@.\-\s]'))],
              decoration: InputDecoration(
                labelText: '${r.provider} number / handle',
                hintText: 'e.g. 01012345678',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
          ] else ...[
            const Text(
              'A one-time code will be issued immediately after redeeming. '
              'You can cancel it later to get your points back.',
              style: TextStyle(fontSize: 11.5, height: 1.5, color: AppColors.muted),
            ),
            const SizedBox(height: 14),
          ],
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.redeem_outlined, size: 18),
              label: Text('Redeem for ${r.pointsCost} pts'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuccessSheet extends StatelessWidget {
  final Reward reward;
  final String headline;
  final int balance;
  const _SuccessSheet({
    required this.reward,
    required this.headline,
    required this.balance,
  });

  @override
  Widget build(BuildContext context) {
    final hasCode = reward.requiresDestination == false && headline.startsWith('ECO-');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
                color: AppColors.rewardBg, shape: BoxShape.circle),
            child: const Icon(Icons.check_circle_outline,
                color: AppColors.green, size: 34),
          ),
          const SizedBox(height: 12),
          Text(hasCode ? 'Here is your code' : reward.name,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.foreground)),
          const SizedBox(height: 6),
          if (hasCode)
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: headline));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Code copied')));
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(AppRadii.small),
                  border: Border.all(color: AppColors.line),
                ),
                child: Text(headline,
                    style: const TextStyle(
                        fontSize: 20,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w800,
                        color: AppColors.deepGreen)),
              ),
            )
          else
            Text(headline,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12, height: 1.5, color: AppColors.muted)),
          const SizedBox(height: 8),
          Text('New balance: ${Fmt.points(balance)}',
              style: const TextStyle(fontSize: 11, color: AppColors.muted)),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Redemption history: codes, statuses, cancellation of unused codes.
class MyRedemptionsScreen extends ConsumerWidget {
  const MyRedemptionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final redemptionsAsync = ref.watch(myRedemptionsProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('My rewards',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: redemptionsAsync.when(
        loading: () => const LoadingView(message: 'Loading your redemptions…'),
        error: (e, _) => ErrorView(
          message:
              e is ApiException ? e.message : 'Could not load your redemptions.',
          onRetry: () => ref.invalidate(myRedemptionsProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyView(
              icon: Icons.redeem_outlined,
              title: 'Nothing redeemed yet',
              subtitle: 'Exchange your points in the Rewards section.',
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: items.map((r) => _RedemptionRow(redemption: r)).toList(),
          );
        },
      ),
    );
  }
}

class _RedemptionRow extends ConsumerWidget {
  final RewardRedemption redemption;
  const _RedemptionRow({required this.redemption});

  ({String label, Color bg, Color fg}) get _statusStyle {
    switch (redemption.status) {
      case 'available':
        return (label: 'Available', bg: AppColors.rewardBg, fg: AppColors.green);
      case 'pending':
        return (
          label: 'Processing',
          bg: AppColors.yellow.withValues(alpha: 0.14),
          fg: const Color(0xFF8a5a00)
        );
      case 'approved':
        return (label: 'Approved', bg: AppColors.mint, fg: AppColors.deepGreen);
      case 'fulfilled':
      case 'used':
        return (label: 'Completed', bg: AppColors.mint, fg: AppColors.deepGreen);
      case 'rejected':
        return (label: 'Rejected', bg: AppColors.errorBg, fg: AppColors.danger);
      default:
        return (label: 'Cancelled', bg: AppColors.line, fg: AppColors.muted);
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(dataRepositoryProvider).cancelRedemption(redemption.id);
      ref.invalidate(myRedemptionsProvider);
      ref.invalidate(rewardsCatalogProvider);
      ref.invalidate(currentUserProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cancelled — points refunded')),
        );
      }
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = _statusStyle;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: Border.all(color: AppColors.line.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(redemption.rewardName,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.foreground)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: s.bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(s.label,
                    style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: s.fg)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '-${Fmt.points(redemption.pointsSpent)}'
            ' · ${redemption.valueLabel}'
            '${redemption.destinationMasked != null ? ' · to ${redemption.destinationMasked}' : ''}',
            style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
          ),
          if (redemption.showsCode) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Text(redemption.redemptionCode!,
                    style: const TextStyle(
                        fontSize: 15,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.deepGreen)),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    Clipboard.setData(
                        ClipboardData(text: redemption.redemptionCode!));
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Code copied')));
                  },
                  icon: const Icon(Icons.copy_outlined,
                      size: 16, color: AppColors.muted),
                ),
              ],
            ),
          ],
          if (redemption.adminNote != null) ...[
            const SizedBox(height: 4),
            Text('Note from the team: ${redemption.adminNote}',
                style:
                    const TextStyle(fontSize: 10, color: AppColors.muted)),
          ],
          if (redemption.isCancellable) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _cancel(context, ref),
                icon: const Icon(Icons.undo_outlined, size: 15),
                label: const Text('Cancel & refund points',
                    style:
                        TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
