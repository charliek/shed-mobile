import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;
import 'dart:math';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/core/app_error.dart';
import 'package:shed_mobile/rc/rc_models.dart';
import 'package:shed_mobile/rc/rc_service.dart';
import 'package:shed_mobile/ssh/ssh_runner.dart';

/// Records the last invocation and returns a canned result (or throws).
class _FakeRunner {
  List<String>? argv;
  String? stdin;
  Duration? timeout;

  SshResult result = const SshResult(0, '{}', '');
  Object? error;

  SshRun get run =>
      (
        List<String> a, {
        String? stdin,
        Duration timeout = const Duration(seconds: 15),
      }) async {
        argv = a;
        this.stdin = stdin;
        this.timeout = timeout;
        if (error != null) throw error!;
        return result;
      };
}

RcService _service(_FakeRunner fake, {String Function()? slugGen}) => RcService(
  runner: fake.run,
  shedName: 'myshed',
  serverLabel: 'mac-mini',
  slugGen: slugGen,
);

String _dto({
  String slug = 'abc234',
  String kind = 'claude-rc',
  String state = 'ready',
}) => jsonEncode({
  'slug': slug,
  'tmux_session': 'rc-$slug',
  'kind': kind,
  'state': state,
  'managed': true,
  'display_name': 'myshed/$slug',
  'url': 'https://claude.ai/code/session_01abc',
});

void main() {
  group('genSlug', () {
    test('is 6 chars from the unambiguous alphabet', () {
      const alphabet = 'abcdefghjkmnpqrstuvwxyz23456789';
      for (var seed = 0; seed < 50; seed += 1) {
        final s = genSlug(Random(seed));
        expect(s, hasLength(6));
        for (final ch in s.split('')) {
          expect(alphabet, contains(ch));
        }
      }
    });

    test('excludes visually-confusable l/i/o/0/1', () {
      final joined = List.generate(200, (i) => genSlug(Random(i))).join();
      for (final bad in ['l', 'i', 'o', '0', '1']) {
        expect(
          joined.contains(bad),
          isFalse,
          reason: 'slug must not contain "$bad"',
        );
      }
    });
  });

  group('rcCreatedBy', () {
    test('is shed-mobile/<version>', () {
      expect(rcToolName, 'shed-mobile');
      expect(rcCreatedBy, startsWith('shed-mobile/'));
      expect(rcCreatedBy, isNot(contains(' ')));
    });
  });

  group('create', () {
    test('builds the create argv with --wait and provenance', () async {
      final fake = _FakeRunner()..result = SshResult(0, _dto(), '');
      final svc = _service(fake, slugGen: () => 'fixed1');
      final s = await svc.create(kind: RcKind.claudeRc);

      expect(fake.argv, [
        'shed-ext-rc',
        'create',
        '--kind',
        'claude-rc',
        '--name',
        'myshed/fixed1', // default display name = <shed>/<slug>
        '--slug',
        'fixed1',
        '--created-by',
        rcCreatedBy,
        '--target',
        'shed:myshed@mac-mini',
        '--wait',
      ]);
      expect(fake.stdin, isNull);
      expect(fake.timeout, const Duration(seconds: 30));
      expect(s.slug, 'abc234');
      expect(s.isReady, isTrue);
    });

    test('claude-rc prompt is sent via stdin with --prompt-stdin', () async {
      final fake = _FakeRunner()..result = SshResult(0, _dto(), '');
      final svc = _service(fake, slugGen: () => 'fixed1');
      await svc.create(kind: RcKind.claudeRc, prompt: '  fix the build  ');

      expect(fake.argv, contains('--prompt-stdin'));
      expect(fake.stdin, 'fix the build'); // trimmed
    });

    test('claude-broker drops the prompt (no pane to type into)', () async {
      final fake = _FakeRunner()
        ..result = SshResult(0, _dto(kind: 'claude-broker'), '');
      final svc = _service(fake, slugGen: () => 'fixed1');
      await svc.create(kind: RcKind.claudeBroker, prompt: 'ignored');

      expect(fake.argv, isNot(contains('--prompt-stdin')));
      expect(fake.stdin, isNull);
    });

    test('passes --workdir and --permission-mode when given', () async {
      final fake = _FakeRunner()..result = SshResult(0, _dto(), '');
      final svc = _service(fake, slugGen: () => 'fixed1');
      await svc.create(
        kind: RcKind.claudeRc,
        workdir: '/work/dir',
        permissionMode: rcPermissionBypass,
      );
      expect(fake.argv, containsAllInOrder(['--workdir', '/work/dir']));
      expect(
        fake.argv,
        containsAllInOrder(['--permission-mode', 'bypassPermissions']),
      );
    });

    test('rejects an invalid permission mode before any SSH call', () async {
      final fake = _FakeRunner();
      final svc = _service(fake);
      await expectLater(
        svc.create(kind: RcKind.claudeRc, permissionMode: 'nope'),
        throwsA(
          isA<AppError>().having((e) => e.code, 'code', 'RC_BAD_REQUEST'),
        ),
      );
      expect(fake.argv, isNull); // never reached the runner
    });

    test('honors a caller-supplied slug and display name', () async {
      final fake = _FakeRunner()..result = SshResult(0, _dto(), '');
      final svc = _service(fake);
      await svc.create(
        kind: RcKind.shell,
        slug: 'mine12',
        displayName: 'My Shell',
      );
      expect(fake.argv, containsAllInOrder(['--name', 'My Shell']));
      expect(fake.argv, containsAllInOrder(['--slug', 'mine12']));
    });
  });

  group('list', () {
    test('parses rc_sessions and applies the <shed>/<slug> fallback', () async {
      final fake = _FakeRunner()
        ..result = SshResult(
          0,
          jsonEncode({
            'rc_sessions': [
              {
                'slug': 'a1',
                'tmux_session': 'rc-a1',
                'kind': 'shell',
                'state': 'ready',
                'managed': true,
              },
              {
                'slug': 'b2',
                'tmux_session': 'rc-b2',
                'kind': 'claude-broker',
                'state': 'starting',
                'managed': false,
              },
            ],
          }),
          '',
        );
      final svc = _service(fake);
      final list = await svc.list();
      expect(fake.argv, ['shed-ext-rc', 'list']);
      expect(list, hasLength(2));
      expect(list[1].displayName, 'myshed/b2'); // fallback
    });

    test('empty rc_sessions → empty list', () async {
      final fake = _FakeRunner()
        ..result = SshResult(0, jsonEncode({'rc_sessions': []}), '');
      expect(await _service(fake).list(), isEmpty);
    });
  });

  group('kill', () {
    test('sends kill --slug', () async {
      final fake = _FakeRunner()..result = const SshResult(0, '', '');
      await _service(fake).kill('abc234');
      expect(fake.argv, ['shed-ext-rc', 'kill', '--slug', 'abc234']);
    });
  });

  group('prompt', () {
    test('sends text via stdin', () async {
      final fake = _FakeRunner()..result = const SshResult(0, '', '');
      await _service(fake).prompt('abc234', '  hi there  ', sessionId: 'sid-1');
      expect(fake.argv, [
        'shed-ext-rc',
        'prompt',
        '--slug',
        'abc234',
        '--session-id',
        'sid-1',
      ]);
      expect(fake.stdin, 'hi there');
    });

    test('rejects empty text before any SSH call', () async {
      final fake = _FakeRunner();
      await expectLater(
        _service(fake).prompt('abc234', '   '),
        throwsA(
          isA<AppError>().having((e) => e.code, 'code', 'RC_BAD_REQUEST'),
        ),
      );
      expect(fake.argv, isNull);
    });
  });

  group('error mapping (exit codes)', () {
    Future<AppError> caught(
      int code, {
      String stderr = '',
      String stdout = '',
    }) async {
      final fake = _FakeRunner()..result = SshResult(code, stdout, stderr);
      try {
        await _service(fake).kill('x');
        fail('expected throw');
      } on AppError catch (e) {
        return e;
      }
    }

    test(
      'domain codes 2/3/4 take priority over the missing-binary check',
      () async {
        expect((await caught(3)).code, 'RC_SLUG_TAKEN');
        expect((await caught(3)).statusCode, 409);
        expect((await caught(4)).code, 'RC_NOT_FOUND');
        expect((await caught(4)).statusCode, 404);
        expect((await caught(2)).code, 'RC_BAD_REQUEST');
        expect((await caught(2)).statusCode, 400);
        // A domain error whose message mentions "command not found" must NOT be
        // misread as a missing binary.
        final e = await caught(
          2,
          stderr: 'invalid: command not found in workdir',
        );
        expect(e.code, 'RC_BAD_REQUEST');
      },
    );

    test('127 / "command not found" → SHED_EXT_RC_MISSING', () async {
      expect((await caught(127)).code, 'SHED_EXT_RC_MISSING');
      expect(
        (await caught(1, stderr: 'bash: shed-ext-rc: command not found')).code,
        'SHED_EXT_RC_MISSING',
      );
    });

    test('other non-zero → RC_FAILED', () async {
      final e = await caught(1, stderr: 'boom');
      expect(e.code, 'RC_FAILED');
      expect(e.statusCode, 500);
      expect(e.message, 'boom');
    });

    test('non-JSON stdout on a 0 exit → RC_FAILED 502', () async {
      final fake = _FakeRunner()..result = const SshResult(0, 'not json', '');
      await expectLater(
        _service(fake).list(),
        throwsA(
          isA<AppError>()
              .having((e) => e.code, 'code', 'RC_FAILED')
              .having((e) => e.statusCode, 'status', 502),
        ),
      );
    });

    test('wrong-shape rc_sessions (not a list) → RC_FAILED 502', () async {
      final fake = _FakeRunner()
        ..result = SshResult(0, jsonEncode({'rc_sessions': 'oops'}), '');
      await expectLater(
        _service(fake).list(),
        throwsA(isA<AppError>().having((e) => e.statusCode, 'status', 502)),
      );
    });

    test('a malformed entry fails the whole list (no silent drop)', () async {
      // A stale binary contract: one good session, one with a wrong-typed field
      // (slug as a number). Must surface 502, not crash with a raw TypeError or
      // silently drop the bad entry.
      final fake = _FakeRunner()
        ..result = SshResult(
          0,
          jsonEncode({
            'rc_sessions': [
              {
                'slug': 'ok',
                'tmux_session': 'rc-ok',
                'kind': 'shell',
                'state': 'ready',
                'managed': true,
              },
              {
                'slug': 123,
                'tmux_session': 'rc-bad',
                'kind': 'shell',
                'state': 'ready',
                'managed': true,
              },
            ],
          }),
          '',
        );
      await expectLater(
        _service(fake).list(),
        throwsA(
          isA<AppError>()
              .having((e) => e.code, 'code', 'RC_FAILED')
              .having((e) => e.statusCode, 'status', 502),
        ),
      );
    });

    test('create with a wrong-typed DTO field → RC_FAILED 502', () async {
      final fake = _FakeRunner()
        ..result = SshResult(
          0,
          jsonEncode({
            'slug': 'x',
            'tmux_session': 'rc-x',
            'kind': 99, // wrong type
            'state': 'ready',
            'managed': true,
          }),
          '',
        );
      await expectLater(
        _service(fake, slugGen: () => 'x').create(kind: RcKind.shell),
        throwsA(
          isA<AppError>()
              .having((e) => e.code, 'code', 'RC_FAILED')
              .having((e) => e.statusCode, 'status', 502),
        ),
      );
    });
  });

  group('error mapping (transport exceptions)', () {
    Future<AppError> caught(Object err) async {
      final fake = _FakeRunner()..error = err;
      try {
        await _service(fake).list();
        fail('expected throw');
      } on AppError catch (e) {
        return e;
      }
    }

    test('auth failure → SSH_AUTH_DENIED 401', () async {
      final e = await caught(SSHAuthFailError('denied'));
      expect(e.code, 'SSH_AUTH_DENIED');
      expect(e.statusCode, 401);
    });

    test('host-key mismatch → SSH_HOST_KEY_MISMATCH', () async {
      final e = await caught(SSHHostkeyError('Hostkey verification failed'));
      expect(e.code, 'SSH_HOST_KEY_MISMATCH');
    });

    test('socket / generic SSH / timeout → SSH_UNREACHABLE 502', () async {
      expect(
        (await caught(const SocketException('refused'))).code,
        'SSH_UNREACHABLE',
      );
      expect((await caught(SSHStateError('boom'))).code, 'SSH_UNREACHABLE');
      expect((await caught(TimeoutException('slow'))).code, 'SSH_UNREACHABLE');
    });

    test(
      'messages never echo transport detail (no token/key leakage path)',
      () async {
        final e = await caught(SSHAuthFailError('secret-detail-xyz'));
        expect(e.message, isNot(contains('secret-detail-xyz')));
      },
    );
  });
}
