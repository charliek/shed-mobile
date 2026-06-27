/// The app's semantic version, the single source of truth for provenance strings
/// (e.g. `SHED_RC_CREATED_BY = shed-mobile/<version>`). Must track pubspec.yaml's
/// `version:` (minus the `+build` suffix) — a unit test asserts they match so
/// drift fails CI rather than shipping a stale provenance tag.
const String kAppVersion = '1.0.0';
