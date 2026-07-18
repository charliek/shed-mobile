//! `BridgeError` — the single data-carrying error the bridge surfaces to Dart
//! (plan §3.6). Every `BridgeClient` method returns `Result<T, BridgeError>`.
//!
//! It wraps the three shed-core error domains — `ShedError` (HTTP/transport),
//! `RcError` (the rc binary's exit-code domain), and `TokenBundleError` (the
//! control-bundle parse) — as distinct variants so the app can `switch` on them
//! exhaustively. FRB 2.13 renders this fielded enum as a Dart 3 **sealed
//! class**, so the Dart side gets compiler-enforced exhaustiveness.
//!
//! **Status codes are preserved** (`BadStatus{code}`), which is load-bearing:
//! mobile distinguishes a **404** to drive the `OverviewUnsupported`
//! (server-too-old) path (`shed_client.dart:61`) and `RC_SESSION_GONE`
//! (`shed_client.dart:214`). A lossy "some error happened" mapping would break
//! those; the conversion tests pin it.
//!
//! Secret handling (AC#5): none of these variants carry token bytes — the
//! shed-core errors they wrap are already redacted at the source (e.g.
//! `token.rs`'s `MINT_FAILED_REDACTED`), and `TokenBundleError` carries no
//! payload at all. A unit test asserts no token material appears under
//! `Debug`/`Display`.

use shed_core::http::ShedError;
use shed_core::rc::RcError;
use shed_core::token::TokenBundleError;

/// Sentinel prefix the mint path stamps on a `ShedError::Transport` message when
/// the underlying failure is actually a typed `TokenBundleError` (Codex review
/// #3). The `TokenMinter` trait can only return `ShedError`, so the typed bundle
/// error (`PinMismatch` — a possible MITM — / `PinMissing` / `AuthExpired`) would
/// otherwise collapse to a generic transport error and never reach the app.
/// `run_mint` encodes the variant here; [`From<ShedError>`] below recovers it
/// into the correct `BridgeError::Token*` variant. Leads with a control byte so
/// it can't collide with a real transport message; carries only the variant name
/// (no token bytes — AC#5).
///
/// TODO(shed follow-up): a first-class `ShedError::TokenBundle(TokenBundleError)`
/// variant in shed-core would make this marker unnecessary. Candidate shed PR.
pub(crate) const TOKEN_ERR_MARKER: &str = "\u{1}shed-token-bundle-error:";

/// Encode a `TokenBundleError` as a marked transport message (the mint side).
pub(crate) fn encode_token_err(e: &TokenBundleError) -> String {
    let tag = match e {
        TokenBundleError::AuthExpired => "AuthExpired",
        TokenBundleError::PinMismatch => "PinMismatch",
        TokenBundleError::PinMissing => "PinMissing",
    };
    format!("{TOKEN_ERR_MARKER}{tag}")
}

/// The bridge's unified error, rendered by FRB 2.13 as a Dart sealed class.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeError {
    /// shed-server returned a non-2xx HTTP status. `code` is preserved so the
    /// app can distinguish 404 (`OverviewUnsupported` / `RC_SESSION_GONE`).
    BadStatus { code: u16 },
    /// A transport-layer failure (connect/TLS/timeout) — no HTTP status.
    Transport { msg: String },
    /// A response body failed to decode.
    Decode { msg: String },
    /// A `create_shed` stream ended in failure.
    Create { msg: String },
    /// A client-construction / configuration refusal (e.g. a TLS pin on a
    /// non-https URL).
    Config { msg: String },

    /// `shed-ext-rc` reported the slug already exists (exit 3).
    RcSlugTaken { detail: String },
    /// `shed-ext-rc` reported the session was not found (exit 4).
    RcNotFound { detail: String },
    /// `shed-ext-rc` rejected the request (exit 2 / validation gate).
    RcBadRequest { detail: String },
    /// `shed-ext-rc` is not installed on the shed (exit 127).
    RcMissingBinary,
    /// Any other rc binary / transport failure.
    RcFailed { detail: String },

    /// The control bundle is expired or malformed (`SHED_AUTH_EXPIRED`).
    TokenAuthExpired,
    /// The bundle's TLS fingerprint differs from the configured pin
    /// (`SHED_TLS_PIN_MISMATCH`).
    TokenPinMismatch,
    /// The bundle omits a required TLS fingerprint (`SHED_TLS_PIN_MISSING`).
    TokenPinMissing,
}

impl From<ShedError> for BridgeError {
    fn from(e: ShedError) -> Self {
        match e {
            ShedError::BadStatus(code) => BridgeError::BadStatus { code },
            // Recover a typed token-bundle error that had to travel as a marked
            // transport message (Codex review #3), so a pin mismatch surfaces as
            // TokenPinMismatch rather than a generic Transport error.
            ShedError::Transport(msg) => match msg.strip_prefix(TOKEN_ERR_MARKER) {
                Some("AuthExpired") => BridgeError::TokenAuthExpired,
                Some("PinMismatch") => BridgeError::TokenPinMismatch,
                Some("PinMissing") => BridgeError::TokenPinMissing,
                _ => BridgeError::Transport { msg },
            },
            ShedError::Decode(msg) => BridgeError::Decode { msg },
            ShedError::Create(msg) => BridgeError::Create { msg },
            ShedError::Config(msg) => BridgeError::Config { msg },
        }
    }
}

impl From<RcError> for BridgeError {
    fn from(e: RcError) -> Self {
        match e {
            RcError::SlugTaken(detail) => BridgeError::RcSlugTaken { detail },
            RcError::NotFound(detail) => BridgeError::RcNotFound { detail },
            RcError::BadRequest(detail) => BridgeError::RcBadRequest { detail },
            RcError::MissingBinary => BridgeError::RcMissingBinary,
            RcError::Failed(detail) => BridgeError::RcFailed { detail },
        }
    }
}

impl From<TokenBundleError> for BridgeError {
    fn from(e: TokenBundleError) -> Self {
        match e {
            TokenBundleError::AuthExpired => BridgeError::TokenAuthExpired,
            TokenBundleError::PinMismatch => BridgeError::TokenPinMismatch,
            TokenBundleError::PinMissing => BridgeError::TokenPinMissing,
        }
    }
}

impl std::fmt::Display for BridgeError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            BridgeError::BadStatus { code } => write!(f, "shed-server returned HTTP {code}"),
            BridgeError::Transport { msg } => write!(f, "transport error: {msg}"),
            BridgeError::Decode { msg } => write!(f, "decode error: {msg}"),
            BridgeError::Create { msg } => write!(f, "create failed: {msg}"),
            BridgeError::Config { msg } => write!(f, "{msg}"),
            BridgeError::RcSlugTaken { detail } => write!(f, "rc session already exists: {detail}"),
            BridgeError::RcNotFound { detail } => write!(f, "rc session not found: {detail}"),
            BridgeError::RcBadRequest { detail } => write!(f, "invalid rc request: {detail}"),
            BridgeError::RcMissingBinary => {
                write!(f, "shed-ext-rc is not installed on this shed")
            }
            BridgeError::RcFailed { detail } => write!(f, "rc operation failed: {detail}"),
            BridgeError::TokenAuthExpired => {
                write!(f, "control token bundle rejected: expired or malformed")
            }
            BridgeError::TokenPinMismatch => {
                write!(f, "control token bundle TLS fingerprint mismatch")
            }
            BridgeError::TokenPinMissing => {
                write!(f, "control token bundle omits a valid tls_cert_fingerprint")
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn shed_error_preserves_status_code() {
        // The load-bearing 404 distinction (OverviewUnsupported / RC_SESSION_GONE).
        assert_eq!(
            BridgeError::from(ShedError::BadStatus(404)),
            BridgeError::BadStatus { code: 404 }
        );
        assert_eq!(
            BridgeError::from(ShedError::BadStatus(503)),
            BridgeError::BadStatus { code: 503 }
        );
    }

    #[test]
    fn shed_error_variants_map_exhaustively() {
        assert_eq!(
            BridgeError::from(ShedError::Transport("boom".into())),
            BridgeError::Transport { msg: "boom".into() }
        );
        assert_eq!(
            BridgeError::from(ShedError::Decode("bad json".into())),
            BridgeError::Decode { msg: "bad json".into() }
        );
        assert_eq!(
            BridgeError::from(ShedError::Create("provision failed".into())),
            BridgeError::Create { msg: "provision failed".into() }
        );
        assert_eq!(
            BridgeError::from(ShedError::Config("no pin".into())),
            BridgeError::Config { msg: "no pin".into() }
        );
    }

    #[test]
    fn rc_error_variants_map_exhaustively() {
        assert_eq!(
            BridgeError::from(RcError::SlugTaken("cdx".into())),
            BridgeError::RcSlugTaken { detail: "cdx".into() }
        );
        assert_eq!(
            BridgeError::from(RcError::NotFound("cdx".into())),
            BridgeError::RcNotFound { detail: "cdx".into() }
        );
        assert_eq!(
            BridgeError::from(RcError::BadRequest("bad mode".into())),
            BridgeError::RcBadRequest { detail: "bad mode".into() }
        );
        assert_eq!(
            BridgeError::from(RcError::MissingBinary),
            BridgeError::RcMissingBinary
        );
        assert_eq!(
            BridgeError::from(RcError::Failed("ssh down".into())),
            BridgeError::RcFailed { detail: "ssh down".into() }
        );
    }

    #[test]
    fn marked_transport_recovers_typed_token_error() {
        // Codex review #3: a token-bundle error tunnelled through
        // ShedError::Transport must recover to the typed BridgeError variant.
        for e in [
            TokenBundleError::AuthExpired,
            TokenBundleError::PinMismatch,
            TokenBundleError::PinMissing,
        ] {
            let marked = ShedError::Transport(encode_token_err(&e));
            assert_eq!(BridgeError::from(marked), BridgeError::from(e));
        }
        // Pin mismatch specifically (the MITM signal) is not a Transport error.
        let marked = ShedError::Transport(encode_token_err(&TokenBundleError::PinMismatch));
        assert_eq!(BridgeError::from(marked), BridgeError::TokenPinMismatch);
        // A genuine transport message (no marker) stays Transport.
        assert_eq!(
            BridgeError::from(ShedError::Transport("connection refused".into())),
            BridgeError::Transport { msg: "connection refused".into() }
        );
    }

    #[test]
    fn token_error_variants_map_exhaustively() {
        assert_eq!(
            BridgeError::from(TokenBundleError::AuthExpired),
            BridgeError::TokenAuthExpired
        );
        assert_eq!(
            BridgeError::from(TokenBundleError::PinMismatch),
            BridgeError::TokenPinMismatch
        );
        assert_eq!(
            BridgeError::from(TokenBundleError::PinMissing),
            BridgeError::TokenPinMissing
        );
    }
}
