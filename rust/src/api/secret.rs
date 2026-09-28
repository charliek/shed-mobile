//! The one wrapper every secret-carrying bridge field uses (shed-mobile#30).

/// A secret on its way across the bridge: a bearer token, or the raw
/// `_bootstrap` stdout that in token mode IS a bearer plus its envelope.
///
/// It exists because of what the codegen does with a bare `String`. FRB renders
/// every fielded Rust enum as a Dart `@freezed` sealed class, and freezed
/// generates a `toString()` that prints every field. So a `String` secret on a
/// variant (`BridgeCredentialEvent::Adopted.token`,
/// `BridgeMintOutcome::Success.raw_stdout`) was printed whole by any `'$event'`
/// interpolation, log line or error message that rendered the variant
/// (shed-mobile#30).
///
/// FRB renders a plain struct like this one as a plain Dart class with `==` and
/// `hashCode` and NO `toString()`, so freezed's rendering of the enclosing
/// variant prints `Instance of 'BridgeSecret'` and never the value. Reading the
/// secret takes an explicit `.value`.
///
/// On the Rust side `Debug` is implemented by hand, to redact, so a future
/// `derive(Debug)` on an enclosing type cannot print the value there either. A
/// trait impl is not carried to Dart by the codegen.
///
/// The field is NAMED so Dart reads `.value` rather than a positional
/// `.field0`.
pub struct BridgeSecret {
    pub value: String,
}

impl std::fmt::Debug for BridgeSecret {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("BridgeSecret(<redacted>)")
    }
}

#[cfg(test)]
mod tests {
    use super::BridgeSecret;

    /// `{:?}` of the wrapper, and of anything that derives `Debug` around it,
    /// prints the marker and never the value.
    #[test]
    fn debug_never_renders_the_secret() {
        let secret = "bearer-7f3a9c-must-not-print";
        let wrapped = BridgeSecret {
            value: secret.into(),
        };
        let rendered = format!("{wrapped:?}");
        assert!(
            !rendered.contains(secret),
            "the secret rendered: {rendered}"
        );
        assert!(rendered.contains("<redacted>"), "no marker: {rendered}");

        #[derive(Debug)]
        #[allow(dead_code)] // only ever rendered
        struct Enclosing {
            token: Option<BridgeSecret>,
        }
        let nested = format!(
            "{:?}",
            Enclosing {
                token: Some(wrapped)
            }
        );
        assert!(!nested.contains(secret), "the secret rendered: {nested}");
        assert!(nested.contains("<redacted>"), "no marker: {nested}");
    }
}
