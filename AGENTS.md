# Project Agent Instructions

## CUA UI validation lifecycle

- Reuse one QA application instance throughout a validation run. Do not pass
  `creates_new_application_instance: true` unless the task explicitly tests
  multi-instance behavior.
- Use one stable QA bundle identifier. Before launching, inspect running apps
  with CUA and reuse the matching PID when one already exists.
- Exercise disconnected, error, connected, empty, and other UI states inside
  the same process instead of launching one process per state.
- When a rebuild must load a new binary, gracefully quit the existing QA PID
  with CUA, verify that it is gone, and then launch exactly one replacement.
- Keep the invariant at no more than one running QA instance during
  validation. At the end, quit every agent-launched QA instance, verify the QA
  instance count is zero, and end the CUA session.
- Never leave QA menu-bar icons behind. Do not quit a user's existing
  production CheckCheck instance unless the user explicitly asks for it.
