/// Clear widget: fill a Rect with empty cells.
///
/// Use this to erase a region before rendering over it, or to clear
/// popups/overlays when they are dismissed.
///
/// ```gleam
/// buffer.buffer_new(area)
/// |> clear.render(popup_rect)
/// |> block.render(popup_rect, block.block_new() |> block.with_border(block.Single))
/// ```
import etui/buffer
import etui/geometry

/// Fill `area` with empty cells (space, Default colors, no modifier).
pub fn render(buf: buffer.Buffer, area: geometry.Rect) -> buffer.Buffer {
  buffer.clear(buf, area)
}
