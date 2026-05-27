# Custom Widgets

## Widget type

A widget is any function with signature `fn(Buffer, Rect) -> Buffer`. No registration, no traits.

```gleam
import etui/buffer
import etui/geometry
import etui/widget
import etui/widgets/paragraph

// This function is already a widget, no wrapping needed
fn clock_widget(buf: buffer.Buffer, area: geometry.Rect) -> buffer.Buffer {
  paragraph.render(buf, area, paragraph.paragraph_new(get_current_time()))
}

// Use it anywhere a Widget is expected
widget.layer(background_w, clock_widget)(buf, screen)
```

`widget.Widget` is a type alias: `fn(buffer.Buffer, geometry.Rect) -> buffer.Buffer`.

## Stateful widgets

State lives in your app model. The widget receives it at render time.

```gleam
import etui/widget

pub type CounterState { CounterState(count: Int) }

let counter_w = widget.StatefulWidget(render: fn(buf, area, state: CounterState) {
  let text = "Count: " <> int.to_string(state.count)
  paragraph.render(buf, area, paragraph.paragraph_new(text))
})

// Render with state from model
widget.render_stateful(buf, area, counter_w, my_state)

// Or bake state in (makes it stateless)
let frozen: widget.Widget = widget.freeze(counter_w, CounterState(42))
frozen(buf, area)
```

## Animated widgets

`AnimatedWidget = fn(Buffer, Rect, Int) -> Buffer`. The third argument is the frame number.

```gleam
let pulse_w: widget.AnimatedWidget = fn(buf, area, frame) {
  let bright = frame % 30 < 15
  let color = case bright { True -> style.Rgb(255, 255, 0) False -> style.Rgb(128, 128, 0) }
  let s = style.Style(fg: color, bg: style.Default, modifier: style.none())
  paragraph.render(buf, area, paragraph.paragraph_new("●") |> paragraph.with_style(s))
}

// Bind frame at render time
let w: widget.Widget = widget.freeze_frame(pulse_w, anim_state.frame)
w(buf, area)
```

## Composition helpers

### layer

Draw two widgets in the same area. `bottom` first, then `top` on top.

```gleam
let w = widget.layer(background_w, overlay_w)
```

### stack

Draw a list of widgets in the same area, in order.

```gleam
let w = widget.stack([bg_w, content_w, cursor_w, highlight_w])
```

### at

Pin a widget to a fixed sub-area. Ignores the caller-supplied area.

```gleam
let sub = geometry.Rect(position: Position(x: 4, y: 1), size: Size(width: 20, height: 1))
let w = widget.at(label_w, sub)
// w(buf, any_area) always renders into sub
```

### compose

Border fills `area`, content fills `inner_area`. The common "block + child" pattern.

```gleam
let blk = block.block_new() |> block.with_border(block.Single)
let inner = block.inner(area, blk)

let composed = widget.compose(
  fn(buf, a) { block.render(buf, a, blk) },
  inner,
  fn(buf, a) { paragraph.render(buf, a, para) },
)
composed(buf, area)
```

### empty

No-op widget. Renders nothing.

```gleam
let placeholder: widget.Widget = widget.empty()
```

## Real example: progress panel

```gleam
fn progress_panel(model: Model) -> widget.Widget {
  let blk = block.block_new()
    |> block.with_border(block.Rounded)
    |> block.with_title("Progress", block.Top)

  fn(buf, area) {
    let inner = block.inner(area, blk)
    let gauge_area = geometry.Rect(
      position: inner.position,
      size: geometry.Size(width: inner.size.width, height: 1),
    )
    let g = gauge.gauge_new(model.percent)
      |> gauge.with_label(int.to_string(model.percent) <> "%")
    buf
    |> block.render(area, blk)
    |> gauge.render(gauge_area, g)
  }
}
```

The function closes over `model` directly. Read-only data does not need a state wrapper.

## Building from buffer primitives

```gleam
import etui/buffer
import etui/geometry
import etui/style

fn custom_render(buf: buffer.Buffer, area: geometry.Rect) -> buffer.Buffer {
  let pos = area.position
  buffer.set_string(buf, pos, "custom", style.Default, style.Default, style.none())
}
```

`buffer.set_string` writes a string left-to-right starting at `pos`, respecting cell widths for wide characters. Wide chars leave a `Continuation` cell automatically.

## Testing custom widgets

```gleam
import gleeunit/should
import etui/buffer
import etui/geometry.{Position, Rect, Size}

fn read_row(buf, y, x, n) { ... }  // see test/widget_extensibility_test.gleam

pub fn my_widget_test() {
  let area = Rect(position: Position(x: 0, y: 0), size: Size(width: 10, height: 1))
  let buf = buffer.buffer_new(area)
  let result = my_widget(buf, area)
  read_row(result, 0, 0, 5) |> should.equal("hello")
}
```

No terminal process needed. All tests run headless.
