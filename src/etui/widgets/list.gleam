import etui/anim
import etui/buffer
import etui/geometry
import etui/span
import etui/style
import etui/text
import gleam/int
import gleam/list as glist

// ─────────────────────────────────────────────────────────────────
// Types

/// Scrollable list of styled items with selection highlight.
pub type ListWidget {
  ListWidget(
    items: List(span.Line),
    fg: style.Color,
    bg: style.Color,
    highlight_style: style.Style,
    /// Blink period in frames (0 = no blink).
    blink_period: Int,
  )
}

/// Scroll and selection state for a list. Kept external so state persists across renders.
pub type ListState {
  ListState(selected: Int, offset: Int)
}

// ─────────────────────────────────────────────────────────────────
// Widget config constructors

/// New list from plain strings. Default colors, reverse-video selection.
pub fn list_new(items: List(String)) -> ListWidget {
  ListWidget(
    items: glist.map(items, span.line_plain),
    fg: style.Default,
    bg: style.Default,
    highlight_style: style.Style(
      fg: style.Default,
      bg: style.Default,
      modifier: style.reverse(),
    ),
    blink_period: 0,
  )
}

/// New list from styled `span.Line` items.
///
/// ```gleam
/// list.list_new_styled([
///   span.line_new([span.span_styled("ERROR", style.bold_style()), span.span_plain(" file")]),
///   span.line_plain("normal item"),
/// ])
/// ```
pub fn list_new_styled(items: List(span.Line)) -> ListWidget {
  ListWidget(
    items: items,
    fg: style.Default,
    bg: style.Default,
    highlight_style: style.Style(
      fg: style.Default,
      bg: style.Default,
      modifier: style.reverse(),
    ),
    blink_period: 0,
  )
}

pub fn with_colors(
  l: ListWidget,
  fg: style.Color,
  bg: style.Color,
) -> ListWidget {
  ListWidget(..l, fg: fg, bg: bg)
}

pub fn with_highlight_style(l: ListWidget, s: style.Style) -> ListWidget {
  ListWidget(..l, highlight_style: s)
}

pub fn with_style(l: ListWidget, s: style.Style) -> ListWidget {
  ListWidget(..l, fg: s.fg, bg: s.bg)
}

/// Blink period in frames. 0 = steady (no blink). Use with `render_animated`.
pub fn with_blink(l: ListWidget, period: Int) -> ListWidget {
  ListWidget(..l, blink_period: period)
}

// ─────────────────────────────────────────────────────────────────
// State constructors and navigation

pub fn state_new() -> ListState {
  ListState(selected: 0, offset: 0)
}

pub fn select(state: ListState, idx: Int) -> ListState {
  ListState(..state, selected: int.max(0, idx))
}

pub fn select_next(state: ListState, item_count: Int) -> ListState {
  let max_idx = int.max(0, item_count - 1)
  ListState(..state, selected: int.min(max_idx, state.selected + 1))
}

pub fn select_prev(state: ListState) -> ListState {
  ListState(..state, selected: int.max(0, state.selected - 1))
}

/// Clamp `selected` to `[0, item_count - 1]`.
/// Call after replacing the item list to avoid a stale selection index.
pub fn clamp_state(state: ListState, item_count: Int) -> ListState {
  let max = int.max(0, item_count - 1)
  ListState(..state, selected: int.min(state.selected, max))
}

// ─────────────────────────────────────────────────────────────────
// Rendering

pub fn render(
  buf: buffer.Buffer,
  area: geometry.Rect,
  l: ListWidget,
) -> buffer.Buffer {
  case area.size.height <= 0 {
    True -> buf
    False -> do_render(buf, area, l, -1, 0, 0)
  }
}

pub fn render_stateful(
  buf: buffer.Buffer,
  area: geometry.Rect,
  l: ListWidget,
  state: ListState,
) -> buffer.Buffer {
  case area.size.height <= 0 {
    True -> buf
    False -> {
      let offset = scroll_offset(state.selected, state.offset, area.size.height)
      do_render(buf, area, l, state.selected, offset, 0)
    }
  }
}

pub fn render_animated(
  buf: buffer.Buffer,
  area: geometry.Rect,
  l: ListWidget,
  state: ListState,
  frame: Int,
) -> buffer.Buffer {
  case area.size.height <= 0 {
    True -> buf
    False -> {
      let offset = scroll_offset(state.selected, state.offset, area.size.height)
      let show = anim.blink(frame, l.blink_period)
      let sel = case show {
        True -> state.selected
        False -> -1
      }
      do_render(buf, area, l, sel, offset, 0)
    }
  }
}

fn do_render(
  buf: buffer.Buffer,
  area: geometry.Rect,
  l: ListWidget,
  selected: Int,
  offset: Int,
  y_offset: Int,
) -> buffer.Buffer {
  case y_offset >= area.size.height {
    True -> buf
    False -> {
      let item_idx = offset + y_offset
      let y = area.position.y + y_offset
      let is_selected = item_idx == selected
      let #(row_fg, row_bg, row_mod) = case is_selected {
        True -> #(
          l.highlight_style.fg,
          l.highlight_style.bg,
          l.highlight_style.modifier,
        )
        False -> #(l.fg, l.bg, style.none())
      }
      // Draw background row first so unoccupied cells have correct color.
      let bg_row = text.pad_right("", area.size.width)
      let buf1 =
        buffer.set_string(
          buf,
          geometry.Position(x: area.position.x, y: y),
          bg_row,
          row_fg,
          row_bg,
          row_mod,
        )
      let buf2 = case get_item_at(l.items, item_idx) {
        Error(_) -> buf1
        Ok(line) -> {
          // Prefix: "▶ " when selected, "  " otherwise.
          let prefix = case is_selected {
            True -> "▶ "
            False -> "  "
          }
          let prefix_w = text.cell_width(prefix)
          let buf3 =
            buffer.set_string(
              buf1,
              geometry.Position(x: area.position.x, y: y),
              prefix,
              row_fg,
              row_bg,
              row_mod,
            )
          // Spans get their own colors; selected highlight comes from bg row.
          let effective_line = case is_selected {
            False -> line
            True -> apply_highlight_to_line(line, l.highlight_style)
          }
          span.render_line(
            buf3,
            geometry.Position(x: area.position.x + prefix_w, y: y),
            effective_line,
            area.size.width - prefix_w,
          )
        }
      }
      do_render(buf2, area, l, selected, offset, y_offset + 1)
    }
  }
}

// When a span uses Default fg/bg, substitute highlight colors so the row
// reads as fully highlighted without overriding intentionally-colored spans.
fn apply_highlight_to_line(line: span.Line, hl: style.Style) -> span.Line {
  span.line_new(
    glist.map(line.spans, fn(sp) {
      let new_fg = case sp.fg {
        style.Default -> hl.fg
        _ -> sp.fg
      }
      let new_bg = case sp.bg {
        style.Default -> hl.bg
        _ -> sp.bg
      }
      let new_mod = case style.modifier_equal(sp.modifier, style.none()) {
        True -> hl.modifier
        False -> sp.modifier
      }
      span.Span(..sp, fg: new_fg, bg: new_bg, modifier: new_mod)
    }),
  )
}

// ─────────────────────────────────────────────────────────────────
// Scroll helpers

pub fn effective_offset(state: ListState, height: Int) -> Int {
  scroll_offset(state.selected, state.offset, height)
}

fn scroll_offset(selected: Int, offset: Int, height: Int) -> Int {
  case selected < offset {
    True -> selected
    False ->
      case height <= 0 {
        True -> offset
        False ->
          case selected >= offset + height {
            True -> selected - height + 1
            False -> offset
          }
      }
  }
}

// ─────────────────────────────────────────────────────────────────
// Internal helpers

fn get_item_at(items: List(span.Line), idx: Int) -> Result(span.Line, Nil) {
  case idx {
    i if i < 0 -> Error(Nil)
    0 ->
      case items {
        [h, ..] -> Ok(h)
        [] -> Error(Nil)
      }
    _ -> get_item_at(glist.drop(items, 1), idx - 1)
  }
}
