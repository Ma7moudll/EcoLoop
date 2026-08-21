import 'dart:async';
import 'dart:convert';

import 'package:shared/shared.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/api_client.dart';
import 'data_repository.dart';

/// Realtime deposit status over the backend WebSocket, with a transparent
/// HTTP-polling fallback when the socket is unavailable.
///
/// The socket is TRANSPORT ONLY: it carries whatever the backend already
/// persisted, so it can never award points. The terminal `Deposit` is always
/// the authoritative server snapshot (confirmed/rejected/cancelled/expired) —
/// identical to what HTTP polling would eventually return. `awaitDeposit`
/// returns once a terminal state is reached, exactly like the polling path.
class DepositStatusChannel {
  final ApiClient _api;
  final DepositRepository _repo;

  /// Injectable socket factory for tests; the default connects for real. A
  /// failed handshake surfaces as an error on the channel's stream, which
  /// the polling fallback in [awaitDeposit] absorbs.
  final WebSocketChannel Function(Uri uri)? connect;

  DepositStatusChannel(this._api, this._repo, {this.connect});

  /// Bandwidth-friendly live status string for the waiting UI.
  static String phaseLabel(DepositStatus status) => switch (status) {
        DepositStatus.capture => 'Waiting for the station camera…',
        DepositStatus.analyzing => 'Analyzing the item…',
        DepositStatus.pending => 'Waiting for the station…',
        DepositStatus.routing => 'Routing the item…',
        DepositStatus.moving => 'Moving to the compartment…',
        DepositStatus.ready => 'Item in place — starting detection…',
        DepositStatus.detecting => 'Detecting the item…',
        DepositStatus.measuring => 'Measuring weight…',
        _ => 'Waiting for the station…',
      };

  /// Waits for a terminal deposit, preferring the realtime socket. Every live
  /// phase is forwarded to [onLive] so the UI can render progress; on any
  /// socket failure it silently drops back to the repository's HTTP polling.
  Future<({Deposit deposit, int pointsAwarded, int challengeBonus})>
      awaitDeposit(
    Deposit session, {
    void Function(Deposit live)? onLive,
    Duration pollInterval = const Duration(seconds: 2),
    Duration timeout = const Duration(minutes: 3),
  }) async {
    final token = _api.token;
    final socketUri = token == null ? null : _wsUri(session.operationId, token);
    if (socketUri != null) {
      try {
        return await _viaSocket(socketUri, session, onLive: onLive, timeout: timeout);
      } catch (_) {
        // Socket path failed for any reason — fall back to polling below.
      }
    }
    return _repo.awaitDeposit(
      session,
      pollInterval: pollInterval,
      timeout: timeout,
    );
  }

  Future<({Deposit deposit, int pointsAwarded, int challengeBonus})>
      _viaSocket(
    Uri uri,
    Deposit session, {
    void Function(Deposit live)? onLive,
    required Duration timeout,
  }) async {
    final channel =
        connect?.call(uri) ?? IOWebSocketChannel.connect(uri);
    final deadline = DateTime.now().add(timeout);

    try {
      await for (final frame in channel.stream.timeout(timeout)) {
        final message = jsonDecode(frame as String) as Map<String, dynamic>;
        final type = message['type'] as String?;
        if (type == 'keepalive') continue;
        if (type != 'state' && type != 'terminal') continue;

        final deposit = Deposit.fromJson(message['deposit'] as Map<String, dynamic>);
        if (deposit.status.isTerminal) {
          return (
            deposit: deposit,
            pointsAwarded: deposit.pointsAwarded,
            challengeBonus: 0,
          );
        }
        onLive?.call(deposit);
        if (!DateTime.now().isBefore(deadline)) break; // safety net
      }
    } finally {
      await channel.sink.close();
    }
    throw ApiException('The station did not respond in time. Please retry.');
  }

  Uri _wsUri(String operationId, String token) {
    final base = Uri.parse(_api.baseUrl);
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    return Uri(
      scheme: scheme,
      host: base.host,
      port: base.port,
      path: '/ws/deposits/$operationId',
      queryParameters: {'token': token},
    );
  }
}