import 'package:shed_mobile/ssh/lane_forward.dart';

/// A recording [LaneLease] fake shared by the lane_controller and
/// lane_provider tests, mirroring `FakeShedClient`'s placement
/// (`test/features/sheds/fake_shed_client.dart`) for a fake used by more than
/// one test file.
///
/// [releases] counts [release] calls, which is what makes "released exactly
/// once" and "kept across a re-open" assertable; [isValid] mirrors the
/// production contract that a released lease can no longer be reused.
class FakeLaneLease implements LaneLease {
  FakeLaneLease(this.port);

  @override
  final int port;

  int releases = 0;

  @override
  bool get isValid => releases == 0;

  @override
  Future<void> release() async => releases++;
}
