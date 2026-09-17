import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecoloop/core/api_client.dart';
import 'package:ecoloop/providers/data_providers.dart';
import 'package:ecoloop/providers/providers.dart';
import 'package:ecoloop/screens/rewards_screen.dart';
import 'package:ecoloop/services/data_repository.dart';
import 'package:shared/shared.dart';

const _coffee = Reward(
  id: 'rw-mix-coffee-20',
  category: 'food',
  name: 'MIX Coffee 20% Off',
  description: '20% off any drink at MIX Coffee.',
  provider: 'MIX Coffee',
  pointsCost: 60,
  valueLabel: '20% OFF',
  currency: 'EGP',
  icon: 'local_cafe',
  stock: null,
  requiresDestination: false,
);

const _vodafone = Reward(
  id: 'rw-vodafone-10',
  category: 'cash',
  name: 'Vodafone Cash 10 EGP',
  description: 'Cash payout by the admin team.',
  provider: 'Vodafone Cash',
  pointsCost: 100,
  valueLabel: '10 EGP',
  currency: 'EGP',
  icon: 'account_balance_wallet_outlined',
  stock: null,
  requiresDestination: true,
);

RewardRedemption _redemption({
  String status = 'available',
  String? code = 'ECO-AB3D9K',
}) {
  return RewardRedemption(
    id: 'rd-1',
    rewardId: _coffee.id,
    rewardName: _coffee.name,
    rewardCategory: _coffee.category,
    provider: _coffee.provider,
    valueLabel: _coffee.valueLabel,
    pointsSpent: 60,
    status: status,
    redemptionCode: code,
    destinationMasked: null,
    adminNote: null,
    createdAt: DateTime(2026, 8, 22),
    fulfilledAt: null,
  );
}

class _FakeRepo extends DataRepository {
  _FakeRepo({this.catalog, this.redemptions = const []})
      : super(ApiClient('http://localhost:9'));

  RewardsCatalog? catalog;
  List<RewardRedemption> redemptions;
  String? error;
  String? redeemError;

  final List<({String rewardId, String key, String? destination})> redeemCalls =
      [];
  final List<String> cancelCalls = [];

  @override
  Future<RewardsCatalog> fetchRewards() async {
    if (error != null) throw ApiException(error!);
    return catalog!;
  }

  @override
  Future<List<RewardRedemption>> fetchMyRedemptions() async => redemptions;

  @override
  Future<RedemptionResult> redeemReward(String rewardId,
      {required String idempotencyKey, String? destination}) async {
    redeemCalls.add((
      rewardId: rewardId,
      key: idempotencyKey,
      destination: destination
    ));
    if (redeemError != null) throw ApiException(redeemError!, statusCode: 409);
    if (error != null) throw ApiException(error!, statusCode: 409);
    return RedemptionResult(
        redemption:
            _redemption(code: rewardId == _vodafone.id ? null : 'ECO-AB3D9K'),
        balance: (catalog?.balance ?? 0) - 60);
  }

  @override
  Future<RedemptionResult> cancelRedemption(String redemptionId) async {
    cancelCalls.add(redemptionId);
    return RedemptionResult(
        redemption: _redemption(status: 'cancelled', code: 'ECO-AB3D9K'),
        balance: 60);
  }
}

Widget _host(_FakeRepo repo) {
  return ProviderScope(
    overrides: [
      dataRepositoryProvider.overrideWithValue(repo),
      currentUserIdProvider.overrideWithValue('u-me'),
    ],
    child: const MaterialApp(home: RewardsScreen()),
  );
}

void main() {
  testWidgets('renders balance and catalog cards with affordability hints',
      (tester) async {
    await tester.pumpWidget(_host(_FakeRepo(
      catalog: RewardsCatalog(
          balance: 50, rewards: [_coffee, _vodafone]),
    )));
    await tester.pumpAndSettle();

    expect(find.text('Your balance'), findsOneWidget);
    expect(find.text('+50 pts'), findsOneWidget);
    expect(find.text('MIX Coffee 20% Off'), findsOneWidget);
    expect(find.text('Vodafone Cash 10 EGP'), findsOneWidget);
    // Coffee affordable (chip), vodafone not (needs 50 more).
    expect(find.text('Need 50 more pts'), findsOneWidget);
  });

  testWidgets('redeeming a code reward issues an ECO code', (tester) async {
    final repo = _FakeRepo(
        catalog: RewardsCatalog(balance: 200, rewards: [_coffee]));
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('MIX Coffee 20% Off'));
    await tester.pumpAndSettle();
    expect(find.text('Redeem for 60 pts'), findsOneWidget);

    await tester.tap(find.text('Redeem for 60 pts'));
    await tester.pumpAndSettle();

    expect(find.text('Here is your code'), findsOneWidget);
    expect(find.text('ECO-AB3D9K'), findsOneWidget);
    expect(find.text('New balance: +140 pts'), findsOneWidget);
    expect(repo.redeemCalls.single.rewardId, _coffee.id);
    expect(repo.redeemCalls.single.key.length, greaterThanOrEqualTo(8));
  });

  testWidgets('cash rewards require a payout destination', (tester) async {
    final repo = _FakeRepo(
        catalog: RewardsCatalog(balance: 200, rewards: [_vodafone]));
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Vodafone Cash 10 EGP'));
    await tester.pumpAndSettle();

    // Submit without a number -> inline validation, nothing sent.
    await tester.tap(find.text('Redeem for 100 pts'));
    await tester.pump();
    expect(find.textContaining('Enter the Vodafone Cash'), findsOneWidget);
    expect(repo.redeemCalls, isEmpty);

    await tester.enterText(
        find.byType(TextField), '01012345678');
    await tester.tap(find.text('Redeem for 100 pts'));
    await tester.pumpAndSettle();

    expect(repo.redeemCalls.single.destination, '01012345678');
    expect(find.textContaining('Request received'), findsOneWidget); // pending note
    expect(find.text('ECO-AB3D9K'), findsNothing);
  });

  testWidgets('unaffordable rewards are not tappable', (tester) async {
    final repo =
        _FakeRepo(catalog: RewardsCatalog(balance: 30, rewards: [_coffee]));
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('MIX Coffee 20% Off'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Redeem for 60 pts'), findsNothing);
  });

  testWidgets('server rejection surfaces the sentence', (tester) async {
    final redeemFails = _FakeRepo(
        catalog: RewardsCatalog(balance: 200, rewards: [_coffee]));
    await tester.pumpWidget(_host(redeemFails));
    await tester.pumpAndSettle();

    // Simulate server-side conflict by stubbing after build.
    redeemFails.redeemError = 'You do not have enough points for this reward yet.';
    await tester.tap(find.text('MIX Coffee 20% Off'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Redeem for 60 pts'));
    await tester.pumpAndSettle();

    expect(find.text('You do not have enough points for this reward yet.'),
        findsOneWidget);
  });

  testWidgets('my redemptions list shows codes and cancels unused ones',
      (tester) async {
    final repo = _FakeRepo(redemptions: [
      _redemption(),
      _redemption(status: 'fulfilled', code: null),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        dataRepositoryProvider.overrideWithValue(repo),
        currentUserIdProvider.overrideWithValue('u-me'),
      ],
      child: const MaterialApp(home: MyRedemptionsScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Available'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('ECO-AB3D9K'), findsOneWidget);

    await tester.tap(find.text('Cancel & refund points'));
    await tester.pumpAndSettle();
    expect(repo.cancelCalls, ['rd-1']);
    expect(find.text('Cancelled — points refunded'), findsOneWidget);
  });

  testWidgets('signed-out users get an empty marketplace, not a crash',
      (tester) async {
    final repo = _FakeRepo(catalog: RewardsCatalog(balance: 0, rewards: []));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        dataRepositoryProvider.overrideWithValue(repo),
        currentUserIdProvider.overrideWithValue(null),
      ],
      child: const MaterialApp(home: RewardsScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('No rewards available yet'), findsOneWidget);
  });
}
