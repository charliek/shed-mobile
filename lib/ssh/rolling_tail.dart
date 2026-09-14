/// **The last N bytes of a stream, held while reading** — the one discipline
/// both diagnostic bands on this connection share.
///
/// Two seams need it and they must not grow two copies: the bootstrap exec
/// (`exec_bytes.dart`, at the step's `stderr_cap`) and the byte pump's
/// diagnostic band (`duplex_pump.dart`, at [kStderrTailBytes]). The rule they
/// share is the one that is easy to get subtly wrong — a far side that writes a
/// megabyte of banner must not cost a megabyte of memory to keep four kilobytes
/// of it, and the window must be kept in BYTES so a cut that lands inside a
/// multi-byte sequence is re-joined by the next chunk rather than decoded into
/// a replacement character that is then permanent.
library;

import 'dart:convert';
import 'dart:typed_data';

/// How much of a channel's diagnostic band the pump keeps to classify against.
///
/// The same 4 KiB as `roost_bootstrap.rs`'s `STDERR_TAIL_CAP`, deliberately:
/// the two clients must not truncate the same failure differently, and a
/// bootstrap step and a live tunnel are looking for the same markers.
const int kStderrTailBytes = 4 * 1024;

/// The last [cap] bytes seen. See the library comment for why it is bytes.
class RollingTail {
  RollingTail(this.cap);

  final int cap;
  Uint8List _bytes = Uint8List(0);

  /// How many bytes are currently held — never more than [cap].
  int get length => _bytes.length;

  void add(Uint8List chunk) {
    if (cap <= 0) return;
    if (chunk.length >= cap) {
      _bytes = Uint8List.fromList(
        Uint8List.sublistView(chunk, chunk.length - cap),
      );
      return;
    }
    final keep = _bytes.length + chunk.length <= cap
        ? _bytes.length
        : cap - chunk.length;
    final next = Uint8List(keep + chunk.length);
    next.setRange(0, keep, _bytes, _bytes.length - keep);
    next.setRange(keep, next.length, chunk);
    _bytes = next;
  }

  /// Lossy on purpose: the cut at the head is at a byte boundary and can land
  /// inside a multi-byte sequence, and a diagnosis with one replacement
  /// character in it beats an exception on the path that reports a failure.
  ///
  /// A split *between chunks* is not lossy, which is the whole point: the
  /// bytes are joined before anything decodes them.
  String decode() => utf8.decode(_bytes, allowMalformed: true);
}
