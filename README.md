# CheckCheck

A small native macOS menu bar app that watches GitHub Checks and commit statuses on selected repositories and sends local notifications when their state changes.

## Features

- Select repositories from your GitHub account.
- Watch the latest commit on each repository's default branch.
- See queued, running, successful, failed, skipped, and cancelled status checks.
- Receive notifications for new runs and status transitions.
- Open the exact Check details page from a row or notification.
- Keep the GitHub token in macOS Keychain.
- Launch automatically at login by default; turn it off in Settings.
- Avoid notification noise by treating the first synchronization as a baseline.

## Build

Requirements: macOS 14+, Xcode 15+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
open CheckCheck.xcodeproj
```

Or build from Terminal:

```sh
xcodebuild -project CheckCheck.xcodeproj -scheme CheckCheck -configuration Debug build
```

The project uses ad-hoc signing for local development. Do not pass
`CODE_SIGNING_ALLOWED=NO`: macOS requires a signed app identity to register
local notification permissions.

## GitHub token

Create a [personal access token (classic)](https://github.com/settings/tokens/new?scopes=repo&description=CheckCheck%20for%20macOS) at GitHub Settings > Developer settings > Personal access tokens. GitHub's Checks API does not currently support fine-grained personal access tokens.

- Public repositories do not require a scope.
- Private repositories require the `repo` scope.

The token never leaves the Mac except in authenticated requests to `api.github.com`.

## MVP behavior

CheckCheck polls every 10 seconds while a check is queued or running, and once per minute while idle. It monitors current Check Runs and commit statuses from recent commits on each selected repository's default branch. GitHub API rate limits and individual API errors are shown in the popover footer.
