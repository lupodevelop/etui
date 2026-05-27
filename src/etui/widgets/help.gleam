/// Keyboard shortcut help view.
/// Two modes:
/// - `Short`: one line, "k1/k2 desc • k3 desc • ..."
/// - `Full`: two columns, one binding per row.
import etui/buffer
import etui/geometry
import etui/style
import etui/text
import gleam/int
import gleam/list
import gleam/string

// ─────────────────────────────────────────────────────────────────
// Types

/// A single key binding. Multiple keys for the same action go in `keys`.
pub type Binding {
  Binding(keys: List(String), description: String)
}

pub type HelpMode {
  Short
  Full
}

pub type Help {
  Help(
    bindings: List(Binding),
    mode: HelpMode,
    separator: String,
    key_fg: style.Color,
    description_fg: style.Color,
    bg: style.Color,
  )
}

// ─────────────────────────────────────────────────────────────────
// Constructors

pub fn binding(keys: List(String), description: String) -> Binding {
  Binding(keys: keys, description: description)
}

pub fn help_new(bindings: List(Binding)) -> Help {
  Help(
    bindings: bindings,
    mode: Short,
    separator: " • ",
    key_fg: style.Default,
    description_fg: style.Indexed(8),
    bg: style.Default,
  )
}

pub fn with_mode(h: Help, mode: HelpMode) -> Help {
  Help(..h, mode: mode)
}

pub fn toggle_mode(h: Help) -> Help {
  case h.mode {
    Short -> Help(..h, mode: Full)
    Full -> Help(..h, mode: Short)
  }
}

pub fn with_separator(h: Help, sep: String) -> Help {
  Help(..h, separator: sep)
}

pub fn with_key_color(h: Help, fg: style.Color) -> Help {
  Help(..h, key_fg: fg)
}

pub fn with_description_color(h: Help, fg: style.Color) -> Help {
  Help(..h, description_fg: fg)
}

pub fn with_bg(h: Help, bg: style.Color) -> Help {
  Help(..h, bg: bg)
}

// ─────────────────────────────────────────────────────────────────
// Rendering

pub fn render(
  buf: buffer.Buffer,
  area: geometry.Rect,
  h: Help,
) -> buffer.Buffer {
  case area.size.width <= 0 || area.size.height <= 0 {
    True -> buf
    False ->
      case h.mode {
        Short -> render_short(buf, area, h)
        Full -> render_full(buf, area, h)
      }
  }
}

fn render_short(
  buf: buffer.Buffer,
  area: geometry.Rect,
  h: Help,
) -> buffer.Buffer {
  let txt =
    h.bindings
    |> list.map(fn(b) { string.join(b.keys, "/") <> " " <> b.description })
    |> string.join(h.separator)
  let line = text.truncate(txt, area.size.width, "")
  let padded = text.pad_right(line, area.size.width)
  buffer.set_string(
    buf,
    area.position,
    padded,
    h.description_fg,
    h.bg,
    style.none(),
  )
}

fn render_full(
  buf: buffer.Buffer,
  area: geometry.Rect,
  h: Help,
) -> buffer.Buffer {
  let max_key_w =
    list.fold(h.bindings, 0, fn(acc, b) {
      int.max(acc, text.cell_width(string.join(b.keys, "/")))
    })
  let key_col = int.min(max_key_w, int.max(0, area.size.width / 3))
  let desc_col = int.max(0, area.size.width - key_col - 1)
  render_full_rows(buf, area, h, h.bindings, 0, key_col, desc_col)
}

fn render_full_rows(
  buf: buffer.Buffer,
  area: geometry.Rect,
  h: Help,
  bindings: List(Binding),
  row: Int,
  key_col: Int,
  desc_col: Int,
) -> buffer.Buffer {
  case row >= area.size.height {
    True -> buf
    False ->
      case bindings {
        [] -> buf
        [b, ..rest] -> {
          let y = area.position.y + row
          let key_text = text.truncate(string.join(b.keys, "/"), key_col, "")
          let key_padded = text.pad_right(key_text, key_col)
          let buf2 =
            buffer.set_string(
              buf,
              geometry.Position(x: area.position.x, y: y),
              key_padded,
              h.key_fg,
              h.bg,
              style.bold(),
            )
          let desc_text = text.truncate(b.description, desc_col, "")
          let desc_padded = text.pad_right(desc_text, desc_col)
          let buf3 =
            buffer.set_string(
              buf2,
              geometry.Position(x: area.position.x + key_col + 1, y: y),
              desc_padded,
              h.description_fg,
              h.bg,
              style.none(),
            )
          render_full_rows(buf3, area, h, rest, row + 1, key_col, desc_col)
        }
      }
  }
}
