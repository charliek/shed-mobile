import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/core/sse_parser.dart';

Stream<List<int>> _strChunks(List<String> parts) async* {
  for (final p in parts) {
    yield utf8.encode(p);
  }
}

Stream<List<int>> _byteChunks(List<int> bytes, List<int> splitAt) async* {
  var i = 0;
  for (final s in [...splitAt, bytes.length]) {
    yield bytes.sublist(i, s);
    i = s;
  }
}

void main() {
  test('parses event + data', () async {
    final out = await parseSseStream(
      _strChunks(['event: progress\ndata: {"a":1}\n\n']),
    ).toList();
    expect(out, hasLength(1));
    expect(out.first.event, 'progress');
    expect(out.first.data, '{"a":1}');
  });

  test('multiline data joins with newline', () async {
    final out = await parseSseStream(
      _strChunks(['data: a\ndata: b\n\n']),
    ).toList();
    expect(out.single.data, 'a\nb');
  });

  test('ignores comment / keep-alive lines', () async {
    final out = await parseSseStream(
      _strChunks([': ping\nevent: x\ndata: y\n\n']),
    ).toList();
    expect(out.single.event, 'x');
    expect(out.single.data, 'y');
  });

  test('a blank line with no data does not dispatch', () async {
    final out = await parseSseStream(_strChunks(['\n\n: c\n\n'])).toList();
    expect(out, isEmpty);
  });

  test('flushes a final record with no trailing newline', () async {
    final out = await parseSseStream(
      _strChunks(['event: complete\ndata: done']),
    ).toList();
    expect(out.single.event, 'complete');
    expect(out.single.data, 'done');
  });

  test('strips trailing CR (CRLF streams)', () async {
    final out = await parseSseStream(
      _strChunks(['event: e\r\ndata: d\r\n\r\n']),
    ).toList();
    expect(out.single.event, 'e');
    expect(out.single.data, 'd');
  });

  test('handles a multi-byte char split across chunks', () async {
    final bytes = utf8.encode('data: café\n\n'); // é is two UTF-8 bytes
    final splitInsideEacute = utf8.encode('data: caf').length + 1;
    final out = await parseSseStream(
      _byteChunks(bytes, [splitInsideEacute]),
    ).toList();
    expect(out.single.data, 'café');
  });

  test('throws when an unterminated line exceeds the cap', () async {
    final huge = 'data: ${'x' * 100}'; // no newline
    expect(
      parseSseStream(_strChunks([huge]), maxLineLength: 16).toList(),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'throws when a complete (newline-terminated) line exceeds the cap',
    () async {
      final line = 'data: ${'x' * 100}\n\n';
      expect(
        parseSseStream(_strChunks([line]), maxLineLength: 16).toList(),
        throwsA(isA<FormatException>()),
      );
    },
  );
}
