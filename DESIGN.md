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
- Check names use 13 pt semibold text.
- Repository metadata uses 11 pt monospaced text for a developer-tool signature.
- Dynamic values use monospaced digits where appropriate.

## Component styling

- Rows are flat, full-width click targets with semantic status symbols.
- Buttons use standard macOS controls, not custom pills.
- Inputs use native SecureField, TextField, Toggle, and List behavior.
- Radius scale: 6 pt for small status backgrounds, 10 pt for the single onboarding panel.

## Layout principles

- The menu popover is 380 pt wide with a 12 pt spacing rhythm.
- The header orients, the list communicates status, and the footer exposes freshness.
- Settings use one progressive account-to-repository flow: repository controls appear only after GitHub connects.

## Depth and elevation

The popover's system material provides the only elevated surface. Rows remain borderless and use separators for structure.

## Do and don't

- Do make failure and active work easy to scan.
- Do keep the repository visible on every row.
- Do make every Check row open its GitHub details.
- Do use full labels and accessibility descriptions for icon buttons.
- Don't use decorative gradients, floating cards, or permanent bright accents.
- Don't notify on the first synchronization.

## Window behavior

The menu popover stays compact. The settings window can resize vertically and supports long repository names without hiding the selection control.

## Motion

State changes rely on symbol replacement and system notification motion. The menu icon stays still so it remains legible in macOS's hosted status-item scene.
