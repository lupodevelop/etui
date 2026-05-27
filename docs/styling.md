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
let s = style.Style(
  fg: style.Rgb(255, 255, 255),
  bg: style.Indexed(4),
  modifier: style.add(style.bold(), style.italic()),
)
```

Most widgets accept style via `with_style(s)`.

## ANSI output

```gleam
style.ansi_fg(style.Rgb(255, 0, 0))    // "\e[38;2;255;0;0m"
style.ansi_fg(style.Indexed(1))        // "\e[31m"
style.ansi_fg(style.Indexed(200))      // "\e[38;5;200m"
style.ansi_bg(style.Indexed(4))        // "\e[44m"
style.ansi_reset()                      // "\e[0m"
```

## Styled spans

For mixed-style inline text, use `etui/span`:

```gleam
import etui/span

// Plain text span
let s1 = span.span_plain("normal text")

// Styled span
let s2 = span.span_styled("bold red", style.Style(
  fg: style.Indexed(1),
  bg: style.Default,
  modifier: style.bold(),
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
