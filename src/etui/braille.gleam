/// Braille pixel grid utilities. 2×4 dot grid per terminal cell using
/// Unicode braille block U+2800–U+28FF.
///
/// A "pixel" here is a sub-cell dot. (px / 2, py / 4) maps to terminal cell
/// coordinates; (px % 2, py % 4) maps to dot position within that cell.
///
/// The pixel dictionary maps cell coords → (bitmask, fg_color). Multiple
/// writes to the same cell OR their bitmasks; the last fg color wins.
import etui/buffer
import etui/geometry
import etui/style
import gleam/dict
import gleam/int
import gleam/string

pub type Pixels =
  dict.Dict(#(Int, Int), #(Int, style.Color))

/// Empty pixel grid.
pub fn new() -> Pixels {
  dict.new()
}

/// Set a pixel at terminal-cell (char_x, char_y), accumulating its bit into
/// the existing mask. Color overrides any prior color for that cell.
pub fn set_pixel(
  pixels: Pixels,
  char_x: Int,
  char_y: Int,
  bit: Int,
  fg: style.Color,
) -> Pixels {
  let key = #(char_x, char_y)
  let existing = case dict.get(pixels, key) {
    Ok(#(m, _)) -> m
    Error(_) -> 0
  }
  dict.insert(pixels, key, #(int.bitwise_or(existing, bit), fg))
}

/// Bitmask bit for the dot at (col, row) inside a 2×4 braille cell.
/// Layout (Unicode braille dot numbering):
///   col 0  col 1
///   row 0    1     8
///   row 1    2    16
///   row 2    4    32
///   row 3   64   128
pub fn bit(col: Int, row: Int) -> Int {
  case col, row {
    0, 0 -> 1
    0, 1 -> 2
    0, 2 -> 4
    0, 3 -> 64
    1, 0 -> 8
    1, 1 -> 16
    1, 2 -> 32
    1, 3 -> 128
    _, _ -> 0
  }
}

/// Write a single pixel at absolute braille-pixel coords (px, py) into the
/// pixel grid. Out-of-bounds coords (px < 0 or py < 0) are dropped.
pub fn put(pixels: Pixels, px: Int, py: Int, fg: style.Color) -> Pixels {
  case px < 0 || py < 0 {
    True -> pixels
    False -> set_pixel(pixels, px / 2, py / 4, bit(px % 2, py % 4), fg)
  }
}

/// Flush the pixel grid into a buffer at the given area's origin.
/// Each populated cell becomes one braille glyph.
pub fn flush(
  buf: buffer.Buffer,
  area: geometry.Rect,
  pixels: Pixels,
  bg: style.Color,
) -> buffer.Buffer {
  dict.fold(pixels, buf, fn(b, key, val) {
    let #(char_x, char_y) = key
    let #(mask, fg) = val
    let ch = case string.utf_codepoint(0x2800 + mask) {
      Ok(cp) -> string.from_utf_codepoints([cp])
      Error(_) -> "·"
    }
    buffer.set_string(
      b,
      geometry.Position(
        x: area.position.x + char_x,
        y: area.position.y + char_y,
      ),
      ch,
      fg,
      bg,
      style.none(),
    )
  })
}
