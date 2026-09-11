import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/ssh/duplex_pump.dart';
import 'package:shed_mobile/ssh/lane_forward.dart';

import 'support/fake_channel.dart';
import 'support/loopback_client.dart';

/// **A lane's port forward, and the refcounted registry over it** (plan 018
/// §3.10).
///
/// Two things are proved here and nowhere else on this side of the wire:
///
/// 1. **The stable local port.** Rust's HTTP/SSE client reconnects against a
///    fixed loopback address that stops answering rather than one that moves,
///    and the forward re-dials the SSH channel underneath it. A forward that
///    rebinds on reconnect breaks a reconnect model written once, in Rust, for
///    every client (the plan-012 invariant).
/// 2. **One forward per `(machine, remote port)`.** Two lanes on one agent
///    server must share a forward and release it exactly once; two forwards
///    means two listeners and a Rust client talking to whichever one it was
///    handed, and a leaked lease is a port left listening on a phone in
///    someone's pocket.
///
/// Every claim below is asserted on DELIVERED BYTES, never on liveness — plan
/// 012 shipped a forwarded-hub check that only proved the tunnel was up and
/// passed against a completely dead feed
/// (`roost_tunnel_test.dart:18-30`). The pump's own semantics are
/// `duplex_pump_test.dart`; the far side's argv is shed's
/// `tests/machine-transport` differential.
void main() {
  group('LaneForward', () {
    test(
      'carries bytes both ways, to the remote port it was asked for',
      () async {
        final dialer = _Dialer(echo: upperEcho);
        final forward = await LaneForward.openWithDial(
          dial: dialer.dial,
          remotePort: 4096,
        );
        addTearDown(forward.close);

        final conn = await LoopbackClient.connect(forward.port);
        addTearDown(conn.destroy);

        expect(await conn.roundTrip('GET /app'), 'GET /APP');
        expect(dialer.channels[0].receivedText, 'GET /app');
        // The forward's whole job: this local port reaches THAT far-side port.
        expect(dialer.remotePorts, [4096]);
        expect(forward.remotePort, 4096);
        expect(forward.port, isNot(4096));
      },
    );

    test('keeps its local port across a failed channel, and re-dials', () async {
      // THE STABLE-PORT PROOF. Rust holds one address for the lane's whole
      // life; when the phone changes networks the channel underneath dies and
      // the next accepted connection dials a new one. So: send bytes, kill the
      // channel, reconnect to the SAME port, and prove bytes flow through a
      // NEWLY DIALLED channel.
      final dialer = _Dialer(echo: upperEcho);
      final forward = await LaneForward.openWithDial(
        dial: dialer.dial,
        remotePort: 4096,
      );
      addTearDown(forward.close);
      final port = forward.port;

      final first = await LoopbackClient.connect(port);
      addTearDown(first.destroy);
      expect(await first.roundTrip('one'), 'ONE');

      // The link drops: the far side's channel ends under us.
      dialer.channels[0].endStream();
      await first.closedByPeer.timeout(const Duration(seconds: 5));
      expect(
        forward.isClosed,
        isFalse,
        reason: 'a dead channel must not take the forward down with it',
      );
      expect(forward.port, port, reason: 'and the port must not move');

      // The same address, a new channel, and real bytes through it.
      final second = await LoopbackClient.connect(port);
      addTearDown(second.destroy);
      expect(await second.roundTrip('two'), 'TWO');

      expect(dialer.remotePorts, [4096, 4096], reason: 'it re-dialled');
      expect(dialer.channels.length, 2);
      // Not the first channel answering again: each carried its own bytes.
      expect(dialer.channels[0].receivedText, 'one');
      expect(dialer.channels[1].receivedText, 'two');
    });

    test('close frees the port but never the connection it rides', () async {
      // The forward is one of several things on the machine's ONE SSH client
      // (the roost tunnel and a PTY are others), so closing it must close
      // channels and nothing else. Structural here — `LaneForward` is handed a
      // dial, never a client — and this is the guard on that staying true.
      final dialer = _Dialer(echo: upperEcho);
      final forward = await LaneForward.openWithDial(
        dial: dialer.dial,
        remotePort: 4096,
      );
      final conn = await LoopbackClient.connect(forward.port);
      addTearDown(conn.destroy);
      expect(await conn.roundTrip('live'), 'LIVE');
      final port = forward.port;

      await forward.close();

      expect(forward.isClosed, isTrue);
      expect(await portAccepts(port), isFalse, reason: 'the port is freed');
      expect(dialer.channels[0].closeCalled, isTrue, reason: 'and the channel');
      expect(
        dialer.connectionClosed,
        isFalse,
        reason: 'but NOT the SSH connection the dial rides',
      );
      await conn.closedByPeer.timeout(const Duration(seconds: 5));
    });

    test('close is idempotent', () async {
      final dialer = _Dialer();
      final forward = await LaneForward.openWithDial(
        dial: dialer.dial,
        remotePort: 4096,
      );
      await forward.close();
      await forward.close();
      expect(forward.isClosed, isTrue);
    });

    test('a failed dial closes one connection, not the forward', () async {
      final dialer = _Dialer(echo: upperEcho, failDials: 1);
      final forward = await LaneForward.openWithDial(
        dial: dialer.dial,
        remotePort: 4096,
      );
      addTearDown(forward.close);
      final port = forward.port;

      final probe = await LoopbackClient.connect(port);
      await probe.closedByPeer.timeout(const Duration(seconds: 10));
      probe.destroy();
      expect(forward.isClosed, isFalse);
      expect(forward.port, port);

      // The retry lands, against the same address.
      final conn = await LoopbackClient.connect(port);
      addTearDown(conn.destroy);
      expect(await conn.roundTrip('retry'), 'RETRY');
    });
  });

  group('ForwardRegistry', () {
    test('two simultaneous acquires open ONE forward', () async {
      // The single-flight rule. The slot is inserted before the first await, so
      // an acquire landing in the same turn as another adopts its open instead
      // of starting a second one.
      final fake = _Registry(echo: upperEcho);
      final leases = await Future.wait([
        fake.registry.acquire(4096),
        fake.registry.acquire(4096),
      ]);
      addTearDown(() => Future.wait(leases.map((l) => l.release())));

      expect(fake.opens, 1, reason: 'one open for two acquires');
      expect(fake.registry.liveForwards, 1);
      expect(leases[0].port, leases[1].port, reason: 'one port, shared');
      expect(leases.every((l) => l.isValid), isTrue);

      // And it is a real, byte-carrying forward, not just a bookkeeping entry.
      final conn = await LoopbackClient.connect(leases[0].port);
      addTearDown(conn.destroy);
      expect(await conn.roundTrip('shared'), 'SHARED');
      expect(leases[0].remotePort, 4096);
    });

    test('the LAST release closes the forward', () async {
      final fake = _Registry(echo: upperEcho);
      final first = await fake.registry.acquire(4096);
      final second = await fake.registry.acquire(4096);
      final port = first.port;
      expect(fake.opens, 1);

      await first.release();
      expect(
        await portAccepts(port),
        isTrue,
        reason: 'one holder left, so the forward must still be serving',
      );
      final conn = await LoopbackClient.connect(port);
      addTearDown(conn.destroy);
      expect(await conn.roundTrip('alive'), 'ALIVE');

      await second.release();
      expect(await portAccepts(port), isFalse);
      expect(fake.registry.liveForwards, 0);
      expect(second.isValid, isFalse);
    });

    test('release is idempotent, and does not decrement twice', () async {
      // A double release that decremented twice would close a forward another
      // lane is still using — the failure mode is another screen's lane going
      // dark, which is exactly the kind of thing nobody traces back to here.
      final fake = _Registry(echo: upperEcho);
      final first = await fake.registry.acquire(4096);
      final second = await fake.registry.acquire(4096);
      addTearDown(second.release);

      await first.release();
      await first.release();

      expect(fake.registry.liveForwards, 1);
      final conn = await LoopbackClient.connect(second.port);
      addTearDown(conn.destroy);
      expect(await conn.roundTrip('held'), 'HELD');
    });

    test('a failed open reaches every waiter and leaves no slot', () async {
      // A poisoned slot would make every later acquire on this port await a
      // future that has already failed — the lane would never recover from one
      // asleep machine.
      final fake = _Registry(echo: upperEcho, failOpens: 1);
      final results = await Future.wait([
        fake.registry
            .acquire(4096)
            .then<Object?>((l) => l, onError: (Object e) => e),
        fake.registry
            .acquire(4096)
            .then<Object?>((l) => l, onError: (Object e) => e),
      ]);

      expect(results[0], isA<SocketException>());
      expect(
        results[1],
        isA<SocketException>(),
        reason: 'every waiter sees it',
      );
      expect(fake.opens, 1, reason: 'still single-flight while it was failing');
      expect(fake.registry.liveForwards, 0, reason: 'the slot is gone');

      // The retry gets a fresh open, and a working forward.
      final lease = await fake.registry.acquire(4096);
      addTearDown(lease.release);
      expect(fake.opens, 2);
      final conn = await LoopbackClient.connect(lease.port);
      addTearDown(conn.destroy);
      expect(await conn.roundTrip('after'), 'AFTER');
    });

    test('a teardown racing an open leaves no listener', () async {
      // The window that leaks: `closeAll` runs while the SSH dial is still in
      // flight, so there is nothing to close yet. The open must close ITSELF
      // when it lands, or a phone keeps a port open for a machine it is no
      // longer watching.
      final fake = _Registry(echo: upperEcho, gateOpens: true);
      final acquiring = fake.registry.acquire(4096);
      await waitFor(() => fake.opens == 1, 'the open to start');

      await fake.registry.closeAll();
      expect(fake.registry.liveForwards, 0);

      // Now the dial lands, into a registry that no longer wants it.
      fake.release();
      await expectLater(acquiring, throwsA(isA<StateError>()));

      // The dial DID land and DID bind a port — and that port is gone again.
      await waitFor(() => fake.localPorts.isNotEmpty, 'the late open to bind');
      await waitForPortFree(fake.localPorts.single);
    });

    test('closeAll closes a live forward and invalidates its lease', () async {
      final fake = _Registry(echo: upperEcho);
      final lease = await fake.registry.acquire(4096);
      expect(lease.isValid, isTrue);

      await fake.registry.closeAll();

      expect(
        lease.isValid,
        isFalse,
        reason: 'a lane must re-acquire, not write',
      );
      expect(await portAccepts(lease.port), isFalse);
      expect(fake.registry.liveForwards, 0);
      // And giving back an invalidated lease is harmless.
      await lease.release();
      await lease.release();
    });

    test('two remote ports get two forwards, each to its own', () async {
      final fake = _Registry(echo: upperEcho);
      final gx = await fake.registry.acquire(4096);
      addTearDown(gx.release);
      final opencode = await fake.registry.acquire(2421);
      addTearDown(opencode.release);

      expect(fake.opens, 2);
      expect(fake.registry.liveForwards, 2);
      expect(gx.port, isNot(opencode.port));
      expect(fake.remotePortsOpened, [4096, 2421]);

      // Bytes go to the right far side, not to whichever was opened first.
      final gxConn = await LoopbackClient.connect(gx.port);
      addTearDown(gxConn.destroy);
      expect(await gxConn.roundTrip('gx'), 'GX');
      expect(fake.dialerFor(4096).channels[0].receivedText, 'gx');
      expect(fake.dialerFor(2421).channels, isEmpty);
    });

    test('an acquire after the last release opens a new forward', () async {
      final fake = _Registry(echo: upperEcho);
      final first = await fake.registry.acquire(4096);
      await first.release();

      final second = await fake.registry.acquire(4096);
      addTearDown(second.release);

      expect(fake.opens, 2, reason: 'the closed slot was not reused');
      // Deliberately NOT asserting the new port differs from the old one: the
      // OS is free to hand back a just-released ephemeral port, so that would
      // be a flake rather than a property. `opens == 2` is what says a second
      // forward was really opened, and the round-trip below is what says it
      // works.
      final conn = await LoopbackClient.connect(second.port);
      addTearDown(conn.destroy);
      expect(await conn.roundTrip('again'), 'AGAIN');
    });
  });
}

/// A [LaneDial] under the test's control, standing in for one machine's SSH
/// connection: it records every remote port it was asked for and hands out
/// [FakeChannel]s.
class _Dialer {
  _Dialer({this.echo, this.failDials = 0});

  final Uint8List Function(Uint8List)? echo;

  /// How many of the first dials throw, the way an asleep machine's would.
  final int failDials;

  final List<int> remotePorts = <int>[];
  final List<FakeChannel> channels = <FakeChannel>[];

  /// Whether anything closed the SSH connection these channels ride. Nothing
  /// in [LaneForward] may: the machine's feed owns it.
  bool connectionClosed = false;

  Future<DuplexChannel> dial(int remotePort) async {
    remotePorts.add(remotePort);
    if (remotePorts.length <= failDials) {
      throw const SocketException('no route to host');
    }
    final channel = FakeChannel(echo: echo);
    channels.add(channel);
    return channel;
  }
}

/// A [ForwardRegistry] over real [LaneForward]s (real loopback ports, so "no
/// listener" means something) whose SSH half is a [_Dialer].
class _Registry {
  _Registry({this.echo, this.failOpens = 0, this.gateOpens = false});

  final Uint8List Function(Uint8List)? echo;

  /// How many of the first opens throw — the SSH dial's own failure.
  final int failOpens;

  /// Hold every open until [release], so a teardown can be raced against one.
  final bool gateOpens;

  final Completer<void> _gate = Completer<void>();

  int opens = 0;
  final List<int> remotePortsOpened = <int>[];
  final Map<int, _Dialer> _dialers = <int, _Dialer>{};

  /// Every local port an open actually bound, recorded BEFORE the registry can
  /// close it — a closed `ServerSocket` will not tell you its port.
  final List<int> localPorts = <int>[];

  late final ForwardRegistry registry = ForwardRegistry(
    openForward: (remotePort) {
      opens++;
      remotePortsOpened.add(remotePort);
      if (opens <= failOpens) {
        return Future<LaneForward>.error(
          const SocketException('no route to host'),
        );
      }
      final dialer = _dialers.putIfAbsent(
        remotePort,
        () => _Dialer(echo: echo),
      );
      return _open(dialer, remotePort);
    },
  );

  Future<LaneForward> _open(_Dialer dialer, int remotePort) async {
    if (gateOpens) await _gate.future;
    final forward = await LaneForward.openWithDial(
      dial: dialer.dial,
      remotePort: remotePort,
    );
    localPorts.add(forward.port);
    return forward;
  }

  /// Let the gated opens complete.
  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }

  _Dialer dialerFor(int remotePort) => _dialers[remotePort]!;
}
