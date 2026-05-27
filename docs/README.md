# étui documentation

Guides for using the library. API details also live in `///` doc comments on each public function (HexDocs after publish).

| Guide | Contents |
| --- | --- |
| [Getting started](getting-started.md) | Dependency, minimal app, app loop, crash-restore |
| [Layout](layout.md) | `geometry.split`, constraints, spacing |
| [Styling](styling.md) | Colors, modifiers, spans |
| [Themes](themes.md) | Built-in palettes and runtime switching |
| [Widgets](widgets.md) | Full widget reference |
| [Custom widgets](custom-widgets.md) | Composition, stateful/animated helpers |
| [Animation](animation.md) | `run_animated`, `anim` helpers |
| [Focus](focus.md) | `FocusRing` for multi-panel UIs |

## Targets

| Target | Backend | App loop |
| --- | --- | --- |
| Erlang (default) | `etui/backend/erlang` via `default.new()` | `app.run_buffered` → `AppResult` |
| JavaScript (Node) | `etui/backend/node` via `default.new()` | `app.run_buffered` → `Promise(AppResult)` |

Use `gleam run --target erlang` for terminal apps and `gleam run --target javascript` for the JS smoke path.

## Examples in this repo

Runnable demos live under `dev/` (not shipped on Hex): `etui_showcase`, `etui_filebrowser`, `etui_interactive`, etc.
