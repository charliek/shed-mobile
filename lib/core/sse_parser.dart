import 'dart:convert';

/// One parsed SSE record. Mirrors packages/shared/src/sse.ts `SSERawEvent`.
class SseRawEvent {
  const SseRawEvent(this.event, this.data);

  final String event;
  final String data;
}

/// Parse an SSE byte stream into `{event, data}` records (shed-server dialect):
///   - `event:` sets the event type for the next dispatch
///   - `data:` lines concat with newlines
///   - a blank line dispatches the accumulated event (only when data is present)
///   - `:` lines are comments / keep-alive pings
///   - a final record with no trailing blank line is still flushed at EOF
///
/// Port of packages/shared/src/sse.ts with **bounded buffers** (PLAN §13 P4):
/// an unterminated line may not exceed [maxLineLength] and an accumulated
/// event's data may not exceed [maxDataLength] (both in UTF-16 code units, a
/// conservative proxy for bytes); exceeding either throws [FormatException]
/// rather than buffering without limit.
Stream<SseRawEvent> parseSseStream(
  Stream<List<int>> bytes, {
  int maxLineLength = 1 << 20,
  int maxDataLength = 8 << 20,
}) async* {
  var buffer = '';
  var event = '';
  var data = '';

  void applyData(String v) {
    data = data.isEmpty ? v : '$data\n$v';
    if (data.length > maxDataLength) {
      throw const FormatException('SSE event data exceeds the maximum size');
    }
  }

  void apply(String line) {
    if (line.startsWith(':')) return;
    if (line.startsWith('event:')) {
      event = line.substring(6).trim();
    } else if (line.startsWith('data:')) {
      applyData(line.substring(5).trim());
    }
  }

  String stripCr(String s) =>
      s.endsWith('\r') ? s.substring(0, s.length - 1) : s;

  // utf8.decoder (chunked) correctly holds partial multi-byte sequences across
  // chunk boundaries, the way TextDecoder's stream mode does in the TS source.
  await for (final chunk in bytes.transform(
    const Utf8Decoder(allowMalformed: true),
  )) {
    buffer += chunk;
    // Walk lines with a cursor so each newline is O(1), not an O(tail) reslice.
    var start = 0;
    var nl = buffer.indexOf('\n');
    while (nl != -1) {
      final line = stripCr(buffer.substring(start, nl));
      if (line.length > maxLineLength) {
        throw const FormatException('SSE line exceeds the maximum size');
      }
      start = nl + 1;
      if (line.isEmpty) {
        if (data.isNotEmpty) yield SseRawEvent(event, data);
        event = '';
        data = '';
      } else {
        apply(line);
      }
      nl = buffer.indexOf('\n', start);
    }
    if (start > 0) buffer = buffer.substring(start);
    if (buffer.length > maxLineLength) {
      throw const FormatException('SSE line exceeds the maximum size');
    }
  }

  // EOF flush: a final line without a trailing newline is still applied.
  if (buffer.isNotEmpty) apply(stripCr(buffer));
  if (data.isNotEmpty) yield SseRawEvent(event, data);
}
