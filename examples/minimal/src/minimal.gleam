import etui/app
import etui/backend
import etui/backend/default
import etui/buffer
import etui/geometry.{type Rect}
import etui/widgets/paragraph

pub type Model {
  Model(quit: Bool, width: Int, height: Int)
}

pub fn main() {
  let _ =
    app.run_buffered(
      default.new(),
      Model(quit: False, width: 80, height: 24),
      view,
      update,
      fn(m) { m.quit },
      16,
    )
}

fn view(_model: Model, screen: Rect) -> buffer.Buffer {
  buffer.buffer_new(screen)
  |> paragraph.render(
    screen,
    paragraph.paragraph_new("Hello, étui!  Press q to quit."),
  )
}

fn update(event: backend.InputEvent, model: Model) -> Model {
  case event {
    backend.Resize(w, h) -> Model(..model, width: w, height: h)
    backend.KeyPress("q") -> Model(..model, quit: True)
    _ -> model
  }
}
