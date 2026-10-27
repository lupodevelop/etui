# Styling

## Colors

```gleam
import etui/style

style.Default             // inherits terminal default
style.Indexed(0)          // ANSI color 0 (black), 16-color palette
style.Indexed(200)        // 256-color extended palette (16–255)
style.Rgb(255, 128, 0)    // 24-bit true color
```

### 16-color palette (Indexed 0–15)

| Index | Name | Index | Name |
| --- | --- | --- | --- |
| 0 | Black | 8 | Bright Black |
| 1 | Red | 9 | Bright Red |
| 2 | Green | 10 | Bright Green |
| 3 | Yellow | 11 | Bright Yellow |
| 4 | Blue | 12 | Bright Blue |
| 5 | Magenta | 13 | Bright Magenta |
| 6 | Cyan | 14 | Bright Cyan |
| 7 | White | 15 | Bright White |

### 256-color extended palette (Indexed 16–255)

- 16–231: 6×6×6 color cube
- 232–255: grayscale ramp (dark to light)

## Modifiers

```gleam
style.bold()
style.italic()
style.underline()
style.reverse()         // swap fg/bg
style.dim()
style.blink()
style.strikethrough()

// Combine
let m = style.add(style.bold(), style.underline())

// Remove
let m2 = style.remove(m, style.underline())

// Check
style.has(m, style.bold())  // True
```

## Style record

```gleam
let s = style.new(
  style.Rgb(255, 255, 255),
  style.Indexed(4),
  style.add(style.bold(), style.italic()),
)
```

`style.new` fills in the two fields a call site rarely sets: `sub_modifier`
(empty) and `underline_color` (`Default`, so the underline takes the text
colour). Set them with `style.remove_modifier` and `style.with_underline_color`.

Most widgets accept style via `with_style(s)`.

## Underline colour

The underline can be a different colour from the text under it, which is what
a spell checker or a diagnostic squiggle wants:

```gleam
let squiggle =
  style.underline_style()
  |> style.with_underline_color(style.Rgb(220, 60, 60))
```

On a span, where a single marked word usually lives:

```gleam
span.span_styled("recieve", style.underline_style())
|> span.span_underline_color(style.Rgb(220, 60, 60))
```

This emits SGR 58, colon-separated. Terminals that implement it (kitty, VTE,
WezTerm, iTerm2) draw the underline in that colour; the rest ignore the
sequence and draw the underline in the foreground colour, as before 2.0.

The colons are what makes ignoring it safe. Written with semicolons,
`ESC[58;5;9m` is three ordinary parameters to a terminal that does not know
58 — unknown, then 5, then 9 — so a red underline came out as blinking
struck-through text, and a green one (`58;5;2`) as blinking dim text. After a
colon the values belong to the 58, so the whole attribute is skipped together.

## ANSI output

```gleam
style.ansi_fg(style.Rgb(255, 0, 0))    // "\e[38;2;255;0;0m"
style.ansi_fg(style.Indexed(1))        // "\e[31m"
style.ansi_fg(style.Indexed(200))      // "\e[38;5;200m"
style.ansi_bg(style.Indexed(4))        // "\e[44m"
style.ansi_underline_color(style.Indexed(2))  // "\e[58:5:2m"
style.ansi_underline_color(style.Rgb(220, 60, 60))  // "\e[58:2::220:60:60m"
style.ansi_reset()                      // "\e[0m"
```

## Styled spans

For mixed-style inline text, use `etui/span`:

```gleam
import etui/span

// Plain text span
let s1 = span.span_plain("normal text")

// Styled span
let s2 = span.span_styled("bold red", style.new(
  style.Indexed(1),
  style.Default,
  style.bold(),
))

// Assemble a line
let line = span.line_new([s1, s2])

// Measure total cell width
span.line_width(line)

// Render to buffer at position
span.render_line(buf, pos, line, max_width)
```

`span.Line` is used by `statusbar`, `list` (item spans), and any widget that needs mixed-style text on one row.

## Block styling

```gleam
import etui/widgets/block

block.block_new()
|> block.with_style(style.Indexed(7), style.Indexed(0))  // fg, bg
|> block.with_bg_fill   // fill inner area with bg color
```

`with_bg_fill` paints every cell inside the border with the block's background color. Useful for popup backgrounds and highlighted panels.

## Emoji presentation and cell width

Text measurement, wrapping and buffer writes share the same cell-width policy.
For Unicode 16.0 emoji variation sequences, VS16 (`U+FE0F`) requests two cells:
`☺` is one cell, while `☺️` is two. VS15 (`U+FE0E`) requests one cell for
supported bases below U+1F000, so `☕︎` is one cell. Supplementary emoji retain
their base width with VS15. A selector only affects a supported base immediately
before it; it does not narrow CJK characters or widen arbitrary letters.

The Erlang and JavaScript backends preserve the complete grapheme in the buffer,
including ASCII keycaps such as `1️⃣`. A two-cell grapheme is omitted when only
one cell remains in the row. Actual glyph appearance and width can still vary
with terminal and font.

Standalone clusters measured as zero cells (such as a leading combining mark,
ZWSP or a lone variation selector) are ignored by buffer writes and bulk fills.
They neither replace an existing cell nor advance the cursor. Marks attached
to a visible base remain in its cell, including combining tails after ZWJ that
OTP may return separately.
