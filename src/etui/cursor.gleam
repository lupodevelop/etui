/// Terminal cursor shapes and movement helpers.
import gleam/int

// ─────────────────────────────────────────────────────────────────
// Cursor shape

pub type CursorShape {
  BlockBlink
  Block
  UnderlineBlink
  Underline
  BarBlink
  Bar
}

/// ANSI sequence to change the cursor shape.
pub fn set_shape(shape: CursorShape) -> String {
  case shape {
    BlockBlink -> "\u{001B}[1 q"
    Block -> "\u{001B}[2 q"
    UnderlineBlink -> "\u{001B}[3 q"
    Underline -> "\u{001B}[4 q"
    BarBlink -> "\u{001B}[5 q"
    Bar -> "\u{001B}[6 q"
  }
}

// ─────────────────────────────────────────────────────────────────
// Visibility

pub fn show() -> String {
  "\u{001B}[?25h"
}

pub fn hide() -> String {
  "\u{001B}[?25l"
}

// ─────────────────────────────────────────────────────────────────
// Movement

/// Move cursor to 1-based (row, col) position.
pub fn move_to(row: Int, col: Int) -> String {
  "\u{001B}[" <> int.to_string(row) <> ";" <> int.to_string(col) <> "H"
}

/// Save cursor position.
pub fn save() -> String {
  "\u{001B}[s"
}

/// Restore cursor position.
pub fn restore() -> String {
  "\u{001B}[u"
}
