/// Centered modal popup overlay widget.
///
/// Computes a centered `Rect` and renders a block with an optional title.
/// Use `popup_area` to get the inner content rect, then render child widgets into it.
///
/// Example:
/// ```gleam
/// let pop = popup.popup_new(40, 10) |> popup.with_title("Confirm")
/// let area = popup.popup_area(screen, pop)
/// popup.render(buf, screen, pop)
/// |> paragraph.render(area, content_para)
/// ```
import etui/buffer
import etui/geometry
import etui/style
import etui/widgets/block

// ─────────────────────────────────────────────────────────────────
// Types

/// Popup configuration. Width/height are in terminal cells.
pub type Popup {
  Popup(
    width: Int,
    height: Int,
    title: String,
    border: block.Border,
    fg: style.Color,
    bg: style.Color,
  )
}

// ─────────────────────────────────────────────────────────────────
// Constructors

/// New popup with given cell dimensions. Default: Rounded border, default colors.
pub fn popup_new(width: Int, height: Int) -> Popup {
  Popup(
    width: width,
    height: height,
    title: "",
    border: block.Rounded,
    fg: style.Default,
    bg: style.Default,
  )
}

/// Set the popup title (shown on top border).
pub fn with_title(p: Popup, title: String) -> Popup {
  Popup(..p, title: title)
}

/// Set the border style.
pub fn with_border(p: Popup, border: block.Border) -> Popup {
  Popup(..p, border: border)
}

/// Set foreground and background colors.
pub fn with_style(p: Popup, fg: style.Color, bg: style.Color) -> Popup {
  Popup(..p, fg: fg, bg: bg)
}

pub fn with_colors(p: Popup, fg: style.Color, bg: style.Color) -> Popup {
  Popup(..p, fg: fg, bg: bg)
}

// ─────────────────────────────────────────────────────────────────
// Layout helpers

/// Centered rect for this popup within `screen`.
pub fn popup_rect(screen: geometry.Rect, p: Popup) -> geometry.Rect {
  let w = int_clamp(p.width, 0, screen.size.width)
  let h = int_clamp(p.height, 0, screen.size.height)
  let x = screen.position.x + { screen.size.width - w } / 2
  let y = screen.position.y + { screen.size.height - h } / 2
  geometry.Rect(
    position: geometry.Position(x: x, y: y),
    size: geometry.Size(width: w, height: h),
  )
}

/// Inner content area (inside border and padding) for child widgets.
pub fn popup_area(screen: geometry.Rect, p: Popup) -> geometry.Rect {
  let outer = popup_rect(screen, p)
  let blk = to_block(p)
  block.inner(outer, blk)
}

// ─────────────────────────────────────────────────────────────────
// Rendering

/// Render popup overlay. Draw child widgets into `popup_area` after this.
pub fn render(
  buf: buffer.Buffer,
  screen: geometry.Rect,
  p: Popup,
) -> buffer.Buffer {
  let outer = popup_rect(screen, p)
  let blk = to_block(p)
  block.render(buf, outer, blk)
}

// ─────────────────────────────────────────────────────────────────
// Internal helpers

fn to_block(p: Popup) -> block.Block {
  block.block_new()
  |> block.with_border(p.border)
  |> block.with_title(p.title, block.Top)
  |> block.with_style(p.fg, p.bg)
  |> block.with_bg_fill
}

fn int_clamp(v: Int, lo: Int, hi: Int) -> Int {
  case v < lo {
    True -> lo
    False ->
      case v > hi {
        True -> hi
        False -> v
      }
  }
}
