<p align="center">
  <img src="assets/logo.png" alt="Étui logo" width="200">
</p>

<p align="center">
  <a href="https://hex.pm/packages/etui"><img src="https://img.shields.io/hexpm/v/etui" alt="Hex version"></a>
  <a href="https://hexdocs.pm/etui"><img src="https://img.shields.io/badge/hexdocs-etui-blue" alt="HexDocs"></a>
  <a href="https://github.com/lupodevelop/etui/actions/workflows/test.yml"><img src="https://github.com/lupodevelop/etui/actions/workflows/test.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/lupodevelop/etui/blob/main/LICENSE"><img src="https://img.shields.io/hexpm/l/etui" alt="License"></a>
</p>

# Étui

A TUI library for Gleam. Pure functions, composable widgets, correct Unicode.

Inspired by [ratatui](https://ratatui.rs/): buffer-diff rendering, layout constraints, and an extensible widget system, all on the Erlang/BEAM.

> *étui* (French): a small, fitted case that holds and protects delicate instruments. This library is that case for your terminal: a snug shell around buffers, widgets, and Unicode, so your app stays clean inside.

**Requirements:** Gleam 1.16+, Erlang/OTP 26+ for terminal apps. Node 22+ only for the JavaScript target smoke path.

```text
┌─ Sidebar ──┐┌─ Main ──────────────────────────┐
│  > item 1  ││ Count: 42                        │
│    item 2  ││ あいうえお  CJK = 2 cells each   │
│    item 3  ││ 👨‍👩‍👧‍👦       ZWJ family = 2 cells   │
└────────────┘└─────────────────────────────────┘
```

## Highlights

**Unicode-correct.** Cell width, not codepoints. `cell_width("你好") == 4`. Grapheme clusters come from Erlang's native UAX #29 segmentation. ZWJ sequences, combining marks, and regional indicators all cluster correctly.

**Crash-restore.** `app.run` wraps the event loop in Erlang `try...after`. The terminal is restored before any exception propagates, and on normal exit and supported abort paths.

**No-jitter layout.** `geometry.resolve_sizes` allocates on boundaries, not widths. Rounding errors don't accumulate across columns.

**Testable without a terminal.** Geometry and buffer diffing are pure functions. Tests run headless.

## Install

```sh
gleam add etui
```

Or in `gleam.toml`:

```toml
[dependencies]
etui = ">= 1.0.0 and < 2.0.0"
```

## Quickstart

```gleam
import etui/app
import etui/backend
import etui/backend/default
import etui/buffer
import etui/geometry.{type Rect, Fill, Horizontal, Percentage}
import etui/widgets/block
import etui/widgets/paragraph
import gleam/int

pub type Model {
  Model(count: Int, width: Int, height: Int)
}

pub fn main() {
  let _ =
    app.run_buffered(
      default.new(),
      Model(0, 80, 24),
      view,
      update,
      fn(m) { m.count >= 10 },
      16,
    )
}

fn view(model: Model, screen: Rect) -> buffer.Buffer {
  let chunks = geometry.split(Horizontal, screen, [Percentage(30), Fill])
  let left = case chunks { [l, ..] -> l _ -> screen }
  let right = case chunks { [_, r, ..] -> r _ -> screen }
  let para = paragraph.paragraph_new("Count: " <> int.to_string(model.count))
  let blk =
    block.block_new()
    |> block.with_border(block.Rounded)
    |> block.with_title("App", block.Top)
  buffer.buffer_new(screen)
  |> block.render(left, block.block_new() |> block.with_border(block.Single))
  |> block.render(right, blk)
  |> paragraph.render(block.inner(right, blk), para)
}

fn update(event: backend.InputEvent, model: Model) -> Model {
  case event {
    backend.KeyPress("q") -> Model(..model, count: 10)
    backend.KeyPress(" ") -> Model(..model, count: model.count + 1)
    backend.Resize(w, h) -> Model(..model, width: w, height: h)
    _ -> model
  }
}
```

## Widgets

| Widget | Module | Description |
| --- | --- | --- |
| Block | `widgets/block` | Borders, title, padding, bg fill |
| Paragraph | `widgets/paragraph` | Wrapping text, alignment |
| List | `widgets/list` | Scrollable, selectable items |
| Table | `widgets/table` | Grid with header, selection |
| Tabs | `widgets/tabs` | Horizontal tab bar |
| Gauge | `widgets/gauge` | Progress bar with label |
| HBar | `widgets/hbar` | Horizontal bar chart |
| Chart | `widgets/chart` | Line chart |
| Sparkline | `widgets/sparkline` | Inline data trend |
| Canvas | `widgets/canvas` | Braille pixel drawing |
| Input | `widgets/input` | Text input, wide-char cursor |
| Scrollbar | `widgets/scrollbar` | Scroll indicator |
| Spinner | `widgets/spinner` | Animated loading indicator |
| Marquee | `widgets/marquee` | Scrolling text ticker |
| Popup | `widgets/popup` | Centered modal overlay |
| StatusBar | `widgets/statusbar` | Left/center/right status line |
| Line | `widgets/line` | Horizontal/vertical dividers |
| Progress | `widgets/progress` | Multi-step progress tracker |
| GradientBar | `widgets/gradient_bar` | Color-gradient bar |
| Clear | `widgets/clear` | Erase area |
| Scene | `widgets/scene` | Static composed layout |
| TextArea | `widgets/textarea` | Multi-line editor |
| Tree | `widgets/tree` | Expand/collapse hierarchy, optional counts |
| Dialog | `widgets/dialog` | Modal with buttons |
| Form | `widgets/form` | Multi-field input form |
| Notification | `widgets/notification` | Toast/banner |
| ScrollView | `widgets/scroll_view` | Scrollable region wrapper |
| Paginator | `widgets/paginator` | Page indicator (dots / arabic) |
| Help | `widgets/help` | Key binding help, short and full |
| Fieldset | `widgets/fieldset` | Horizontal rule with title |
| MultiSelect | `widgets/multi_select` | Checkbox list with optional cap |

## Layout

```gleam
import etui/geometry.{Horizontal, Vertical, Length, Percentage, Fill}

// Constraints: Length(n) fixed cells, Percentage(n) of total, Fill = remainder
let cols = geometry.split(Horizontal, area, [Length(20), Percentage(50), Fill])
let rows = geometry.split(Vertical, area, [Length(3), Fill])
```

## Styling

```gleam
import etui/style

style.Indexed(1)           // 16-color palette
style.Rgb(255, 128, 0)     // 24-bit true color
style.bold()               // modifier
style.italic()
style.underline()
style.reverse()
```

## Themes

```gleam
import etui/theme

let t = theme.dracula()         // dark purple, RGB
let t = theme.nord()            // arctic dark, RGB
let t = theme.catppuccin_mocha() // pastel dark, RGB
let t = theme.gruvbox_dark()    // retro groove, RGB
let t = theme.tokyo_night()     // cool blue, RGB
let t = theme.dark()            // ANSI 16-color (max compatibility)

// Use color slots directly
block.block_new() |> block.with_style(t.border, t.bg)

// Or use pre-built Style helpers
list_widget |> glist.with_highlight_style(theme.selection(t))

// Customize from a base
let custom = theme.Theme(..theme.nord(), accent: style.Rgb(255, 165, 0))
```

10 built-in themes. RGB (`style.Rgb(r,g,b)`) and 256-color (`style.Indexed(n)`) both supported. ANSI themes for terminals without true-color.

## Widget system

Any `fn(Buffer, Rect) -> Buffer` is a widget. No registration, no traits.

```gleam
import etui/widget

// Compose: border + inner content
let w = widget.compose(border_w, block.inner(area, blk), content_w)

// Layer: draw top over bottom
let w = widget.layer(background_w, overlay_w)

// Stack: multiple widgets in same area, in order
let w = widget.stack([bg_w, content_w, cursor_w])

// Stateful widget
let sw = widget.StatefulWidget(render: fn(buf, area, state: MyState) { ... })
widget.render_stateful(buf, area, sw, my_state)

// Animated widget
let aw: widget.AnimatedWidget = fn(buf, area, frame) { ... }
widget.freeze_frame(aw, current_frame)(buf, area)
```

## App loop

Most apps use **`run_buffered`**: you return a `Buffer`, étui diffs it each frame.

```gleam
app.run_buffered(
  default.new(),
  model,
  fn(m, screen) { /* build buffer */ },
  fn(ev, m) { /* update model */ },
  fn(m) { m.quit },
  16,
)
```

| API | When |
| --- | --- |
| `run_buffered` | Default full-screen UI |
| `run_buffered_cursor` | Inputs with visible hardware cursor |
| `run_animated` | Frame-based widgets (`AnimState` passed to `view`) |
| `run` | Low-level `List(RenderOp)` control |

On **JavaScript** (Node), the same functions return `Promise(AppResult(_))`.

Low-level `RenderOp` values: `Write`, `MoveCursor`, `ClearScreen`, `EnterAltScreen`, `ExitAltScreen`, `EnableMouse`, `DisableMouse`. Enable mouse with `default.new_with_mouse()`.

## Examples in this repo

Demos under `dev/` (not published to Hex):

```sh
gleam run -m etui_showcase
gleam run -m etui_filebrowser
gleam run --target javascript -m etui_js_smoke
```

## Docs

See [`docs/`](docs/) (index: [docs/README.md](docs/README.md)):

- [Getting started](docs/getting-started.md)
- [Layout](docs/layout.md)
- [Styling](docs/styling.md)
- [Themes](docs/themes.md)
- [Widgets](docs/widgets.md)
- [Custom widgets](docs/custom-widgets.md)
- [Animation](docs/animation.md)
- [Focus](docs/focus.md)

Contributors: [CONTRIBUTING.md](CONTRIBUTING.md)

## License

MIT
