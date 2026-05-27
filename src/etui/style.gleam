/// Terminal style: colors and text modifiers.
/// Supports 16-color (ANSI), 256-color, and RGB (true color).
/// Modifier is a bitfield: modifiers can be freely combined via `add`/`remove`.
import gleam/int
import gleam/string

/// Terminal color. `Default` defers to the terminal theme.
/// `Indexed(n)` covers the whole 256-color space: 0 to 15 are the themeable
/// ANSI colors, 16 to 255 the extended palette (the 6x6x6 cube and the
/// grayscale ramp).
/// `Rgb(r, g, b)` uses 24-bit true color and needs a truecolor terminal.
pub type Color {
  Default
  Indexed(Int)
  Rgb(Int, Int, Int)
}

/// Opaque bitfield for text modifiers. Use constants + `add`/`remove`/`has`.
pub opaque type Modifier {
  Modifier(bits: Int)
}

// ─────────────────────────────────────────────────────────────────
// Modifier constants (bit values)

/// No modifiers active.
pub fn none() -> Modifier {
  Modifier(0)
}

/// Bold / increased intensity.
pub fn bold() -> Modifier {
  Modifier(1)
}

/// Dim / decreased intensity.
pub fn dim() -> Modifier {
  Modifier(2)
}

/// Italic text.
pub fn italic() -> Modifier {
  Modifier(4)
}

/// Underline.
pub fn underline() -> Modifier {
  Modifier(8)
}

/// Blinking text (terminal support varies).
pub fn blink() -> Modifier {
  Modifier(16)
}

/// Swap foreground and background colors.
pub fn reverse() -> Modifier {
  Modifier(32)
}

/// Strikethrough.
pub fn strikethrough() -> Modifier {
  Modifier(64)
}

// ─────────────────────────────────────────────────────────────────
// Modifier operations

/// Combine two modifiers (bitwise OR).
pub fn add(a: Modifier, b: Modifier) -> Modifier {
  Modifier(int.bitwise_or(a.bits, b.bits))
}

/// Remove modifier bits from `a` that are set in `b`.
pub fn remove(a: Modifier, b: Modifier) -> Modifier {
  Modifier(int.bitwise_and(a.bits, int.bitwise_not(b.bits)))
}

/// Check if `flag` bits are set in `m`.
pub fn has(m: Modifier, flag: Modifier) -> Bool {
  int.bitwise_and(m.bits, flag.bits) != 0
}

/// True when no modifier bits are set.
pub fn is_none(m: Modifier) -> Bool {
  m.bits == 0
}

/// Structural equality for modifiers.
pub fn modifier_equal(a: Modifier, b: Modifier) -> Bool {
  a.bits == b.bits
}

// ─────────────────────────────────────────────────────────────────
// Composite style

/// Combined foreground color, background color, and text modifiers.
pub type Style {
  Style(fg: Color, bg: Color, modifier: Modifier)
}

/// Default style: terminal colors, no modifiers.
pub fn default_style() -> Style {
  Style(fg: Default, bg: Default, modifier: none())
}

/// Set foreground color on a style.
pub fn with_fg(s: Style, fg: Color) -> Style {
  Style(..s, fg: fg)
}

/// Set background color on a style.
pub fn with_bg(s: Style, bg: Color) -> Style {
  Style(..s, bg: bg)
}

/// Set modifier on a style.
pub fn with_modifier(s: Style, m: Modifier) -> Style {
  Style(..s, modifier: m)
}

/// Default colors with bold modifier.
pub fn bold_style() -> Style {
  Style(fg: Default, bg: Default, modifier: bold())
}

/// Default colors with reverse modifier (swap fg/bg).
pub fn reversed() -> Style {
  Style(fg: Default, bg: Default, modifier: reverse())
}

/// Default colors with italic modifier.
pub fn italic_style() -> Style {
  Style(fg: Default, bg: Default, modifier: italic())
}

/// Default colors with dim modifier.
pub fn dim_style() -> Style {
  Style(fg: Default, bg: Default, modifier: dim())
}

/// Default colors with underline modifier.
pub fn underline_style() -> Style {
  Style(fg: Default, bg: Default, modifier: underline())
}

/// Add a modifier to a `Style` (bitwise OR).
pub fn add_modifier(s: Style, m: Modifier) -> Style {
  Style(..s, modifier: add(s.modifier, m))
}

/// Remove modifier bits from a `Style`.
pub fn remove_modifier(s: Style, m: Modifier) -> Style {
  Style(..s, modifier: remove(s.modifier, m))
}

/// Parse an RGB color from a hex string (`"#RRGGBB"` or `"RRGGBB"`).
/// Returns `Error(Nil)` for malformed input.
///
/// ```gleam
/// style.color_from_hex("#1e1e2e")  // Ok(Rgb(30, 30, 46))
/// style.color_from_hex("ff5555")   // Ok(Rgb(255, 85, 85))
/// ```
pub fn color_from_hex(hex: String) -> Result(Color, Nil) {
  let s = case string.starts_with(hex, "#") {
    True -> string.drop_start(hex, 1)
    False -> hex
  }
  case string.length(s) == 6 {
    False -> Error(Nil)
    True -> {
      let chars = string.to_graphemes(s)
      case chars {
        [r1, r2, g1, g2, b1, b2] ->
          case hex_pair(r1, r2), hex_pair(g1, g2), hex_pair(b1, b2) {
            Ok(r), Ok(g), Ok(b) -> Ok(Rgb(r, g, b))
            _, _, _ -> Error(Nil)
          }
        _ -> Error(Nil)
      }
    }
  }
}

fn hex_pair(hi: String, lo: String) -> Result(Int, Nil) {
  case hex_digit(hi), hex_digit(lo) {
    Ok(h), Ok(l) -> Ok(h * 16 + l)
    _, _ -> Error(Nil)
  }
}

fn hex_digit(c: String) -> Result(Int, Nil) {
  case c {
    "0" -> Ok(0)
    "1" -> Ok(1)
    "2" -> Ok(2)
    "3" -> Ok(3)
    "4" -> Ok(4)
    "5" -> Ok(5)
    "6" -> Ok(6)
    "7" -> Ok(7)
    "8" -> Ok(8)
    "9" -> Ok(9)
    "a" | "A" -> Ok(10)
    "b" | "B" -> Ok(11)
    "c" | "C" -> Ok(12)
    "d" | "D" -> Ok(13)
    "e" | "E" -> Ok(14)
    "f" | "F" -> Ok(15)
    _ -> Error(Nil)
  }
}

/// Apply `over` on top of `base`. Default fg/bg fall back to `base`.
/// Modifier: if `over` has any bits set, they are OR'd into `base`;
/// `none()` in `over` means "no modifier override" (keep base).
pub fn patch(base: Style, over: Style) -> Style {
  let fg = case over.fg {
    Default -> base.fg
    c -> c
  }
  let bg = case over.bg {
    Default -> base.bg
    c -> c
  }
  let modifier = case is_none(over.modifier) {
    True -> base.modifier
    False -> add(base.modifier, over.modifier)
  }
  Style(fg: fg, bg: bg, modifier: modifier)
}

// ─────────────────────────────────────────────────────────────────
// ANSI sequence generation

/// Foreground color escape sequence.
pub fn ansi_fg(color: Color) -> String {
  case color {
    Default -> ""
    Indexed(0) -> "\u{001B}[30m"
    Indexed(1) -> "\u{001B}[31m"
    Indexed(2) -> "\u{001B}[32m"
    Indexed(3) -> "\u{001B}[33m"
    Indexed(4) -> "\u{001B}[34m"
    Indexed(5) -> "\u{001B}[35m"
    Indexed(6) -> "\u{001B}[36m"
    Indexed(7) -> "\u{001B}[37m"
    Indexed(8) -> "\u{001B}[90m"
    Indexed(9) -> "\u{001B}[91m"
    Indexed(10) -> "\u{001B}[92m"
    Indexed(11) -> "\u{001B}[93m"
    Indexed(12) -> "\u{001B}[94m"
    Indexed(13) -> "\u{001B}[95m"
    Indexed(14) -> "\u{001B}[96m"
    Indexed(15) -> "\u{001B}[97m"
    Indexed(n) -> "\u{001B}[38;5;" <> int.to_string(n) <> "m"
    Rgb(r, g, b) ->
      "\u{001B}[38;2;"
      <> int.to_string(r)
      <> ";"
      <> int.to_string(g)
      <> ";"
      <> int.to_string(b)
      <> "m"
  }
}

/// Background color escape sequence.
pub fn ansi_bg(color: Color) -> String {
  case color {
    Default -> ""
    Indexed(0) -> "\u{001B}[40m"
    Indexed(1) -> "\u{001B}[41m"
    Indexed(2) -> "\u{001B}[42m"
    Indexed(3) -> "\u{001B}[43m"
    Indexed(4) -> "\u{001B}[44m"
    Indexed(5) -> "\u{001B}[45m"
    Indexed(6) -> "\u{001B}[46m"
    Indexed(7) -> "\u{001B}[47m"
    Indexed(8) -> "\u{001B}[100m"
    Indexed(9) -> "\u{001B}[101m"
    Indexed(10) -> "\u{001B}[102m"
    Indexed(11) -> "\u{001B}[103m"
    Indexed(12) -> "\u{001B}[104m"
    Indexed(13) -> "\u{001B}[105m"
    Indexed(14) -> "\u{001B}[106m"
    Indexed(15) -> "\u{001B}[107m"
    Indexed(n) -> "\u{001B}[48;5;" <> int.to_string(n) <> "m"
    Rgb(r, g, b) ->
      "\u{001B}[48;2;"
      <> int.to_string(r)
      <> ";"
      <> int.to_string(g)
      <> ";"
      <> int.to_string(b)
      <> "m"
  }
}

/// Text modifier escape sequence. Emits all active modifier bits.
pub fn ansi_modifier(m: Modifier) -> String {
  case is_none(m) {
    True -> ""
    False -> {
      let parts = []
      let parts = case has(m, bold()) {
        True -> ["1", ..parts]
        False -> parts
      }
      let parts = case has(m, dim()) {
        True -> ["2", ..parts]
        False -> parts
      }
      let parts = case has(m, italic()) {
        True -> ["3", ..parts]
        False -> parts
      }
      let parts = case has(m, underline()) {
        True -> ["4", ..parts]
        False -> parts
      }
      let parts = case has(m, blink()) {
        True -> ["5", ..parts]
        False -> parts
      }
      let parts = case has(m, reverse()) {
        True -> ["7", ..parts]
        False -> parts
      }
      let parts = case has(m, strikethrough()) {
        True -> ["9", ..parts]
        False -> parts
      }
      "\u{001B}[" <> string.join(parts, ";") <> "m"
    }
  }
}

/// Reset all styles.
pub fn ansi_reset() -> String {
  "\u{001B}[0m"
}
