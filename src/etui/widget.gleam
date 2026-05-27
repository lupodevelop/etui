/// Extensible widget system for etui.
///
/// ## Ratatui / Cursive feature mapping
///
/// etui covers the same surface as ratatui's Widget + StatefulWidget traits:
///
/// | ratatui                    | etui                                  |
/// |----------------------------|----------------------------------------|
/// | `Widget::render`           | `Widget = fn(Buffer, Rect) -> Buffer`  |
/// | `StatefulWidget::render`   | `StatefulWidget(render: fn(B,R,S)->B)` |
/// | `WidgetRef::render_ref`    | `Widget` (functions capture by ref)    |
/// | `Frame::render_widget`     | `w(buf, area)` direct call             |
/// | `Frame::render_stateful_widget` | `render_stateful(buf, area, w, s)`|
/// | Layout + Constraint        | `geometry.split` + `geometry.Constraint` |
/// | `Block` widget             | `widgets/block.gleam`                  |
/// | `Paragraph` widget         | `widgets/paragraph.gleam`              |
/// | `List` + `ListState`       | `widgets/list.gleam`                   |
/// | `Table` + `TableState`     | `widgets/table.gleam`                  |
/// | `Tabs`                     | `widgets/tabs.gleam`                   |
/// | `Gauge` / `LineGauge`      | `widgets/gauge.gleam`                  |
/// | `BarChart`                 | `widgets/hbar.gleam` / `widgets/chart.gleam` |
/// | `Sparkline`                | `widgets/sparkline.gleam`              |
/// | `Canvas`                   | `widgets/canvas.gleam` (braille)       |
/// | `Clear`                    | `widgets/clear.gleam`                  |
/// | `Scrollbar`                | `widgets/scrollbar.gleam`              |
/// | `Popup` (community crate)  | `widgets/popup.gleam`                  |
/// | `StatusLine` (custom)      | `widgets/statusbar.gleam`              |
/// | `Spinner` (tui-additions)  | `widgets/spinner.gleam`                |
/// | `Paginator` (cheese)       | `widgets/paginator.gleam`              |
/// | `Help` (cheese)            | `widgets/help.gleam`                   |
/// | `Fieldset` (cheese)        | `widgets/fieldset.gleam`               |
/// | `MultiSelect` (cheese)     | `widgets/multi_select.gleam`           |
/// | `AnimationState`           | `anim.gleam` (lerp, ease, keyframes)   |
/// | `Color` (256 + RGB)        | `style.Indexed(n)` + `style.Rgb(r,g,b)`|
/// | `Modifier` bitfield        | `style.Modifier` (add/remove/has)      |
///
/// ## The Widget type
///
/// `Widget` is a plain function alias: `fn(Buffer, Rect) -> Buffer`.
/// Any function with that signature *is* a widget, no registration needed.
///
/// Wrapping a built-in widget:
/// ```gleam
/// let para = paragraph.paragraph_new("hello") |> paragraph.with_style(s)
/// let w: widget.Widget = fn(buf, area) { paragraph.render(buf, area, para) }
/// ```
///
/// ## Stateful widgets
///
/// `StatefulWidget(state)` holds a render function that also takes a state
/// value. Use `freeze` to bake state into a stateless `Widget`, or
/// `render_stateful` to render directly.
///
/// ## Animated widgets
///
/// `AnimatedWidget` is like `Widget` but also receives the current frame
/// number. Use `freeze_frame` to produce a `Widget` bound to a frame.
///
/// ## Composition
///
/// - `layer(bottom, top)`, draw two widgets in the same area, top on top.
/// - `at(w, sub_area)`, pin a widget to a fixed sub-area (ignores caller's area).
/// - `compose(border_w, inner_area, content_w)`, border fills area, content fills inner.
///
/// ## Custom widgets
///
/// Implement `Widget` directly:
/// ```gleam
/// fn clock_widget(buf: buffer.Buffer, area: geometry.Rect) -> buffer.Buffer {
///   paragraph.render(buf, area, paragraph.paragraph_new(get_time()))
/// }
/// // Use it anywhere a Widget is expected.
/// widget.layer(background_w, clock_widget)(buf, screen)
/// ```
import etui/buffer
import etui/geometry

// ─────────────────────────────────────────────────────────────────
// Core types

/// Stateless widget: a pure render function.
/// Any `fn(Buffer, Rect) -> Buffer` satisfies this type.
pub type Widget =
  fn(buffer.Buffer, geometry.Rect) -> buffer.Buffer

/// Stateful widget: carries a render function that also takes state.
/// State is kept external (in your app model) and passed at render time.
pub type StatefulWidget(state) {
  StatefulWidget(
    render: fn(buffer.Buffer, geometry.Rect, state) -> buffer.Buffer,
  )
}

/// Animated widget: a render function that also receives the current frame.
pub type AnimatedWidget =
  fn(buffer.Buffer, geometry.Rect, Int) -> buffer.Buffer

// ─────────────────────────────────────────────────────────────────
// Stateful helpers

/// Render a stateful widget with the given state value.
pub fn render_stateful(
  buf: buffer.Buffer,
  area: geometry.Rect,
  w: StatefulWidget(s),
  state: s,
) -> buffer.Buffer {
  w.render(buf, area, state)
}

/// Bake state into a stateless Widget.
/// The resulting Widget ignores any state updates after this call.
pub fn freeze(w: StatefulWidget(s), state: s) -> Widget {
  fn(buf, area) { w.render(buf, area, state) }
}

// ─────────────────────────────────────────────────────────────────
// Animated helpers

/// Bind a frame number to an AnimatedWidget, producing a stateless Widget.
pub fn freeze_frame(w: AnimatedWidget, frame: Int) -> Widget {
  fn(buf, area) { w(buf, area, frame) }
}

// ─────────────────────────────────────────────────────────────────
// Composition

/// Draw two widgets in the same area: `bottom` first, then `top` on top.
/// Use for overlaying a popup, cursor, or status indicator over content.
pub fn layer(bottom: Widget, top: Widget) -> Widget {
  fn(buf, area) { buf |> bottom(area) |> top(area) }
}

/// Pin a widget to a fixed `sub_area`, ignoring the caller-supplied area.
/// Use when a widget's position is pre-computed and shouldn't be overridden.
pub fn at(w: Widget, sub_area: geometry.Rect) -> Widget {
  fn(buf, _area) { w(buf, sub_area) }
}

/// Render `border_w` over `area`, then `content_w` over `inner_area`.
/// Convenience for the common "block border + child content" pattern:
///
/// ```gleam
/// let blk = block.block_new() |> block.with_border(block.Single)
/// let inner = block.inner(area, blk)
/// let composed = widget.compose(
///   fn(buf, a) { block.render(buf, a, blk) },
///   inner,
///   fn(buf, a) { paragraph.render(buf, a, para) },
/// )
/// composed(buf, area)
/// ```
pub fn compose(
  border_w: Widget,
  inner_area: geometry.Rect,
  content_w: Widget,
) -> Widget {
  fn(buf, area) { buf |> border_w(area) |> content_w(inner_area) }
}

/// Apply a list of widgets to the same area in order (each draws on top of the previous).
pub fn stack(widgets: List(Widget)) -> Widget {
  fn(buf, area) { fold_widgets(buf, area, widgets) }
}

fn fold_widgets(
  buf: buffer.Buffer,
  area: geometry.Rect,
  widgets: List(Widget),
) -> buffer.Buffer {
  case widgets {
    [] -> buf
    [w, ..rest] -> fold_widgets(w(buf, area), area, rest)
  }
}

// ─────────────────────────────────────────────────────────────────
// No-op widget

/// A widget that renders nothing. Useful as a default or placeholder.
pub fn empty() -> Widget {
  fn(buf, _area) { buf }
}
