# CheckCheck design direction

## Visual theme and atmosphere

CheckCheck is a quiet native status instrument: compact, precise, and useful at a glance. It follows macOS conventions without turning every section into a card.

## Color palette and roles

- Canvas: system window background and menu material.
- Primary text: `Color.primary` for names and decisions.
- Secondary text: `Color.secondary` for repository and timing metadata.
- Running: system blue, used only for active work.
- Success: system green, used only for completed checks.
- Failure: system red, used only for outcomes requiring attention.
- Neutral: system gray for queued, skipped, and idle states.

## Typography rules

- SF Pro is used through SwiftUI system fonts because this is a compact native utility.
- Repository names use 13 pt semibold text; duplicate names include the owner.
- Check names use 12 pt primary text. Status, timing, and commit metadata use 11 pt text.
- Truncated repository names, check names, and commit subjects expose their full text on hover.
- Dynamic values use monospaced digits where appropriate.

## Component styling

- Rows are flat, full-width click targets with semantic status symbols.
- Buttons use standard macOS controls. Check rows have hover feedback, a visible keyboard focus outline, and Space/Return activation.
- Settings use a native grouped Form, SecureField, TextField, and checkbox Toggles for repository selection.
- Native grouped forms own their surfaces and spacing. The row focus outline uses a 4 pt corner radius.

## Layout principles

- The menu popover is 380 pt wide with a 12 pt spacing rhythm.
- The header exposes Settings and Quit in a menu. The list communicates check status, and the footer exposes the last complete sync time.
- A sync warning above the list marks retained results as potentially out of date. Details list each affected repository and its last successful sync; first-sync failures have their own retry state.
- Background refreshes never replace the menu bar outcome symbol. Incomplete sync uses a warning triangle until recovery.
- Settings follow Account → Repositories → General. Repository controls appear only after GitHub connects; account, repository-list, and check-sync errors stay in their own contexts.

## Depth and elevation

Rows remain flat and use separators for structure. Settings use system grouped-form surfaces; error details use a standard popover.

## Do and don't

- Do make failure and active work easy to scan.
- Do keep the repository visible on every row.
- Do make every Check row open its GitHub details.
- Do use full labels and accessibility descriptions for icon buttons.
- Don't use decorative gradients, floating cards, or permanent bright accents.
- Don't notify on the first synchronization.

## Window behavior

The menu popover stays at 380 × 440 pt. Settings adapt from 620 to 800 pt wide and can resize vertically; long repository names never hide their checkbox. The system supplies the settings title bar and window controls.

## Motion

State changes rely on symbol replacement and system notification motion. Settings reveal connected controls without custom movement, including with Reduce Motion enabled. The menu icon stays still so it remains legible in macOS's hosted status-item scene.
