# Widgets Reference

All widgets are pure render functions. Typical signature: `render(buf, area, widget) -> Buffer`.
Stateful widgets use `render_stateful(buf, area, widget, state) -> Buffer`.

---

## Block

Draws a border, optional title, and optional padding. The foundation for most compound widgets.

```gleam
import etui/widgets/block

let blk =
  block.block_new()
  |> block.with_border(block.Single)        // ┌─┐│└─┘
  |> block.with_border(block.Double)        // ╔═╗║╚═╝
  |> block.with_border(block.Rounded)       // ╭─╮│╰─╯
  |> block.with_title("Title", block.Top)   // top or block.Bottom
  |> block.with_padding(1, 1, 2, 2)         // top, bottom, left, right
  |> block.with_style(fg, bg)
  |> block.with_bg_fill                     // fill inner area with bg color

block.render(buf, area, blk)

// Get inner content area (excluding border + padding)
let inner = block.inner(area, blk)
```

---

## Paragraph

Word-wrapping text with alignment.

```gleam
import etui/widgets/paragraph

let para =
  paragraph.paragraph_new("Text that wraps at area width")
  |> paragraph.with_alignment(text.Left)    // Left, Center, Right
  |> paragraph.with_style(style.Style(...))

paragraph.render(buf, area, para)
```

CJK text wraps on character boundaries. Explicit `\n` forces a new line.

---

## List

Scrollable, selectable item list. State keeps selected index and scroll offset.

```gleam
import etui/widgets/list as glist

let items = ["item 1", "item 2", "item 3"]
let l =
  glist.list_new(items)
  |> glist.with_highlight_style(style.Style(...))

let state = glist.state_new()
// Navigate
let state = glist.select_next(state, list.length(items))
let state = glist.select_prev(state)

// Render
let buf = glist.render_stateful(buf, area, l, state)

// Read selection
state.selected  // Int, 0-based index
```

Each row is `width` cells wide exactly. Selection prefix `▶` (plus a space) is included in width budget.

---

## Table

Grid with optional header and row selection.

```gleam
import etui/widgets/table

let t =
  table.table_new([
    ["Name", "Age"],   // header row (if show_header: True)
    ["Alice", "30"],
    ["Bob", "25"],
  ])
  |> table.with_col_widths([12, 5])
  |> table.with_header(True)

let state = table.state_new()
table.render_stateful(buf, area, t, state)
```

Columns separated by `│`. Each column padded/truncated to its width.

---

## Tabs

Horizontal tab bar.

```gleam
import etui/widgets/tabs

let t =
  tabs.tabs_new(["Files", "Git", "Logs"])
  |> tabs.with_active(1)       // 0-based index
  |> tabs.with_divider(" | ")

tabs.render(buf, area, t)
```

Active tab renders with reverse+bold by default. Customise with `with_active_style`.

---

## Gauge

Horizontal progress bar.

```gleam
import etui/widgets/gauge

let g =
  gauge.gauge_new(60)           // 0–100
  |> gauge.with_label("60%")   // centered overlay
  |> gauge.with_chars("█", "░") // filled, empty chars

gauge.render(buf, area, g)
```

---

## LineGauge

Thin single-row progress indicator using Unicode line characters. Lighter than `Gauge`.

```gleam
import etui/widgets/line_gauge

let g =
  line_gauge.line_gauge_new(75)        // 0–100
  |> line_gauge.with_label("75%")      // centered overlay
  |> line_gauge.with_line_set(line_gauge.ThinLine)   // ThinLine, ThickLine, DoubleLine, BrailleLine, AsciiLine
  |> line_gauge.with_colors(style.Indexed(2), style.Default)

line_gauge.render(buf, area, g)
```

---

## HBar

Horizontal bar chart.

```gleam
import etui/widgets/hbar

hbar.render(buf, area, hbar.hbar_new([
  hbar.Bar("Rust", 90),
  hbar.Bar("Gleam", 75),
  hbar.Bar("Python", 60),
]))
```

---

## Sparkline

Inline data trend (single row).

```gleam
import etui/widgets/sparkline

sparkline.render(buf, area, sparkline.sparkline_new([1, 4, 2, 8, 5, 7, 3]))
```

Uses braille dots by default. Values auto-scaled to area height.

---

## Canvas (Braille)

2×4 braille dot canvas. Each terminal cell = 2×4 pixel grid.

```gleam
import etui/widgets/canvas
import etui/braille

let c = canvas.canvas_new(area.size.width * 2, area.size.height * 4)
let c = canvas.set_pixel(c, 10, 5, True)
let c = canvas.line(c, 0, 0, 40, 20, True)

canvas.render(buf, area, c)
```

Braille block: U+2800–U+28FF. Pixel (col, row) maps to cell (col/2, row/4).

---

## Input

Single-line text input with wide-char aware cursor.

```gleam
import etui/widgets/input as ginput

let w = ginput.input_new("placeholder") |> ginput.with_max_length(80)
let state = ginput.state_new()

// Keyboard handling with keys.match instead of raw strings
import etui/keys

let state = case event {
  backend.KeyPress(k) -> case keys.match(k) {
    keys.Enter      -> state  // submit
    keys.Backspace  -> ginput.backspace(state)
    keys.Left       -> ginput.move_cursor_left(state)
    keys.Right      -> ginput.move_cursor_right(state)
    keys.Char(c)    -> ginput.insert_char(w, state, c)
    _               -> state
  }
  _ -> state
}

ginput.render(buf, area, w, state)

// Read value
state.value   // String
state.cursor  // Int, cell position (not grapheme index)
```

### Extra cursor ops

```gleam
ginput.move_to_start(state)
ginput.move_to_end(state)
ginput.delete_to_end(state)
```

### Prompt and password mode

```gleam
let w =
  ginput.input_new("username")
  |> ginput.with_prompt("> ")        // prefix shown before the value

let pw =
  ginput.input_new("password")
  |> ginput.with_password(True)      // mask each cell of the value
  |> ginput.with_mask("•")           // default mask is "*"
```

---

## Scrollbar

Scroll indicator (vertical or horizontal).

```gleam
import etui/widgets/scrollbar

// total = item count, visible = viewport height/width, offset = first visible index
let sb = scrollbar.scrollbar_new(total, visible, offset)
  |> scrollbar.with_chars("░", "█")   // track, thumb
  |> scrollbar.with_arrows("▲", "▼")  // pass "" to hide

scrollbar.render_vertical(buf, area, sb)    // vertical (right-side column)
scrollbar.render_horizontal(buf, area, sb)  // horizontal (bottom row)
```

Derive `offset` from the widget that owns the scroll:

```gleam
// List
let offset = glist.effective_offset(list_state, area.size.height)
// Table (subtract 1 when show_header is True)
let offset = table.effective_offset(table_state, area.size.height - 1)
// Tree
let total  = tree.visible_row_count(tree_state, t)
let offset = tree.effective_offset(tree_state, t, area.size.height)
// TextArea
let offset = ta.effective_offset(editor_state, area.size.height)
```

---

## Spinner

Animated loading indicator. 14 built-in presets.

```gleam
import etui/widgets/spinner

let s =
  spinner.spinner_new()
  |> spinner.with_style(spinner.Dots)
  |> spinner.with_label("loading...")

spinner.render(buf, area, s, frame)  // frame from AnimState
```

Available styles: `Dots`, `Line`, `Circle`, `Bounce`, `MiniDot`, `Jump`,
`Pulse`, `Points`, `Globe`, `Moon`, `Monkey`, `Meter`, `Hamburger`, `Ellipsis`,
and `Custom(frames)` for your own frame list.

---

## Marquee

Scrolling text ticker.

```gleam
import etui/widgets/marquee

let m = marquee.marquee_new("scrolling content  ")
  |> marquee.with_speed(2)   // cells per frame advance

marquee.render(buf, area, m, frame)
```

Wide-char aware: scroll offset is cell-accurate.

---

## Popup

Centered modal overlay.

```gleam
import etui/widgets/popup

let p =
  popup.popup_new(40, 10)
  |> popup.with_title("Confirm")
  |> popup.with_border(block.Rounded)
  |> popup.with_style(style.Default, style.Indexed(0))

// Render the popup border
let buf = popup.render(buf, screen, p)

// Get inner content area for child widgets
let inner = popup.popup_area(screen, p)
let buf = paragraph.render(buf, inner, content_para)
```

`popup_rect(screen, p)` returns the outer border rect. `popup_area(screen, p)` returns the inner content rect. Both clamp to screen bounds.

---

## StatusBar

Horizontal bar with left, center, and right span sections.

```gleam
import etui/widgets/statusbar

let bar =
  statusbar.statusbar_new()
  |> statusbar.with_left([span.line_plain("INSERT")])
  |> statusbar.with_center([span.line_plain("my-file.txt")])
  |> statusbar.with_right([span.line_plain("Ln 42  Col 8")])
  |> statusbar.with_style(style.Default, style.Indexed(4))

statusbar.render(buf, area, bar)
```

Left section is flush-left. Right section is flush-right. Center section is centered. Sections use `span.Line` for mixed-style text.

---

## Line

Horizontal or vertical divider.

```gleam
import etui/widgets/line

line.render(buf, area, line.line_new(line.Horizontal))
line.render(buf, area, line.line_new(line.Vertical))
```

---

## GradientBar

Color-gradient horizontal bar.

```gleam
import etui/widgets/gradient_bar

gradient_bar.render(buf, area, gradient_bar.gradient_bar_new(
  from: style.Rgb(255, 0, 0),
  to: style.Rgb(0, 0, 255),
))
```

---

## Progress

Multi-step progress tracker.

```gleam
import etui/widgets/progress

let p = progress.progress_new(steps: 5, current: 2)
progress.render(buf, area, p)
```

---

## Clear

Erase all cells in area to space/default style.

```gleam
import etui/widgets/clear

clear.render(buf, area)
```

---

## Scene

Pre-composed static layout. Attach multiple widgets to named areas, render all at once.

```gleam
import etui/widgets/scene

let s =
  scene.scene_new()
  |> scene.add("header", header_w, header_area)
  |> scene.add("body", body_w, body_area)

scene.render(buf, s)
```

---

## TextArea

Multi-line text editor with wide-char-aware cursor and vertical scroll. Lines are truncated (not wrapped) at the area width.

```gleam
import etui/widgets/textarea as ta

let w = ta.textarea_new()
  |> ta.with_max_lines(100)
  |> ta.with_max_line_length(200)

let state = ta.state_new()

// Keyboard handling with keys.match instead of raw strings
import etui/keys

let state = case event {
  backend.KeyPress(k) -> case keys.match(k) {
    keys.Enter     -> ta.newline(w, state)
    keys.Backspace -> ta.backspace(state)
    keys.Up        -> ta.move_cursor_up(state)
    keys.Down      -> ta.move_cursor_down(state)
    keys.Left      -> ta.move_cursor_left(state)
    keys.Right     -> ta.move_cursor_right(state)
    keys.Home      -> ta.move_to_line_start(state)
    keys.End       -> ta.move_to_line_end(state)
    keys.Char(c)   -> ta.insert_char(w, state, c)
    _              -> state
  }
  _ -> state
}

ta.render(buf, area, w, state)

// Read value
ta.value(state)       // String, lines joined with "\n"
ta.line_count(state)  // Int
```

Cursor wraps across line boundaries on left/right. Up/down clamp `cursor_x` to the new line's width. The cursor cell is highlighted with `cursor_style` (default: reverse video).

### Extra TextArea cursor ops

```gleam
ta.move_to_line_start(state)
ta.move_to_line_end(state)
ta.delete_to_line_end(state)
ta.state_from_string("pre-filled\ncontent")
```

---

## Tree

Hierarchical list with expand/collapse nodes and keyboard navigation.

```gleam
import etui/widgets/tree

let t =
  tree.tree_new([
    tree.node("src", "src/", [
      tree.leaf("main", "main.gleam"),
      tree.leaf("lib",  "lib.gleam"),
    ]),
    tree.leaf("readme", "README.md"),
  ])
  |> tree.with_highlight_style(style.Style(...))

let state = tree.state_from_tree(t)   // first root selected

// Navigation
let state = tree.select_next(state, t)
let state = tree.select_prev(state, t)
let state = tree.toggle_selected(state, t)  // expand/collapse
let state = tree.expand("src", state)
let state = tree.collapse("src", state)

// Render
let buf = tree.render(buf, area, t, state)

// Read selection
tree.selected(state)    // Result(String, Nil), selected node ID
tree.is_expanded(state, "src")  // Bool
```

Use `tree.ascii_glyphs()` for ASCII-only terminals; default uses Unicode `▶`/`▼`.

### Per-node counts

Attach a right-aligned count to any node (unread emails, child totals, etc.):

```gleam
tree.node_with_count("inbox", "Inbox", 12, [
  tree.leaf_with_count("important", "Important", 3),
  tree.leaf("archive", "Archive"),
])

// Or attach after construction
tree.leaf("drafts", "Drafts") |> tree.with_count(2)
```

Rendered as:

```text
▼ Inbox                  12
    Important             3
    Archive
  Drafts                  2
```

---

## Paginator

Page indicator with dot (`● ○ ○ ○ ○`) or arabic (`2/5`) display modes. Tracks
the current page and slices a list to the current window.

```gleam
import etui/widgets/paginator

let p =
  paginator.paginator_new(5)
  |> paginator.with_page_size(10)
  |> paginator.with_style(paginator.Dots)

// Navigation
let p = paginator.next_page(p)
let p = paginator.prev_page(p)
let p = paginator.go_to(p, 3)

// Slice items for the current page
let visible = paginator.slice(all_items, p)

// Recompute total when the item list changes
let p = paginator.set_item_count(p, list.length(all_items))

paginator.render(buf, area, p)
```

---

## Help

Keyboard binding cheat sheet. Two layouts: `Short` (one line, separator
between bindings) and `Full` (key column + description column, one per row).

```gleam
import etui/widgets/help

let h =
  help.help_new([
    help.binding(["k", "up"], "move up"),
    help.binding(["j", "down"], "move down"),
    help.binding(["?"], "toggle help"),
    help.binding(["q", "ctrl+c"], "quit"),
  ])

// Toggle Short/Full on a key press
let h = case event {
  backend.KeyPress("?") -> help.toggle_mode(h)
  _ -> h
}

help.render(buf, area, h)
```

Customise: `with_separator`, `with_key_color`, `with_description_color`,
`with_bg`.

---

## Fieldset

Horizontal rule with an inline title. Acts as a lightweight section divider.

```gleam
import etui/widgets/fieldset

let fs =
  fieldset.fieldset_new("Connections")
  |> fieldset.with_align(fieldset.AlignCenter)
  |> fieldset.with_line_char("═")

fieldset.render(buf, area, fs)
```

Rendered (center, area width 40):

```text
══════════════ Connections ════════════
```

Alignment: `AlignLeft` (default, with `with_pad` setting the leading rule
count), `AlignCenter`, `AlignRight`.

---

## MultiSelect

Toggle list. Cursor scrolls through items; your update handler calls
`toggle/2` to flip the cursor item.

```gleam
import etui/widgets/multi_select

let w =
  multi_select.multi_select_new(["Bash", "Gleam", "Erlang", "Rust"])
  |> multi_select.with_max(2)           // optional cap, 0 = unlimited

let state = multi_select.state_new()

let state = case event {
  backend.KeyPress("j")     -> multi_select.select_next(state, 4)
  backend.KeyPress("k")     -> multi_select.select_prev(state)
  backend.KeyPress(" ")     -> multi_select.toggle(state, w.max)
  backend.KeyPress("c")     -> multi_select.clear_selection(state)
  _ -> state
}

multi_select.render(buf, area, w, state)

// Read selection
multi_select.selected_indices(state)            // List(Int)
multi_select.selected_values(w.items, state)    // List(String)
multi_select.is_selected(state, 2)              // Bool
```
