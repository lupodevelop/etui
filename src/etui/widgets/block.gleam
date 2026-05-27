/// Block widget: border, title, padding.
import etui/buffer
import etui/geometry
import etui/span
import etui/style
import etui/text
import gleam/int

// ─────────────────────────────────────────────────────────────────
// Types

/// Box-drawing border style.
pub type Border {
  None
  Single
  Double
  Rounded
}

/// Where to place the block title.
pub type TitlePosition {
  Top
  Bottom
}

/// Configuration for a bordered, titled container.
pub type Block {
  Block(
    border: Border,
    title: String,
    /// Styled title spans. When non-empty, used instead of `title`.
    title_spans: List(span.Span),
    title_position: TitlePosition,
    title_alignment: text.Alignment,
    padding_top: Int,
    padding_bottom: Int,
    padding_left: Int,
    padding_right: Int,
    fg: style.Color,
    bg: style.Color,
    fill_bg: Bool,
  )
}

// ─────────────────────────────────────────────────────────────────
// Constructors

/// New block with no border, no title, no padding, default colors.
pub fn block_new() -> Block {
  Block(
    border: None,
    title: "",
    title_spans: [],
    title_position: Top,
    title_alignment: text.Left,
    padding_top: 0,
    padding_bottom: 0,
    padding_left: 0,
    padding_right: 0,
    fg: style.Default,
    bg: style.Default,
    fill_bg: False,
  )
}

/// Fill the inner area with the block's background color.
pub fn with_bg_fill(blk: Block) -> Block {
  Block(..blk, fill_bg: True)
}

/// Set the border style. `Single` draws ┌─┐│└─┘, `Double` ╔═╗║╚═╝, `Rounded` ╭─╮│╰─╯.
pub fn with_border(blk: Block, border: Border) -> Block {
  Block(..blk, border: border)
}

/// Set a title string and whether it appears on the top or bottom border.
pub fn with_title(blk: Block, title: String, position: TitlePosition) -> Block {
  Block(..blk, title: title, title_spans: [], title_position: position)
}

/// Set a styled title from a list of `span.Span` values.
/// Takes precedence over `with_title` when non-empty.
///
/// ```gleam
/// block.block_new()
/// |> block.with_border(block.Rounded)
/// |> block.with_title_styled([
///   span.span_styled("★ ", style.bold_style() |> style.with_fg(style.Rgb(255,215,0))),
///   span.span_plain("Dashboard"),
/// ], block.Top)
/// ```
pub fn with_title_styled(
  blk: Block,
  spans: List(span.Span),
  position: TitlePosition,
) -> Block {
  Block(..blk, title_spans: spans, title: "", title_position: position)
}

/// Set inner padding (cells between border and content).
pub fn with_padding(
  blk: Block,
  top: Int,
  bottom: Int,
  left: Int,
  right: Int,
) -> Block {
  Block(
    ..blk,
    padding_top: top,
    padding_bottom: bottom,
    padding_left: left,
    padding_right: right,
  )
}

/// Set the horizontal alignment of the title within the border.
pub fn with_title_alignment(blk: Block, alignment: text.Alignment) -> Block {
  Block(..blk, title_alignment: alignment)
}

/// Set foreground and background colors for the border and title.
pub fn with_style(blk: Block, fg: style.Color, bg: style.Color) -> Block {
  Block(..blk, fg: fg, bg: bg)
}

/// Alias for `with_style(fg, bg)`, consistent with other widget naming.
pub fn with_colors(blk: Block, fg: style.Color, bg: style.Color) -> Block {
  Block(..blk, fg: fg, bg: bg)
}

// ─────────────────────────────────────────────────────────────────
// Rendering

/// Render block into buffer at given area.
pub fn render(
  buf: buffer.Buffer,
  area: geometry.Rect,
  blk: Block,
) -> buffer.Buffer {
  case blk.border {
    None -> render_content(buf, area, blk)
    Single -> render_bordered(buf, area, blk, "─", "│", "┌", "┐", "└", "┘")
    Double -> render_bordered(buf, area, blk, "═", "║", "╔", "╗", "╚", "╝")
    Rounded -> render_bordered(buf, area, blk, "─", "│", "╭", "╮", "╰", "╯")
  }
}

fn render_bordered(
  buf: buffer.Buffer,
  area: geometry.Rect,
  blk: Block,
  border_h: String,
  border_v: String,
  corner_tl: String,
  corner_tr: String,
  corner_bl: String,
  corner_br: String,
) -> buffer.Buffer {
  let width = area.size.width
  let height = area.size.height

  case width < 2 || height < 2 {
    True -> buf
    False -> {
      let x0 = area.position.x
      let y0 = area.position.y
      let y_bottom = geometry.bottom(area) - 1
      let x_right = geometry.right(area) - 1

      let cell_border =
        buffer.Cell(
          content: buffer.Content(symbol: border_h, width: 1),
          fg: blk.fg,
          bg: blk.bg,
          modifier: style.none(),
          link: "",
        )

      let buf1 =
        buffer.set_cell(
          buf,
          geometry.Position(x: x0, y: y0),
          buffer.Cell(
            content: buffer.Content(symbol: corner_tl, width: 1),
            fg: blk.fg,
            bg: blk.bg,
            modifier: style.none(),
            link: "",
          ),
        )
      let buf2 =
        buffer.set_cell(
          buf1,
          geometry.Position(x: x_right, y: y0),
          buffer.Cell(
            content: buffer.Content(symbol: corner_tr, width: 1),
            fg: blk.fg,
            bg: blk.bg,
            modifier: style.none(),
            link: "",
          ),
        )
      let buf3 =
        buffer.set_cell(
          buf2,
          geometry.Position(x: x0, y: y_bottom),
          buffer.Cell(
            content: buffer.Content(symbol: corner_bl, width: 1),
            fg: blk.fg,
            bg: blk.bg,
            modifier: style.none(),
            link: "",
          ),
        )
      let buf4 =
        buffer.set_cell(
          buf3,
          geometry.Position(x: x_right, y: y_bottom),
          buffer.Cell(
            content: buffer.Content(symbol: corner_br, width: 1),
            fg: blk.fg,
            bg: blk.bg,
            modifier: style.none(),
            link: "",
          ),
        )

      let buf5 =
        draw_horizontal_line(buf4, x0 + 1, x_right - 1, y0, cell_border)
      let buf6 =
        draw_horizontal_line(buf5, x0 + 1, x_right - 1, y_bottom, cell_border)

      let cell_v =
        buffer.Cell(
          content: buffer.Content(symbol: border_v, width: 1),
          fg: blk.fg,
          bg: blk.bg,
          modifier: style.none(),
          link: "",
        )
      let buf7 = draw_vertical_line(buf6, x0, y0 + 1, y_bottom - 1, cell_v)
      let buf8 = draw_vertical_line(buf7, x_right, y0 + 1, y_bottom - 1, cell_v)

      let buf9 = render_title(buf8, area, blk)
      render_content(buf9, inner_area(area, blk), blk)
    }
  }
}

fn render_title(
  buf: buffer.Buffer,
  area: geometry.Rect,
  blk: Block,
) -> buffer.Buffer {
  let x0 = area.position.x + 1
  let max_width = area.size.width - 2
  case blk.title_spans {
    [_, ..] -> {
      let y = case blk.title_position {
        Top -> area.position.y
        Bottom -> geometry.bottom(area) - 1
      }
      let line = span.line_aligned(blk.title_spans, blk.title_alignment)
      span.render_line(buf, geometry.Position(x: x0, y: y), line, max_width)
    }
    [] ->
      case blk.title {
        "" -> buf
        title -> {
          let title_width = text.cell_width(title)
          let t = case title_width > max_width {
            True -> text.truncate(title, max_width, "…")
            False -> title
          }
          let t_width = text.cell_width(t)
          let x_offset = case blk.title_alignment {
            text.Left -> 0
            text.Right -> int.max(0, max_width - t_width)
            text.Center -> int.max(0, { max_width - t_width } / 2)
          }
          let y = case blk.title_position {
            Top -> area.position.y
            Bottom -> geometry.bottom(area) - 1
          }
          buffer.set_string(
            buf,
            geometry.Position(x: x0 + x_offset, y: y),
            t,
            blk.fg,
            blk.bg,
            style.none(),
          )
        }
      }
  }
}

fn render_content(
  buf: buffer.Buffer,
  area: geometry.Rect,
  blk: Block,
) -> buffer.Buffer {
  case blk.fill_bg {
    False -> buffer.clear(buf, area)
    True -> fill_bg_area(buf, area, blk.fg, blk.bg, area.position.y)
  }
}

fn fill_bg_area(
  buf: buffer.Buffer,
  area: geometry.Rect,
  fg: style.Color,
  bg: style.Color,
  y: Int,
) -> buffer.Buffer {
  case y >= area.position.y + area.size.height {
    True -> buf
    False -> {
      let row = text.pad_right("", area.size.width)
      let buf2 =
        buffer.set_string(
          buf,
          geometry.Position(x: area.position.x, y: y),
          row,
          fg,
          bg,
          style.none(),
        )
      fill_bg_area(buf2, area, fg, bg, y + 1)
    }
  }
}

/// Inner area (content region) of a block, accounting for border and padding.
///
/// Use this to get the Rect to pass to child widgets:
///
/// ```gleam
/// let b = block.block_new() |> block.with_border(block.Single)
/// block.render(buf, area, b)
/// |> paragraph.render(block.inner(area, b), p)
/// ```
pub fn inner(area: geometry.Rect, blk: Block) -> geometry.Rect {
  inner_area(area, blk)
}

fn inner_area(area: geometry.Rect, blk: Block) -> geometry.Rect {
  let border_offset = case blk.border {
    None -> 0
    Single -> 1
    Double -> 1
    Rounded -> 1
  }
  let x = area.position.x + blk.padding_left + border_offset
  let y = area.position.y + blk.padding_top + border_offset
  let w =
    int.max(
      0,
      area.size.width - blk.padding_left - blk.padding_right - border_offset * 2,
    )
  let h =
    int.max(
      0,
      area.size.height
        - blk.padding_top
        - blk.padding_bottom
        - border_offset
        * 2,
    )
  geometry.Rect(
    position: geometry.Position(x: x, y: y),
    size: geometry.Size(width: w, height: h),
  )
}

// ─────────────────────────────────────────────────────────────────
// Helpers

fn draw_horizontal_line(
  buf: buffer.Buffer,
  x_start: Int,
  x_end: Int,
  y: Int,
  cell: buffer.Cell,
) -> buffer.Buffer {
  case x_start > x_end {
    True -> buf
    False -> {
      let buf_new =
        buffer.set_cell(buf, geometry.Position(x: x_start, y: y), cell)
      draw_horizontal_line(buf_new, x_start + 1, x_end, y, cell)
    }
  }
}

fn draw_vertical_line(
  buf: buffer.Buffer,
  x: Int,
  y_start: Int,
  y_end: Int,
  cell: buffer.Cell,
) -> buffer.Buffer {
  case y_start > y_end {
    True -> buf
    False -> {
      let buf_new =
        buffer.set_cell(buf, geometry.Position(x: x, y: y_start), cell)
      draw_vertical_line(buf_new, x, y_start + 1, y_end, cell)
    }
  }
}
