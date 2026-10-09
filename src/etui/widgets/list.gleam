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
    highlight_style: style.new(style.Default, style.Default, style.reverse()),
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
    highlight_style: style.new(style.Default, style.Default, style.reverse()),
    blink_period: 0,
  )
}

/// Colors of unselected rows.
pub fn with_colors(
  l: ListWidget,
  fg: style.Color,
  bg: style.Color,
) -> ListWidget {
  ListWidget(..l, fg: fg, bg: bg)
}

/// Style of the selected row (default: reverse video).
pub fn with_highlight_style(l: ListWidget, s: style.Style) -> ListWidget {
  ListWidget(..l, highlight_style: s)
}

/// Take only fg/bg from a Style.
pub fn with_style(l: ListWidget, s: style.Style) -> ListWidget {
  ListWidget(..l, fg: s.fg, bg: s.bg)
}

/// Blink period in frames. 0 = steady (no blink). Use with `render_animated`.
pub fn with_blink(l: ListWidget, period: Int) -> ListWidget {
  ListWidget(..l, blink_period: period)
}

// ─────────────────────────────────────────────────────────────────
// State constructors and navigation

/// Selection at the first item, viewport at the top.
pub fn state_new() -> ListState {
  ListState(selected: 0, offset: 0)
}

/// Jump the selection to `idx`. Negative indices clamp to 0.
pub fn select(state: ListState, idx: Int) -> ListState {
  ListState(..state, selected: int.max(0, idx))
}

/// Move the selection down one, stopping at the last item.
pub fn select_next(state: ListState, item_count: Int) -> ListState {
  let max_idx = int.max(0, item_count - 1)
  ListState(..state, selected: int.min(max_idx, state.selected + 1))
}

/// Move the selection up one, stopping at the first item.
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

/// Render the list with no selection (e.g. for a static table of contents).
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

/// Render the list, scrolling to keep the selection in view.
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

/// Like `render_stateful`, but the highlight blinks on `blink_period` frames.
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
          style.new(row_fg, row_bg, row_mod),
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
              style.new(row_fg, row_bg, row_mod),
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
      let new_fg = case sp.style.fg {
        style.Default -> hl.fg
        _ -> sp.style.fg
      }
      let new_bg = case sp.style.bg {
        style.Default -> hl.bg
        _ -> sp.style.bg
      }
      let new_mod = case style.modifier_equal(sp.style.modifier, style.none()) {
        True -> hl.modifier
        False -> sp.style.modifier
      }
      span.Span(..sp, style: style.new(new_fg, new_bg, new_mod))
    }),
  )
}

// ─────────────────────────────────────────────────────────────────
// Scroll helpers

/// Effective scroll offset for a viewport of `height` rows.
pub fn effective_offset(state: ListState, height: Int) -> Int {
  scroll_offset(state.selected, state.offset, height)
}

/// The state this list settles on once it knows it has `height` rows.
///
/// A list cannot work out its scroll offset until it knows how tall its area
/// is, and that is decided by the layout, not by the model. Call this with the
/// height you are about to render into and keep the result:
///
/// ```gleam
/// let inner = block.inner(area, blk)
/// let listed = list.settle(model.list, inner.size.height)
/// let buf = list.render_stateful(buf, inner, widget, listed)
/// // store `listed` back in the model
/// ```
///
/// Rendering without doing this still draws the right rows, because
/// `render_stateful` works the offset out for itself. What it costs is that
/// the offset never persists, so the viewport slides one row with every step
/// instead of holding still until the selection leaves it.
pub fn settle(state: ListState, height: Int) -> ListState {
  ListState(..state, offset: effective_offset(state, height))
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
