/// The four top-level navigation sections — the mobile bottom tabs and the desktop
/// sidebar items. Shared across both layouts via `appSectionProvider`.
enum AppSection { hosts, sheds, sessions, system }

/// The responsive breakpoint. At or above this logical width the app renders the
/// desktop sidebar layout; below it, the mobile bottom-tab layout. Pure so the
/// boundary (899 → mobile, 900 → desktop) is unit-testable instead of only
/// exercised by the drive harness at two fixed form factors.
const double kDesktopBreakpoint = 900;

bool isDesktopWidth(double width) => width >= kDesktopBreakpoint;

/// Desktop has no Hosts pane — hosts live in the sidebar — so the shared `hosts`
/// section maps to `sheds` when rendering desktop (and highlights Sheds). This
/// keeps a cross-breakpoint resize while on `hosts` well-defined. Identity for the
/// other sections.
AppSection sectionForDesktop(AppSection section) =>
    section == AppSection.hosts ? AppSection.sheds : section;
