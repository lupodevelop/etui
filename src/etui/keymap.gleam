/// Named key bindings with help text generation.
///
/// Register named commands with their key trigger and description.
/// Use `lookup` to dispatch events, `help_lines` to build a help overlay.
///
/// ```gleam
/// import etui/keymap
/// import etui/keys
///
/// type Action { Quit | Save | OpenFile }
///
/// let km =
///   keymap.keymap_new()
///   |> keymap.bind("ctrl+q", Quit, "Quit")
///   |> keymap.bind("ctrl+s", Save, "Save")
///   |> keymap.bind("ctrl+o", OpenFile, "Open file")
///
/// // In on_event:
/// case keymap.lookup(km, raw_key_string) {
///   Ok(Quit) -> ...
///   Ok(Save) -> ...
///   _ -> state
/// }
///
/// // Render a help overlay:
/// let help_buf = keymap.render_help(buf, area, km, style.default_style())
/// ```
import etui/buffer
import etui/geometry
import etui/style
import etui/text
import gleam/list
import gleam/string

// ─────────────────────────────────────────────────────────────────
// Types

/// A single key binding: key → action + description.
pub type Binding(action) {
  Binding(key: String, action: action, description: String)
}

/// Ordered list of key bindings.
pub type Keymap(action) {
  Keymap(bindings: List(Binding(action)))
}

// ─────────────────────────────────────────────────────────────────
// Constructor

/// Empty keymap.
pub fn keymap_new() -> Keymap(action) {
  Keymap(bindings: [])
}

/// Add a binding to the end of the keymap.
/// The first matching binding wins on `lookup`.
pub fn bind(
  km: Keymap(action),
  key: String,
  action: action,
  description: String,
) -> Keymap(action) {
  Keymap(
    bindings: list.append(km.bindings, [Binding(key, action, description)]),
  )
}

/// Remove all bindings for a given key.
pub fn unbind(km: Keymap(action), key: String) -> Keymap(action) {
  Keymap(bindings: list.filter(km.bindings, fn(b) { b.key != key }))
}

/// Merge `other` into `km`. Bindings from `other` are appended.
pub fn merge(km: Keymap(a), other: Keymap(a)) -> Keymap(a) {
  Keymap(bindings: list.append(km.bindings, other.bindings))
}

// ─────────────────────────────────────────────────────────────────
// Lookup

/// Find the action bound to `key`. Returns `Error(Nil)` if not found.
pub fn lookup(km: Keymap(action), key: String) -> Result(action, Nil) {
  case list.find(km.bindings, fn(b) { b.key == key }) {
    Ok(b) -> Ok(b.action)
    Error(_) -> Error(Nil)
  }
}

/// All bindings as `#(key, description)` pairs, in registration order.
pub fn help_lines(km: Keymap(action)) -> List(#(String, String)) {
  list.map(km.bindings, fn(b) { #(b.key, b.description) })
}

/// All bindings as `#(key, action)` pairs.
pub fn all_bindings(km: Keymap(action)) -> List(#(String, action)) {
  list.map(km.bindings, fn(b) { #(b.key, b.action) })
}

// ─────────────────────────────────────────────────────────────────
// Rendering

/// Render a help table into `area`.
/// Each row shows `  key_col  description`. `key_col_width` is the
/// minimum column width for keys (auto-computed if 0).
/// Returns the buffer with the help overlay drawn.
pub fn render_help(
  buf: buffer.Buffer,
  area: geometry.Rect,
  km: Keymap(action),
  st: style.Style,
) -> buffer.Buffer {
  let lines = help_lines(km)
  let key_w = case
    list.fold(lines, 0, fn(acc, pair) {
      let #(k, _) = pair
      case text.cell_width(k) > acc {
        True -> text.cell_width(k)
        False -> acc
      }
    })
  {
    0 -> 6
    n -> n
  }
  render_help_rows(buf, area, lines, key_w, st, 0)
}

fn render_help_rows(
  buf: buffer.Buffer,
  area: geometry.Rect,
  lines: List(#(String, String)),
  key_w: Int,
  st: style.Style,
  row: Int,
) -> buffer.Buffer {
  case row >= area.size.height || list.is_empty(lines) {
    True -> buf
    False ->
      case lines {
        [] -> buf
        [#(key, desc), ..rest] -> {
          let padded_key = text.pad_right(key, key_w)
          let row_text =
            padded_key
            <> "  "
            <> text.truncate(desc, area.size.width - key_w - 2, "")
          let trimmed = text.truncate(row_text, area.size.width, "")
          let padded = text.pad_right(trimmed, area.size.width)
          let buf2 =
            buffer.set_string(
              buf,
              geometry.Position(x: area.position.x, y: area.position.y + row),
              padded,
              st.fg,
              st.bg,
              st.modifier,
            )
          render_help_rows(buf2, area, rest, key_w, st, row + 1)
        }
      }
  }
}

// ─────────────────────────────────────────────────────────────────
// Filtering

/// Keep only bindings whose description contains `query` (case-insensitive).
/// Useful for a live-filter command palette.
pub fn filter(km: Keymap(action), query: String) -> Keymap(action) {
  case query {
    "" -> km
    q -> {
      let lower_q = string.lowercase(q)
      Keymap(
        bindings: list.filter(km.bindings, fn(b) {
          string.contains(string.lowercase(b.description), lower_q)
          || string.contains(string.lowercase(b.key), lower_q)
        }),
      )
    }
  }
}
