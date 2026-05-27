/// Page indicator with dots (●○○○○) or arabic (2/5) modes.
/// Tracks the current page and offers `slice/2` to pull the current page
/// from a flat list of items.
import etui/buffer
import etui/geometry
import etui/style
import etui/text
import gleam/int
import gleam/list
import gleam/string

// ─────────────────────────────────────────────────────────────────
// Types

pub type PaginatorStyle {
  Dots
  Arabic
}

pub type Paginator {
  Paginator(
    current: Int,
    total: Int,
    page_size: Int,
    style: PaginatorStyle,
    active_char: String,
    inactive_char: String,
    fg: style.Color,
    bg: style.Color,
  )
}

// ─────────────────────────────────────────────────────────────────
// Constructors

/// New paginator. `total` is clamped to at least 1. Starts on page 0.
pub fn paginator_new(total: Int) -> Paginator {
  Paginator(
    current: 0,
    total: int.max(1, total),
    page_size: 10,
    style: Dots,
    active_char: "●",
    inactive_char: "○",
    fg: style.Default,
    bg: style.Default,
  )
}

/// Items per page (used by `slice/2`). Default 10.
pub fn with_page_size(p: Paginator, n: Int) -> Paginator {
  Paginator(..p, page_size: int.max(1, n))
}

pub fn with_style(p: Paginator, st: PaginatorStyle) -> Paginator {
  Paginator(..p, style: st)
}

pub fn with_chars(p: Paginator, active: String, inactive: String) -> Paginator {
  Paginator(..p, active_char: active, inactive_char: inactive)
}

pub fn with_colors(
  p: Paginator,
  fg: style.Color,
  bg: style.Color,
) -> Paginator {
  Paginator(..p, fg: fg, bg: bg)
}

// ─────────────────────────────────────────────────────────────────
// Navigation

/// Next page, clamped to last.
pub fn next_page(p: Paginator) -> Paginator {
  Paginator(..p, current: int.min(p.current + 1, p.total - 1))
}

/// Previous page, clamped to 0.
pub fn prev_page(p: Paginator) -> Paginator {
  Paginator(..p, current: int.max(p.current - 1, 0))
}

/// Jump to a specific page, clamped to `[0, total - 1]`.
pub fn go_to(p: Paginator, page: Int) -> Paginator {
  Paginator(..p, current: int.clamp(page, 0, p.total - 1))
}

/// Recompute `total` from an item count and the current `page_size`.
/// Clamps `current` so it stays in range.
pub fn set_item_count(p: Paginator, items: Int) -> Paginator {
  let n = int.max(0, items)
  let total = int.max(1, { n + p.page_size - 1 } / p.page_size)
  let current = int.min(p.current, total - 1)
  Paginator(..p, total: total, current: current)
}

// ─────────────────────────────────────────────────────────────────
// Slice helper

/// Pull the items belonging to the current page.
pub fn slice(items: List(a), p: Paginator) -> List(a) {
  items
  |> list.drop(p.current * p.page_size)
  |> list.take(p.page_size)
}

// ─────────────────────────────────────────────────────────────────
// Rendering

pub fn render(
  buf: buffer.Buffer,
  area: geometry.Rect,
  p: Paginator,
) -> buffer.Buffer {
  case area.size.width <= 0 || area.size.height <= 0 {
    True -> buf
    False -> {
      let txt = case p.style {
        Dots -> dots_text(p)
        Arabic -> int.to_string(p.current + 1) <> "/" <> int.to_string(p.total)
      }
      let txt_w = text.cell_width(txt)
      let x_off = int.max(0, { area.size.width - txt_w } / 2)
      buffer.set_string(
        buf,
        geometry.Position(x: area.position.x + x_off, y: area.position.y),
        text.truncate(txt, area.size.width, ""),
        p.fg,
        p.bg,
        style.none(),
      )
    }
  }
}

fn dots_text(p: Paginator) -> String {
  list.repeat(Nil, p.total)
  |> list.index_map(fn(_, i) {
    case i == p.current {
      True -> p.active_char
      False -> p.inactive_char
    }
  })
  |> string.join(" ")
}
