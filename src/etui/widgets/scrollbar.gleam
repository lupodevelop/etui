/// Scrollbar widget: vertical or horizontal scroll indicator.
///
/// Renders a track with a thumb that reflects current scroll position.
/// Does not manage state, derive `offset` and `visible` from the widget
/// that owns the scroll (e.g. `ListState.offset` and area height).
///
/// Example:
/// ```gleam
/// scrollbar_new(total: 50, visible: 10, offset: 5)
/// |> scrollbar.render_vertical(buf, area)
/// ```
import etui/buffer
import etui/geometry
import etui/style
import gleam/int

// ─────────────────────────────────────────────────────────────────
// Types

/// Scrollbar configuration.
pub type Scrollbar {
  Scrollbar(
    /// Total number of items in the list.
    total: Int,
    /// Number of items visible at once (viewport height/width).
    visible: Int,
    /// Current scroll offset (index of first visible item).
    offset: Int,
    /// Track character (unfilled area).
    track_char: String,
    /// Thumb character (filled/active area).
    thumb_char: String,
    /// Arrow characters at start and end. `""` = no arrows.
    arrow_start: String,
    arrow_end: String,
    fg: style.Color,
    bg: style.Color,
    thumb_fg: style.Color,
    thumb_bg: style.Color,
  )
}

// ─────────────────────────────────────────────────────────────────
// Constructors

/// New scrollbar. `total` = total items, `visible` = viewport size,
/// `offset` = first visible item index.
pub fn scrollbar_new(total: Int, visible: Int, offset: Int) -> Scrollbar {
  Scrollbar(
    total: int.max(1, total),
    visible: int.max(1, visible),
    offset: int.max(0, offset),
    track_char: "░",
    thumb_char: "█",
    arrow_start: "▲",
    arrow_end: "▼",
    fg: style.Default,
    bg: style.Default,
    thumb_fg: style.Default,
    thumb_bg: style.Default,
  )
}

/// Override track and thumb characters.
pub fn with_chars(s: Scrollbar, track: String, thumb: String) -> Scrollbar {
  Scrollbar(..s, track_char: track, thumb_char: thumb)
}

/// Override arrow characters. Pass `""` to hide arrows.
pub fn with_arrows(s: Scrollbar, start: String, end_ch: String) -> Scrollbar {
  Scrollbar(..s, arrow_start: start, arrow_end: end_ch)
}

/// Set colors for the track.
pub fn with_colors(
  s: Scrollbar,
  fg: style.Color,
  bg: style.Color,
) -> Scrollbar {
  Scrollbar(..s, fg: fg, bg: bg)
}

/// Set colors for the thumb.
pub fn with_thumb_colors(
  s: Scrollbar,
  fg: style.Color,
  bg: style.Color,
) -> Scrollbar {
  Scrollbar(..s, thumb_fg: fg, thumb_bg: bg)
}

// ─────────────────────────────────────────────────────────────────
// Rendering

/// Render a vertical scrollbar into the first column of `area`.
/// Arrow characters (if non-empty) occupy the top and bottom cells;
/// the track fills the remaining height.
pub fn render_vertical(
  buf: buffer.Buffer,
  area: geometry.Rect,
  s: Scrollbar,
) -> buffer.Buffer {
  case area.size.height <= 0 || area.size.width <= 0 {
    True -> buf
    False -> {
      let has_start = s.arrow_start != ""
      let has_end = s.arrow_end != ""
      let arrow_top = case has_start {
        True -> 1
        False -> 0
      }
      let arrow_bot = case has_end {
        True -> 1
        False -> 0
      }
      let track_len = int.max(0, area.size.height - arrow_top - arrow_bot)
      let buf = case has_start {
        False -> buf
        True ->
          buffer.set_string(
            buf,
            geometry.Position(x: area.position.x, y: area.position.y),
            s.arrow_start,
            s.fg,
            s.bg,
            style.none(),
          )
      }
      let buf = case has_end {
        False -> buf
        True ->
          buffer.set_string(
            buf,
            geometry.Position(
              x: area.position.x,
              y: area.position.y + area.size.height - 1,
            ),
            s.arrow_end,
            s.fg,
            s.bg,
            style.none(),
          )
      }
      case track_len <= 0 {
        True -> buf
        False -> {
          let track_area =
            geometry.rect_new(
              area.position.x,
              area.position.y + arrow_top,
              area.size.width,
              track_len,
            )
          let #(thumb_start, thumb_size) = thumb_geometry(s, track_len)
          render_vertical_track(
            buf,
            track_area,
            s,
            track_len,
            thumb_start,
            thumb_size,
            0,
          )
        }
      }
    }
  }
}

/// Render a horizontal scrollbar into the first row of `area`.
/// Arrow characters (if non-empty) occupy the leftmost and rightmost cells;
/// the track fills the remaining width.
pub fn render_horizontal(
  buf: buffer.Buffer,
  area: geometry.Rect,
  s: Scrollbar,
) -> buffer.Buffer {
  case area.size.height <= 0 || area.size.width <= 0 {
    True -> buf
    False -> {
      let has_start = s.arrow_start != ""
      let has_end = s.arrow_end != ""
      let arrow_left = case has_start {
        True -> 1
        False -> 0
      }
      let arrow_right = case has_end {
        True -> 1
        False -> 0
      }
      let track_len = int.max(0, area.size.width - arrow_left - arrow_right)
      let buf = case has_start {
        False -> buf
        True ->
          buffer.set_string(
            buf,
            geometry.Position(x: area.position.x, y: area.position.y),
            s.arrow_start,
            s.fg,
            s.bg,
            style.none(),
          )
      }
      let buf = case has_end {
        False -> buf
        True ->
          buffer.set_string(
            buf,
            geometry.Position(
              x: area.position.x + area.size.width - 1,
              y: area.position.y,
            ),
            s.arrow_end,
            s.fg,
            s.bg,
            style.none(),
          )
      }
      case track_len <= 0 {
        True -> buf
        False -> {
          let track_area =
            geometry.rect_new(
              area.position.x + arrow_left,
              area.position.y,
              track_len,
              area.size.height,
            )
          let #(thumb_start, thumb_size) = thumb_geometry(s, track_len)
          render_horizontal_track(
            buf,
            track_area,
            s,
            track_len,
            thumb_start,
            thumb_size,
            0,
          )
        }
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Internal helpers

/// Compute thumb start position and size within a track of `track_len` cells.
fn thumb_geometry(s: Scrollbar, track_len: Int) -> #(Int, Int) {
  let total = int.max(1, s.total)
  let visible = int.clamp(s.visible, 1, total)
  let offset = int.clamp(s.offset, 0, total - visible)

  // Thumb size proportional to visible/total, minimum 1 cell.
  let thumb_size = int.max(1, track_len * visible / total)
  // Thumb position proportional to offset/(total-visible).
  let scrollable = total - visible
  let thumb_start = case scrollable {
    0 -> 0
    _ -> { track_len - thumb_size } * offset / scrollable
  }
  #(thumb_start, thumb_size)
}

fn render_vertical_track(
  buf: buffer.Buffer,
  area: geometry.Rect,
  s: Scrollbar,
  track_len: Int,
  thumb_start: Int,
  thumb_size: Int,
  i: Int,
) -> buffer.Buffer {
  case i >= track_len {
    True -> buf
    False -> {
      let pos = geometry.Position(x: area.position.x, y: area.position.y + i)
      let is_thumb = i >= thumb_start && i < thumb_start + thumb_size
      let #(ch, fg, bg) = case is_thumb {
        True -> #(s.thumb_char, s.thumb_fg, s.thumb_bg)
        False -> #(s.track_char, s.fg, s.bg)
      }
      let buf2 = buffer.set_string(buf, pos, ch, fg, bg, style.none())
      render_vertical_track(
        buf2,
        area,
        s,
        track_len,
        thumb_start,
        thumb_size,
        i + 1,
      )
    }
  }
}

fn render_horizontal_track(
  buf: buffer.Buffer,
  area: geometry.Rect,
  s: Scrollbar,
  track_len: Int,
  thumb_start: Int,
  thumb_size: Int,
  i: Int,
) -> buffer.Buffer {
  case i >= track_len {
    True -> buf
    False -> {
      let pos = geometry.Position(x: area.position.x + i, y: area.position.y)
      let is_thumb = i >= thumb_start && i < thumb_start + thumb_size
      let #(ch, fg, bg) = case is_thumb {
        True -> #(s.thumb_char, s.thumb_fg, s.thumb_bg)
        False -> #(s.track_char, s.fg, s.bg)
      }
      let buf2 = buffer.set_string(buf, pos, ch, fg, bg, style.none())
      render_horizontal_track(
        buf2,
        area,
        s,
        track_len,
        thumb_start,
        thumb_size,
        i + 1,
      )
    }
  }
}
