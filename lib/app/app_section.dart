/// The three top-level navigation sections — the mobile bottom tabs and the
/// desktop sidebar items. Shared across both layouts via `appSectionProvider`.
/// (Hosts absorbed the former System section: each host row now carries its own
/// disk usage, so there's no separate System pane, and both layouts render all
/// three sections directly — no cross-breakpoint folding.)
enum AppSection { hosts, sheds, sessions }

/// The responsive breakpoint. At or above this logical width the app renders the
/// desktop sidebar layout; below it, the mobile bottom-tab layout. Pure so the
/// boundary (899 → mobile, 900 → desktop) is unit-testable instead of only
/// exercised by the drive harness at two fixed form factors.
const double kDesktopBreakpoint = 900;

bool isDesktopWidth(double width) => width >= kDesktopBreakpoint;
