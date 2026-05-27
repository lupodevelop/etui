/// Development example: demonstrates all Etui widgets and layout system.
import etui/buffer
import etui/geometry.{
  type Rect, Fill, Horizontal, Length, Position, Rect, Size, Vertical,
}
import etui/text
import etui/widgets/block
import etui/widgets/input as ginput_widget
import etui/widgets/line
import etui/widgets/list as glist_widget
import etui/widgets/paragraph
import etui/widgets/table as gtable_widget
import gleam/io
import gleam/list
import gleam/string

pub fn main() -> Nil {
  let screen = Rect(Position(0, 0), Size(80, 24))
  let buf = buffer.buffer_new(screen)

  // Split screen: 20% sidebar, 80% main
  let chunks =
    geometry.split(Horizontal, screen, [
      Length(20),
      Fill,
    ])

  let sidebar = case chunks {
    [s, ..] -> s
    [] -> screen
  }

  let main = case chunks {
    [_, m, ..] -> m
    _ -> screen
  }

  // Render sidebar with list
  let buf_with_sidebar = render_sidebar(buf, sidebar)

  // Render main content
  let buf_final = render_main(buf_with_sidebar, main)

  // Visualize buffer
  io.println("=== Etui v0.2.0 Demo (Widgets: List, Block, Paragraph, Line) ===")
  io.println("")
  buffer_to_lines(buf_final)
  |> list.each(io.println)
  io.println("")
}

fn buffer_to_lines(buf: buffer.Buffer) -> List(String) {
  let height = buffer.height(buf)
  range(0, height)
  |> list.map(fn(y) {
    let width = buffer.width(buf)
    range(0, width)
    |> list.map(fn(x) {
      let cell = buffer.get_cell(buf, geometry.Position(x: x, y: y))
      case buffer.is_continuation(cell) {
        True -> ""
        False -> buffer.cell_symbol(cell)
      }
    })
    |> string.concat
  })
}

fn range(start: Int, end: Int) -> List(Int) {
  case start >= end {
    True -> []
    False -> [start, ..range(start + 1, end)]
  }
}

fn render_sidebar(buf: buffer.Buffer, area: Rect) -> buffer.Buffer {
  // Split sidebar into header and list
  let chunks =
    geometry.split(Vertical, area, [
      Length(2),
      Fill,
    ])

  let header_area = case chunks {
    [h, ..] -> h
    [] -> area
  }

  let list_area = case chunks {
    [_, l, ..] -> l
    _ -> area
  }

  // Render header block with Double border
  let header_block =
    block.block_new()
    |> block.with_border(block.Double)
    |> block.with_title("Menu", block.Top)

  let buf_with_header = block.render(buf, header_area, header_block)

  // Render list with selection
  let items = ["Home", "Items", "Settings", "About"]
  let list_widget = glist_widget.list_new(items)
  let list_state = glist_widget.state_new() |> glist_widget.select(1)

  glist_widget.render_stateful(
    buf_with_header,
    list_area,
    list_widget,
    list_state,
  )
}

fn render_main(buf: buffer.Buffer, area: Rect) -> buffer.Buffer {
  // Split main into header and content
  let chunks =
    geometry.split(Vertical, area, [
      Length(3),
      Fill,
    ])

  let header = case chunks {
    [h, ..] -> h
    [] -> area
  }

  let content = case chunks {
    [_, c, ..] -> c
    _ -> area
  }

  // Render header with title and line
  let buf_with_header = render_header(buf, header)

  // Render content area
  let buf_final = render_content(buf_with_header, content)

  buf_final
}

fn render_header(buf: buffer.Buffer, area: Rect) -> buffer.Buffer {
  let title = "Etui v0.2.0: List Widget Demo"
  let p =
    paragraph.paragraph_new(title)
    |> paragraph.with_alignment(text.Center)

  let buf_with_para = paragraph.render(buf, area, p)

  // Add divider line
  let line_area =
    Rect(
      Position(area.position.x, area.position.y + 2),
      Size(area.size.width, 1),
    )

  let divider = line.line_new()
  line.render_horizontal(buf_with_para, line_area, divider)
}

fn render_content(buf: buffer.Buffer, area: Rect) -> buffer.Buffer {
  // Split content into description, table, and input
  let chunks =
    geometry.split(Vertical, area, [
      Length(6),
      Length(6),
      Fill,
    ])

  let desc_area = case chunks {
    [d, ..] -> d
    [] -> area
  }

  let table_area = case chunks {
    [_, t, ..] -> t
    _ -> area
  }

  let input_area = case chunks {
    [_, _, i, ..] -> i
    _ -> area
  }

  // Render description
  let content_text =
    "Etui v0.2.0 adds Table and Input widgets:\n• Table: Rows, columns, and selection\n• Input: Text field with editing support"

  let p =
    paragraph.paragraph_new(content_text)
    |> paragraph.with_alignment(text.Left)

  let buf_with_desc = paragraph.render(buf, desc_area, p)

  // Render table
  let table_rows = [
    ["Widget", "Status", "Tests"],
    ["List", "✓ Done", "4"],
    ["Table", "✓ Done", "5"],
    ["Input", "✓ Done", "7"],
  ]

  let table_widget =
    gtable_widget.table_new(table_rows)
    |> gtable_widget.with_col_widths([12, 10, 8])
  let table_state = gtable_widget.state_new() |> gtable_widget.select_row(1)

  let buf_with_table =
    gtable_widget.render_stateful(
      buf_with_desc,
      table_area,
      table_widget,
      table_state,
    )

  // Render input field
  let input_widget = ginput_widget.input_new("Search...")
  let input_state = ginput_widget.state_from_string("query")

  ginput_widget.render(buf_with_table, input_area, input_widget, input_state)
}
