import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/machines/machine_record.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/servers/server_record.dart';
import 'package:shed_mobile/ssh/host_key_store.dart';

/// **The feed ORIGIN key, and what it dials** (plan 022 S6, shed#328).
///
/// After S6 a shed's agent sessions are roost tabs on a `roost-session` the
/// phone reaches over its own SSH tunnel — the identical machinery a machine's
/// rows come from. The whole of the difference is what the feed dials, and
/// `roostDialFor` is that decision: a wrong user or port is a connection that
/// lands somewhere else entirely, and a TOFU store where a pin belongs is
/// "trust anything" wearing a better name.

const _rec = ServerRecord(
  name: 'h',
  host: '10.0.0.4',
  sshPort: 2222,
  apiUrl: 'https://10.0.0.4:8443',
  tlsCertFingerprint: 'sha256:aa',
  hostKeyPin: 'SHA256:abc',
);

/// The shared TOFU store a machine feed is expected to keep, by identity.
final _machineKeys = HostKeyStore(tofu: true);

({MachineRecord record, HostKeyStore hostKeys}) _dial(
  String origin, {
  List<ServerRecord> servers = const [_rec],
  List<MachineRecord> machines = const [],
}) => roostDialFor(
  origin: origin,
  servers: servers,
  machines: machines,
  machineHostKeys: _machineKeys,
);

void main() {
  group('shedFeedKey / parseShedFeedKey', () {
    test('round-trips a shed', () {
      final key = shedFeedKey('my-server', 'proj');
      expect(key, 'shed:my-server/proj');
      expect(parseShedFeedKey(key), (
        serverName: 'my-server',
        shedName: 'proj',
      ));
    });

    test('a bare machine name is NOT a shed', () {
      // The status-quo meaning of the key, and the reason every existing
      // machine call site needed no edit.
      expect(parseShedFeedKey('mini3'), isNull);
    });

    test('splits on the LAST slash — a server alias is free-form', () {
      // A shed name cannot contain a slash (shed validates it as
      // `^[a-z][a-z0-9-]*[a-z0-9]$`) but a server alias is unconstrained, so
      // `a/b/c` can only be the server `a/b` and the shed `c`. The left-split
      // answer `b/c` is not a name any shed could have, and reading the server
      // as `a` dials the wrong server whenever one is really named `a`.
      expect(parseShedFeedKey('shed:a/b/c'), (
        serverName: 'a/b',
        shedName: 'c',
      ));
    });

    test('a server alias with a slash round-trips', () {
      // The property that actually matters: encode then decode is identity for
      // any legal pair, including the free-form half.
      const server = 'work/prod';
      const shed = 'web';
      expect(parseShedFeedKey(shedFeedKey(server, shed)), (
        serverName: server,
        shedName: shed,
      ));
    });

    test('a machine may not claim the shed namespace', () {
      // The collision this closes: a machine named `shed:h/proj` has that
      // string as its feed origin, so it resolves to the SHED `proj` on
      // server `h` — same provider key, same feed, same End button — while
      // its own host and user are never dialled.
      expect(machineNameError('shed:h/proj'), isNotNull);
      expect(machineNameError('${shedOriginPrefix}anything'), isNotNull);
    });

    test('an ordinary machine name is accepted', () {
      // The other half: the guard must not reject the names people use.
      for (final ok in ['mini3', 'work-laptop', 'shedless', 'my.host:2222']) {
        expect(machineNameError(ok), isNull, reason: ok);
      }
    });

    test('a malformed shed key is not a shed', () {
      expect(parseShedFeedKey('shed:'), isNull);
      expect(parseShedFeedKey('shed:/proj'), isNull, reason: 'no server');
      expect(parseShedFeedKey('shed:h/'), isNull, reason: 'no shed');
    });
  });

  group('roostDialFor', () {
    test('a shed dials <shed>@<server host>:<server ssh port>', () {
      final rec = _dial(shedFeedKey('h', 'web')).record;
      // The shed's login user IS the shed name — that is how the server's sshd
      // routes the connection into the right VM.
      expect(rec.user, 'web');
      expect(rec.host, '10.0.0.4');
      expect(rec.sshPort, 2222);
      // Labelled by the ORIGIN, not the shed name: two servers may both have a
      // shed called `web`, and this string names the tunnel and every error.
      expect(rec.name, 'shed:h/web');
    });

    test('a shed pins the saved fingerprint under <host>:<port>', () {
      final keys = _dial(shedFeedKey('h', 'web')).hostKeys;
      expect(keys.tofu, isFalse);
      expect(keys.pinFor('10.0.0.4:2222'), 'SHA256:abc');
    });

    test(
      "an unknown server's shed does not fall through to the machine arm",
      () {
        // Negative control for the two above: with no matching server the
        // resolver must NOT take the machine branch (which would dial
        // `host == origin` with the shared TOFU store).
        final dial = _dial(shedFeedKey('h', 'web'), servers: const []);
        expect(dial.record.user, 'web');
        expect(dial.record.host, 'h');
        expect(dial.record.host, isNot('shed:h/web'));
        // And it FAILS CLOSED: a pinned store with no pin rejects, where a TOFU
        // store would silently accept whatever answered.
        expect(dial.hostKeys.tofu, isFalse);
        expect(dial.hostKeys.pinFor('h:22'), isNull);
        expect(identical(dial.hostKeys, _machineKeys), isFalse);
      },
    );

    test('a configured machine still resolves to its own record and the '
        'SHARED TOFU store', () {
      final dial = _dial(
        'mini3',
        machines: const [
          MachineRecord(name: 'mini3', host: '192.168.86.42', user: 'charliek'),
        ],
      );
      expect(dial.record.name, 'mini3');
      expect(dial.record.host, '192.168.86.42');
      expect(dial.record.user, 'charliek');
      expect(identical(dial.hostKeys, _machineKeys), isTrue);
    });

    test('an unknown machine name still falls back to name-as-host', () {
      final rec = _dial('mini9').record;
      expect(rec.host, 'mini9');
      expect(rec.user, isNull);
    });
  });
}
