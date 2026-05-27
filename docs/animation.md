# Animation

## AnimState

Frame counter. Advance once per render tick.

```gleam
import etui/anim

let state = anim.anim_new()      // frame = 0
let state = anim.tick(state)     // frame + 1
let state = anim.reset(state)    // frame = 0

anim.is_done(state, 60)          // True when frame >= 60
```

Integrate into your app model:

```gleam
pub type Model { Model(anim: anim.AnimState, ...) }

fn update(event, model) {
  case event {
    backend.Tick -> Model(..model, anim: anim.tick(model.anim))
    _ -> model
  }
}
```

## Interpolation

All interpolation uses integer math. Results are identical on every BEAM target.

```gleam
// Linear: from 0 to 100 over 60 frames
anim.lerp(0, 100, model.anim.frame, 60)

// EaseOut: fast start, slow end
anim.ease_out(0, 100, model.anim.frame, 60)

// EaseIn: slow start, fast end
anim.ease_in(0, 100, model.anim.frame, 60)
```

All clamp `frame` to `[0, duration]`. At `frame == duration`, returns `end_`.

## AnimatedWidget

`widget.AnimatedWidget = fn(Buffer, Rect, Int) -> Buffer`

The frame integer drives all animation logic inside the widget. The widget stays pure, with no mutable state.

```gleam
import etui/widget
import etui/widgets/spinner

// Spinner is an AnimatedWidget
let spin_w: widget.AnimatedWidget = fn(buf, area, frame) {
  spinner.render(buf, area, spinner.spinner_new() |> spinner.with_style(spinner.Dots), frame)
}

// Bind current frame at render time
let w: widget.Widget = widget.freeze_frame(spin_w, model.anim.frame)
w(buf, area)
```

## Color animation

```gleam
import etui/color

// Lerp between two Rgb colors over 60 frames
let c = color.lerp_rgb(
  style.Rgb(255, 0, 0),    // start: red
  style.Rgb(0, 0, 255),    // end: blue
  model.anim.frame,
  60,
)
let s = style.Style(fg: c, bg: style.Default, modifier: style.none())
```

`color.lerp_rgb` interpolates R, G, B channels independently using integer math.

## Spinner built-in frames

```gleam
spinner.Dots      // ⣾ ⣽ ⣻ ⢿ ⡿ ⣟ ⣯ ⣷
spinner.Braille   // braille rotation
spinner.Arc       // ◜ ◠ ◝ ◞ ◡ ◟
spinner.Line      // – \ | /
spinner.Bounce    // ⠁ ⠂ ⠄ ⠂
```

Advance frame each tick; spinner wraps automatically.

## Marquee (scrolling text)

```gleam
import etui/widgets/marquee

let m =
  marquee.marquee_new("  scrolling content  ")
  |> marquee.with_speed(1)   // cells advanced per frame

// frame drives the scroll offset (cell-accurate for wide chars)
marquee.render(buf, area, m, model.anim.frame)
```

## Full animation example

```gleam
import etui/backend

pub type Model {
  Model(anim: anim.AnimState, width: Int, height: Int)
}

fn view(model: Model, screen: geometry.Rect) -> buffer.Buffer {
  let frame = model.anim.frame

  // Pulse color: 0→255→0 over 120 frames
  let v = anim.ease_out(0, 255, frame % 120, 60)
  let color = case frame % 120 < 60 {
    True  -> style.Rgb(v, 0, 0)
    False -> style.Rgb(255 - v, 0, 0)
  }

  let para =
    paragraph.paragraph_new("etui")
    |> paragraph.with_style(style.Style(fg: color, bg: style.Default, modifier: style.bold()))

  buffer.buffer_new(screen)
  |> paragraph.render(screen, para)
}

fn update(event: backend.InputEvent, model: Model) -> Model {
  case event {
    backend.Tick         -> Model(..model, anim: anim.tick(model.anim))
    backend.Resize(w, h) -> Model(..model, width: w, height: h)
    _ -> model
  }
}
```
