# CheckCheck

A small native macOS menu bar app that watches GitHub Check Runs on selected repositories and sends local notifications when their state changes.

## Features

- Select repositories from your GitHub account.
- Watch the latest commit on each repository's default branch.
- See queued, running, successful, failed, skipped, and cancelled Checks.
- Receive notifications for new runs and status transitions.
- Open the exact Check details page from a row or notification.
- Keep the GitHub token in macOS Keychain.
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

## GitHub token

Create a [personal access token (classic)](https://github.com/settings/tokens/new?scopes=repo&description=CheckCheck%20for%20macOS) at GitHub Settings > Developer settings > Personal access tokens. GitHub's Checks API does not currently support fine-grained personal access tokens.

- Public repositories do not require a scope.
- Private repositories require the `repo` scope.

The token never leaves the Mac except in authenticated requests to `api.github.com`.

## MVP behavior

CheckCheck polls once per minute while running. It monitors Check Runs attached to the latest commit of each selected repository's default branch. GitHub API rate limits and individual API errors are shown in the popover footer.
