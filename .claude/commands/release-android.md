# Release Android Command

Build and publish the **Shed** Android app bundle to the Play Store via the
`release-android.yml` workflow (uploads a draft; you promote it in the console).

## Steps

1. **Check branch**: Run `git branch --show-current`. If not on `main`, stop and
   inform the user.

2. **Verify CI status**: `gh run list --commit $(git rev-parse HEAD) --status completed --json conclusion,name`.
   All workflows should be "success". If CI hasn't completed or failed, warn the
   user but allow them to proceed (the release workflow runs its own Flutter checks).

3. **Check for uncommitted changes**: `git status --porcelain`. If dirty, warn and
   ask whether to proceed.

4. **Select track**: Ask which track to target. Default `internal`; options
   internal, alpha, beta, production. For production, require explicit confirmation.

5. **Release notes**: Summarize what changed for this release (from the latest
   `PROGRESS.md` Log entry or the recent commits) and show the user a preview to
   confirm or edit.

6. **Trigger**: `gh workflow run release-android.yml --ref main -f track=<track> -f "release_notes=<notes>"`. Wait a few seconds for the run to appear.

7. **Monitor**: get the run id with
   `gh run list --workflow=release-android.yml --limit=1 --json databaseId --jq '.[0].databaseId'`,
   then `gh run watch <run-id> --exit-status`.

8. **Report**: On success, show the release name + track and the Actions URL, and
   remind the user the release is a **draft** that must be promoted at
   <https://play.google.com/console>. On failure, fetch `gh run view <run-id> --log-failed`.

## Notes

- Requires the five repo secrets (see [docs/android-release.md](../../docs/android-release.md)):
  `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_PASSWORD`, `KEY_ALIAS`,
  `PLAY_STORE_SERVICE_ACCOUNT_JSON`.
- The first-ever upload must be done **manually** (see the same doc); the workflow
  is for subsequent releases.
- Every upload needs a strictly higher versionCode; the workflow derives it from
  the run number + offset automatically.
