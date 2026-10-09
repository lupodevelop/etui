/// ScrollView widget: render any content into a virtual canvas larger than the
/// visible area, then show a viewport into it.
///
/// Unlike the `list` or `table` widgets which handle scrolling internally,
/// `ScrollView` works with any widget. The inner widget renders into a buffer
/// sized to `virtual_width × virtual_height`; the scroll view then copies the
/// visible window into the target buffer.
///
/// Use the `scrollbar` widget alongside the scroll view for visual scroll
/// indicators.
///
/// ```gleam
/// let sv = scroll_view_new(200, 50)
/// let sv_state = state_new()
///
/// // Render a paragraph into the virtual canvas:
/// scroll_view.render(buf, area, sv, sv_state, fn(inner_buf, inner_area) {
///   paragraph.render(inner_buf, inner_area, para)
/// })
/// ```
import etui/buffer
import etui/geometry
import gleam/int

// ─────────────────────────────────────────────────────────────────
// Types

pub type ScrollView {
  ScrollView(virtual_width: Int, virtual_height: Int)
}

pub type ScrollViewState {
  ScrollViewState(scroll_x: Int, scroll_y: Int)
}

// ─────────────────────────────────────────────────────────────────
// Constructors

/// A virtual canvas of the given size. Dimensions are clamped to ≥ 1.
pub fn scroll_view_new(virtual_width: Int, virtual_height: Int) -> ScrollView {
  ScrollView(
    virtual_width: int.max(1, virtual_width),
    virtual_height: int.max(1, virtual_height),
  )
}

/// New scroll state at the origin. Every other stateful widget names its
/// constructor `state_new`, so this one does too.
pub fn state_new() -> ScrollViewState {
  ScrollViewState(scroll_x: 0, scroll_y: 0)
}

/// Former name of `state_new`.
pub fn sv_state_new() -> ScrollViewState {
  state_new()
}

/// Scroll to absolute coordinates; negatives clamp to 0.
pub fn scroll_to(_state: ScrollViewState, x: Int, y: Int) -> ScrollViewState {
  ScrollViewState(scroll_x: int.max(0, x), scroll_y: int.max(0, y))
}

/// Scroll down by `lines`.
pub fn scroll_down(state: ScrollViewState, lines: Int) -> ScrollViewState {
  ScrollViewState(..state, scroll_y: state.scroll_y + int.max(0, lines))
}

/// Scroll up by `lines`, stopping at the top.
pub fn scroll_up(state: ScrollViewState, lines: Int) -> ScrollViewState {
  ScrollViewState(..state, scroll_y: int.max(0, state.scroll_y - lines))
}

/// Scroll right by `cols`.
pub fn scroll_right(state: ScrollViewState, cols: Int) -> ScrollViewState {
  ScrollViewState(..state, scroll_x: state.scroll_x + int.max(0, cols))
}

/// Scroll left by `cols`, stopping at the left edge.
pub fn scroll_left(state: ScrollViewState, cols: Int) -> ScrollViewState {
  ScrollViewState(..state, scroll_x: int.max(0, state.scroll_x - cols))
}

/// Clamp scroll offsets so the viewport never goes past the virtual canvas.
pub fn clamp(
  state: ScrollViewState,
  sv: ScrollView,
  visible_w: Int,
  visible_h: Int,
) -> ScrollViewState {
  let max_x = int.max(0, sv.virtual_width - visible_w)
  let max_y = int.max(0, sv.virtual_height - visible_h)
  ScrollViewState(
    scroll_x: int.min(state.scroll_x, max_x),
    scroll_y: int.min(state.scroll_y, max_y),
  )
}

// ─────────────────────────────────────────────────────────────────
// Rendering

/// Render the scroll view.
///
/// `render_inner` is called with a virtual buffer sized to
/// `(sv.virtual_width × sv.virtual_height)`. The visible window at
/// `(state.scroll_x, state.scroll_y)` is then blitted into `buf` at `area`.
pub fn render(
  buf: buffer.Buffer,
  area: geometry.Rect,
  sv: ScrollView,
  state: ScrollViewState,
  render_inner: fn(buffer.Buffer, geometry.Rect) -> buffer.Buffer,
) -> buffer.Buffer {
  case area.size.width <= 0 || area.size.height <= 0 {
    True -> buf
    False -> {
      let virtual_area =
        geometry.rect_new(0, 0, sv.virtual_width, sv.virtual_height)
      let virtual_buf =
        buffer.buffer_new(virtual_area)
        |> render_inner(virtual_area)

      let window =
        geometry.rect_new(
          int.max(0, state.scroll_x),
          int.max(0, state.scroll_y),
          area.size.width,
          area.size.height,
        )
      buffer.blit(buf, virtual_buf, window, area.position)
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Scroll position helpers

/// How far into the virtual canvas is the viewport (0.0–1.0 × 100).
/// Returns an integer percentage (0–100). Useful for driving scrollbar widgets.
pub fn scroll_pct_y(
  state: ScrollViewState,
  sv: ScrollView,
  visible_h: Int,
) -> Int {
  let max_scroll = int.max(1, sv.virtual_height - visible_h)
  int.min(100, state.scroll_y * 100 / max_scroll)
}

/// Horizontal twin of `scroll_pct_y`.
pub fn scroll_pct_x(
  state: ScrollViewState,
  sv: ScrollView,
  visible_w: Int,
) -> Int {
  let max_scroll = int.max(1, sv.virtual_width - visible_w)
  int.min(100, state.scroll_x * 100 / max_scroll)
}
