import etui/app
import etui/backend
import etui/backend/default
import etui/buffer
import etui/geometry.{type Rect, Fill, Horizontal, Percentage}
import etui/widgets/block
import etui/widgets/paragraph
import gleam/int

pub type Model {
  Model(count: Int, quit: Bool, width: Int, height: Int)
}

pub fn main() {
  let _ =
    app.run_buffered(
      default.new(),
      Model(count: 0, quit: False, width: 80, height: 24),
      view,
      update,
      fn(m) { m.quit },
      16,
    )
}

fn view(model: Model, screen: Rect) -> buffer.Buffer {
  let chunks = geometry.split(Horizontal, screen, [Percentage(30), Fill])
  let left = case chunks { [l, ..] -> l _ -> screen }
  let right = case chunks { [_, r, ..] -> r _ -> screen }
  let para =
    paragraph.paragraph_new("Count: " <> int.to_string(model.count) <> "  (space +1, q quit)")
  let blk =
    block.block_new()
    |> block.with_border(block.Rounded)
    |> block.with_title("Main", block.Top)
  let sidebar =
    block.block_new()
    |> block.with_border(block.Single)
    |> block.with_title("Side", block.Top)
  buffer.buffer_new(screen)
  |> block.render(left, sidebar)
  |> block.render(right, blk)
  |> paragraph.render(block.inner(right, blk), para)
}

fn update(event: backend.InputEvent, model: Model) -> Model {
  case event {
    backend.KeyPress("q") -> Model(..model, quit: True)
    backend.KeyPress(" ") -> Model(..model, count: model.count + 1)
    backend.Resize(w, h) -> Model(..model, width: w, height: h)
    _ -> model
  }
}
