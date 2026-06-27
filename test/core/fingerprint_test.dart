import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/core/fingerprint.dart';

void main() {
  test('certFingerprint is sha256:<lowercase hex> of the DER bytes', () {
    // SHA-256 of the empty input is a well-known constant.
    expect(
      certFingerprint(Uint8List(0)),
      'sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    );
    expect(certFingerprint(Uint8List(0)), matches(kTlsFingerprintRe));
  });

  test('kTlsFingerprintRe accepts lowercase hex only', () {
    expect(kTlsFingerprintRe.hasMatch('sha256:${'a' * 64}'), isTrue);
    expect(kTlsFingerprintRe.hasMatch('sha256:${'A' * 64}'), isFalse);
    expect(kTlsFingerprintRe.hasMatch('SHA256:${'a' * 64}'), isFalse);
    expect(kTlsFingerprintRe.hasMatch('sha256:abc'), isFalse);
  });
}
