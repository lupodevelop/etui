/// Tab bar widget: horizontal row of labelled tabs.
/// Active tab rendered with active_style; others with normal fg/bg.
import etui/buffer
import etui/geometry
import etui/style
import etui/text
import gleam/int
import gleam/list

// ─────────────────────────────────────────────────────────────────
// Types

pub type Tabs {
  Tabs(
    labels: List(String),
    /// 0-based index of the active tab.
    active: Int,
    fg: style.Color,
    bg: style.Color,
    active_style: style.Style,
    /// String rendered between tabs.
    divider: String,
    /// Padding spaces inside each tab label.
    padding: Int,
  )
}

// ─────────────────────────────────────────────────────────────────
// Constructors

pub fn tabs_new(labels: List(String)) -> Tabs {
  Tabs(
    labels: labels,
    active: 0,
    fg: style.Default,
    bg: style.Default,
    active_style: style.Style(
      fg: style.Default,
      bg: style.Default,
      modifier: style.add(style.bold(), style.reverse()),
    ),
    divider: "│",
    padding: 1,
  )
}

pub fn with_active(t: Tabs, idx: Int) -> Tabs {
  Tabs(..t, active: int.max(0, idx))
}

pub fn with_active_style(t: Tabs, s: style.Style) -> Tabs {
  Tabs(..t, active_style: s)
}

pub fn with_divider(t: Tabs, div: String) -> Tabs {
  Tabs(..t, divider: div)
}

pub fn with_padding(t: Tabs, p: Int) -> Tabs {
  Tabs(..t, padding: int.max(0, p))
}

pub fn with_colors(t: Tabs, fg: style.Color, bg: style.Color) -> Tabs {
  Tabs(..t, fg: fg, bg: bg)
}

// Tab navigation helpers

pub fn next_tab(t: Tabs) -> Tabs {
  let n = list.length(t.labels)
  Tabs(..t, active: { t.active + 1 } % int.max(1, n))
}

pub fn prev_tab(t: Tabs) -> Tabs {
  let n = int.max(1, list.length(t.labels))
  Tabs(..t, active: { t.active - 1 + n } % n)
}

// ─────────────────────────────────────────────────────────────────
// Rendering

/// Render the tab bar into the first row of `area`.
pub fn render(
  buf: buffer.Buffer,
  area: geometry.Rect,
  t: Tabs,
) -> buffer.Buffer {
  case area.size.height <= 0 || area.size.width <= 0 {
    True -> buf
    False -> render_tabs(buf, area, t.labels, 0, area.position.x, t)
  }
}

fn render_tabs(
  buf: buffer.Buffer,
  area: geometry.Rect,
  labels: List(String),
  idx: Int,
  x: Int,
  t: Tabs,
) -> buffer.Buffer {
  case labels {
    [] -> buf
    [label, ..rest] -> {
      let pad = make_spaces(t.padding)
      let content = pad <> label <> pad
      let is_active = idx == t.active
      let #(fg, bg, modifier) = case is_active {
        True -> #(t.active_style.fg, t.active_style.bg, t.active_style.modifier)
        False -> #(t.fg, t.bg, style.none())
      }
      let avail = area.position.x + area.size.width - x
      let shown = text.truncate(content, avail, "")
      let buf2 =
        buffer.set_string(
          buf,
          geometry.Position(x: x, y: area.position.y),
          shown,
          fg,
          bg,
          modifier,
        )
      let next_x = x + string_length(content)
      case rest {
        [] -> buf2
        _ -> {
          let div_avail = area.position.x + area.size.width - next_x
          case div_avail <= 0 {
            True -> buf2
            False -> {
              let buf3 =
                buffer.set_string(
                  buf2,
                  geometry.Position(x: next_x, y: area.position.y),
                  t.divider,
                  t.fg,
                  t.bg,
                  style.none(),
                )
              render_tabs(
                buf3,
                area,
                rest,
                idx + 1,
                next_x + string_length(t.divider),
                t,
              )
            }
          }
        }
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Helpers

fn make_spaces(n: Int) -> String {
  case n <= 0 {
    True -> ""
    False -> " " <> make_spaces(n - 1)
  }
}

fn string_length(s: String) -> Int {
  text.cell_width(s)
}
