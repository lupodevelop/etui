# Themes

`etui/theme` provides a semantic color palette system. One import and one function call swap the entire UI palette.

## Built-in themes

| Theme | Style | Colors |
| --- | --- | --- |
| `dark()` | Generic dark | ANSI 16-color (max compatibility) |
| `light()` | Generic light | ANSI 16-color (max compatibility) |
| `dracula()` | Purple dark | RGB |
| `nord()` | Arctic dark | RGB |
| `catppuccin_mocha()` | Pastel dark | RGB |
| `catppuccin_latte()` | Pastel light | RGB |
| `monokai()` | Vibrant dark | RGB |
| `gruvbox_dark()` | Retro groove dark | RGB |
| `tokyo_night()` | Cool blue dark | RGB |
| `solarized_dark()` | Precision dark | RGB |

ANSI themes (`dark`, `light`) work on every terminal including those without true-color support. RGB themes require a truecolor terminal (most modern terminals support this).

## Usage

```gleam
import etui/theme
import etui/widgets/block
import etui/widgets/list as glist

let t = theme.dracula()

// Use colors directly on widgets
let blk =
  block.block_new()
  |> block.with_border(block.Rounded)
  |> block.with_style(t.border, t.bg)
  |> block.with_title("Panel", block.Top)

// Use style helpers
let l =
  glist.list_new(["item 1", "item 2"])
  |> glist.with_highlight_style(theme.selection(t))
```

## Color slots

```gleam
t.bg               // main background
t.fg               // main foreground
t.border           // border lines
t.title            // border titles
t.selection_bg     // selected item background
t.selection_fg     // selected item foreground
t.accent           // primary accent (links, highlights)
t.muted            // subdued/secondary text
t.error            // error messages
t.warning          // warnings
t.success          // success messages
t.info             // informational messages
t.statusbar_bg     // status bar background
t.statusbar_fg     // status bar foreground
```

## Style helpers

Pre-built `style.Style` values from a theme:

```gleam
theme.normal(t)          // fg on bg
theme.selection(t)       // selection_fg on selection_bg
theme.accent_style(t)    // accent on bg
theme.border_style(t)    // border on bg
theme.title_style(t)     // title on bg
theme.muted_style(t)     // muted on bg
theme.error_style(t)     // error on bg, bold
theme.warning_style(t)   // warning on bg
theme.success_style(t)   // success on bg
theme.info_style(t)      // info on bg
theme.statusbar_style(t) // statusbar_fg on statusbar_bg
```

## Custom themes

Option 1: full definition.

```gleam
let my_theme = theme.Theme(
  bg:            style.Rgb(30, 30, 46),
  fg:            style.Rgb(205, 214, 244),
  border:        style.Rgb(137, 180, 250),
  title:         style.Rgb(166, 227, 161),
  selection_bg:  style.Rgb(69, 71, 90),
  selection_fg:  style.Rgb(205, 214, 244),
  accent:        style.Rgb(137, 180, 250),
  muted:         style.Rgb(108, 112, 134),
  error:         style.Rgb(243, 139, 168),
  warning:       style.Rgb(249, 226, 175),
  success:       style.Rgb(166, 227, 161),
  info:          style.Rgb(137, 220, 235),
  statusbar_bg:  style.Rgb(24, 24, 37),
  statusbar_fg:  style.Rgb(205, 214, 244),
)
```

Option 2: derive from a built-in and override specific slots.

```gleam
// Gleam record update syntax
let my_theme = theme.Theme(..theme.nord(), accent: style.Rgb(255, 165, 0))

// Or use helpers
let my_theme =
  theme.nord()
  |> theme.with_accent(style.Rgb(255, 165, 0))
  |> theme.with_statusbar(style.Rgb(0, 0, 0), style.Rgb(255, 255, 255))
  |> theme.with_selection(style.Rgb(60, 80, 120), style.Rgb(240, 240, 240))
```

## RGB colors

`style.Rgb(r, g, b)` uses 24-bit true color. Emits `\e[38;2;r;g;bm` (fg) or `\e[48;2;r;g;bm` (bg).

```gleam
style.Rgb(255, 128, 0)     // orange
style.Rgb(0, 0, 0)         // black
style.Rgb(255, 255, 255)   // white
```

Requires a truecolor-capable terminal. When in doubt, use `dark()` or `light()` (ANSI Indexed colors) for maximum compatibility.

## Full app example

```gleam
import etui/theme
import etui/style
import etui/widgets/block
import etui/widgets/paragraph
import etui/widgets/statusbar
import etui/span

pub type Model {
  Model(theme: theme.Theme, ...)
}

fn view(model: Model, screen: geometry.Rect) -> buffer.Buffer {
  let t = model.theme

  let header =
    statusbar.statusbar_new()
    |> statusbar.with_left([span.line_plain("myapp")])
    |> statusbar.with_right([span.line_plain("q: quit")])
    |> statusbar.with_style(t.statusbar_fg, t.statusbar_bg)

  let content_block =
    block.block_new()
    |> block.with_border(block.Rounded)
    |> block.with_style(t.border, t.bg)
    |> block.with_bg_fill

  let para =
    paragraph.paragraph_new("Hello!")
    |> paragraph.with_style(theme.normal(t))

  let #(header_area, body_area) = case geometry.split_v(screen, [Length(1), Fill]) {
    [h, b, ..] -> #(h, b)
    _ -> #(screen, screen)
  }

  buffer.buffer_new(screen)
  |> statusbar.render(header_area, header)
  |> block.render(body_area, content_block)
  |> paragraph.render(block.inner(body_area, content_block), para)
}

fn update(event, model) {
  case event {
    // Switch theme at runtime
    KeyPress("d") -> Model(..model, theme: theme.dracula())
    KeyPress("n") -> Model(..model, theme: theme.nord())
    KeyPress("g") -> Model(..model, theme: theme.gruvbox_dark())
    _ -> model
  }
}
```
