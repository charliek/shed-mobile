import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/ssh/host_key_store.dart';
import 'package:shed_mobile/ssh/hub_tunnel.dart';

/// The machine hub tunnel's LOCAL half — the part that must hold regardless of
/// what SSH does.
///
/// The forwarding itself needs a live SSH server and belongs to the
/// `tests/machine-transport` differential in the shed repo (which drives every
/// transport against one contract through a throwaway sshd). What is testable
/// here — and is what a phone actually breaks — is the socket lifecycle: the
/// port must be stable, loopback-only, and released on close, because the Rust
/// side's whole reconnect model assumes a fixed address that stops answering
/// rather than one that moves.
void main() {
  test('the remote hub port is the contract value, not configurable', () {
    // Mirrors `shed_core::hub_client::HUB_PORT`. If this ever needs to change,
    // it changes on both sides at once or the tunnel forwards to nothing.
    expect(kHubRemotePort, 1029);
  });

  group('HubTunnel', () {
    test('binds a loopback port that stays fixed and is freed on close', () async {
      final tunnel = await _openWithoutSsh();
      final port = tunnel.port;

      expect(port, greaterThan(0));
      expect(tunnel.isClosed, isFalse);
      // The port is a property of the TUNNEL, not of any connection: reading it
      // repeatedly (as the Rust side does on every reconnect) must not move it.
      expect(tunnel.port, port);
      expect(tunnel.port, port);

      // It is really listening, and really on loopback.
      final probe = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(seconds: 5),
      );
      probe.destroy();

      await tunnel.close();
      expect(tunnel.isClosed, isTrue);

      // Closing must FREE the port — a leaked listener would keep answering and
      // the Rust client would read a dead tunnel as healthy.
      await expectLater(
        Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: const Duration(seconds: 2),
        ),
        throwsA(isA<SocketException>()),
      );
    });

    test('close is idempotent', () async {
      final tunnel = await _openWithoutSsh();
      await tunnel.close();
      await tunnel.close();
      expect(tunnel.isClosed, isTrue);
    });

    test('a failed SSH dial closes only that connection, not the tunnel', () async {
      // The tunnel points at a port nothing serves, so every forward attempt
      // fails — the everyday "machine is asleep" case.
      final tunnel = await _openWithoutSsh();
      final port = tunnel.port;

      // Two connections in a row: each is dropped, and the LISTENER survives.
      // This is the property that lets the Rust side back off and retry against
      // a stable address instead of the tunnel tearing itself down on the first
      // failure (which would strand a machine that is merely asleep).
      for (var i = 0; i < 2; i++) {
        final probe = await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: const Duration(seconds: 5),
        );
        // The far side gives up; we only care that the listener is still there.
        await probe.drain<void>().timeout(
          const Duration(seconds: 10),
          onTimeout: () {},
        );
        probe.destroy();
      }

      expect(
        tunnel.isClosed,
        isFalse,
        reason: 'the tunnel must outlive a failed dial',
      );
      expect(tunnel.port, port, reason: 'and must keep the same port');
      await tunnel.close();
    });
  });
}

/// A tunnel whose SSH side can never connect (nothing listens on the chosen
/// port), so the local socket lifecycle is exercised without a live server.
Future<HubTunnel> _openWithoutSsh() async {
  final dead = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final deadPort = dead.port;
  await dead.close();
  return HubTunnel.open(
    machine: 'test',
    host: InternetAddress.loopbackIPv4.address,
    sshPort: deadPort,
    user: 'nobody',
    identities: const [],
    // The TCP connect never succeeds, so the verifier is never consulted;
    // `tofu: false` makes that explicit rather than leaving a permissive store
    // sitting in a test.
    hostKeys: HostKeyStore(tofu: false),
  );
}
