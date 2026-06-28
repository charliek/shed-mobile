import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/shed/shed_dtos.dart';

void main() {
  group('Shed.fromJson (extended fields)', () {
    test('surfaces image/repo/cpus/memory/started_at', () {
      final s = Shed.fromJson({
        'name': 'web',
        'status': 'running',
        'backend': 'vz',
        'image': 'shed-vz-full:v0.7.5',
        'repo': 'github.com:charliek/slauth',
        'cpus': 2,
        'memory_mb': 4096,
        'started_at': '2026-06-28T00:00:00Z',
      });
      expect(s.image, 'shed-vz-full:v0.7.5');
      expect(s.repo, 'github.com:charliek/slauth');
      expect(s.cpus, 2);
      expect(s.memoryMb, 4096);
      expect(s.startedAt, isNotNull);
      expect(s.raw['backend'], 'vz'); // raw still preserved
    });

    test('zero/absent numeric fields and the Go zero time → null', () {
      final s = Shed.fromJson({
        'name': 'x',
        'status': 'stopped',
        'cpus': 0,
        'started_at': '0001-01-01T00:00:00Z',
      });
      expect(s.cpus, isNull);
      expect(s.memoryMb, isNull);
      expect(s.startedAt, isNull);
      expect(s.image, isNull);
    });

    test('wrong-typed string fields fall back instead of throwing', () {
      final s = Shed.fromJson({
        'name': 42,
        'status': false,
        'backend': ['vz'],
        'image': 9,
        'repo': true,
      });
      expect(s.name, '?');
      expect(s.status, 'unknown');
      expect(s.backend, isNull);
      expect(s.image, isNull);
      expect(s.repo, isNull);
    });
  });

  group('uptimeLabel', () {
    final now = DateTime.parse('2026-06-28T12:00:00Z');
    test('formats days/hours/minutes; null when unknown', () {
      expect(uptimeLabel(null, now: now), isNull);
      expect(
        uptimeLabel(DateTime.parse('2026-06-26T12:00:00Z'), now: now),
        'up 2d',
      );
      expect(
        uptimeLabel(DateTime.parse('2026-06-28T09:00:00Z'), now: now),
        'up 3h',
      );
      expect(
        uptimeLabel(DateTime.parse('2026-06-28T11:30:00Z'), now: now),
        'up 30m',
      );
      expect(
        uptimeLabel(DateTime.parse('2026-06-28T11:59:30Z'), now: now),
        'up 0m',
      );
    });
    test('a future start time → null (clock skew safe)', () {
      expect(
        uptimeLabel(DateTime.parse('2026-06-28T13:00:00Z'), now: now),
        isNull,
      );
    });
  });

  group('shedMetaLine', () {
    final now = DateTime.parse('2026-06-28T12:00:00Z');
    test('joins present parts; "4 GB" memory; drops absent', () {
      final s = Shed.fromJson({
        'name': 'web',
        'status': 'running',
        'repo': 'github.com:charliek/slauth',
        'cpus': 2,
        'memory_mb': 4096,
        'started_at': '2026-06-28T11:00:00Z',
      });
      expect(
        shedMetaLine(s, now: now),
        'github.com:charliek/slauth · 2 vCPU · 4 GB · up 1h',
      );
    });
    test('a bare shed (no extras) yields an empty line', () {
      expect(
        shedMetaLine(Shed.fromJson({'name': 'x', 'status': 'stopped'})),
        '',
      );
    });
    test('non-round memory falls back to MB', () {
      final s = Shed.fromJson({
        'name': 'x',
        'status': 'running',
        'memory_mb': 1500,
      });
      expect(shedMetaLine(s, now: now), '1500 MB');
    });
  });

  group('formatBytes', () {
    test('zero renders as the design empty label', () {
      expect(formatBytes(0), 'Zero KB');
      expect(formatBytes(-5), 'Zero KB');
    });
    test('binary units, trailing zeros trimmed', () {
      expect(formatBytes(702), '702 B');
      expect(formatBytes(1024), '1 KB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(1610612736), '1.5 GB');
      expect(formatBytes(1323184128), '1.23 GB');
      expect(formatBytes(14506430464), '13.51 GB');
    });
  });

  group('SystemDiskUsage / DiskTotals', () {
    test('parses a full df payload', () {
      final df = SystemDiskUsage.fromJson({
        'server_name': 'mac-mini',
        'backend': 'vz',
        'totals': {
          'images': {'logical_bytes': 1, 'physical_bytes': 1323184128},
          'sheds': {'physical_bytes': 6615306240},
          'all': {'physical_bytes': 14506430464},
        },
      });
      expect(df.serverName, 'mac-mini');
      expect(df.totals.images.physicalBytes, 1323184128);
      expect(df.totals.all.physicalBytes, 14506430464);
      expect(df.totals.orphans.physicalBytes, 0); // absent → zero
    });
    test('missing totals → all zeros (no crash)', () {
      final df = SystemDiskUsage.fromJson({'server_name': 'x'});
      expect(df.totals.all.physicalBytes, 0);
      expect(df.totals.sheds.logicalBytes, 0);
    });
    test('wrong-typed string fields fall back instead of throwing', () {
      final df = SystemDiskUsage.fromJson({
        'server_name': 42,
        'backend': false,
      });
      expect(df.serverName, '?');
      expect(df.backend, isNull);
    });
  });

  group('HostSession.fromJson', () {
    test('an rc row exposes the rc block', () {
      final s = HostSession.fromJson({
        'name': 'rc-baxjjh',
        'shed_name': 'scroll-test',
        'server_name': 'mac-mini',
        'attached': false,
        'rc': {
          'kind': 'claude-rc',
          'state': 'starting',
          'managed': true,
          'display_name': 'test',
        },
      });
      expect(s.isRc, isTrue);
      expect(s.name, 'rc-baxjjh');
      expect(s.shedName, 'scroll-test');
      expect(s.rc!.kind, 'claude-rc');
      expect(s.rc!.state, 'starting');
      expect(s.rc!.displayName, 'test');
    });

    test('the Go zero created_at parses to null (no fake "age")', () {
      final s = HostSession.fromJson({
        'name': 'rc-a',
        'shed_name': 's',
        'created_at': '0001-01-01T00:00:00Z',
        'rc': {'kind': 'shell', 'state': 'ready'},
      });
      expect(s.createdAt, isNull);
    });

    test('a real created_at parses', () {
      final s = HostSession.fromJson({
        'name': 'rc-a',
        'shed_name': 's',
        'created_at': '2026-06-28T10:00:00Z',
        'rc': {'kind': 'shell', 'state': 'ready'},
      });
      expect(s.createdAt, DateTime.parse('2026-06-28T10:00:00Z'));
    });

    test('a plain tmux session (no rc block) is not an rc row', () {
      final s = HostSession.fromJson({'name': 'plain', 'shed_name': 's'});
      expect(s.isRc, isFalse);
      expect(s.rc, isNull);
    });

    test('wrong-typed string fields fall back instead of throwing', () {
      final s = HostSession.fromJson({
        'name': 42,
        'shed_name': false,
        'server_name': ['host'],
        'rc': {'kind': 9, 'state': true, 'display_name': 7},
      });
      expect(s.name, '?');
      expect(s.shedName, '?');
      expect(s.serverName, isNull);
      expect(s.rc!.kind, 'shell');
      expect(s.rc!.state, 'idle');
      expect(s.rc!.displayName, isNull);
    });
  });
}
