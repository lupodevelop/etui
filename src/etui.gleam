/// etui, TUI library for Gleam.
///
/// Correct Unicode, minimal diff, no terminal left broken.
///
/// ## Quick start
///
/// ```gleam
/// import etui/app
/// import etui/backend
/// import etui/backend/default
/// import etui/buffer
/// import etui/geometry.{rect_new}
///
/// pub fn main() {
///   let _ = app.run_buffered(
///     default.new(),
///     Nil,
///     fn(_state, screen) { buffer.buffer_new(screen) },
///     fn(ev, state) { case ev { backend.KeyPress("q") -> state _ -> state } },
///     fn(_) { False },
///     16,
///   )
/// }
/// ```
///
/// ## Module map
///
/// | Module | Purpose |
/// |--------|---------|
/// | `etui/app` | Application event loop (`run`, `run_buffered`, `run_animated`, `run_buffered_cursor`) |
/// | `etui/backend` | Terminal event types and render ops |
/// | `etui/backend/default` | Platform-selecting backend (`new()` works on Erlang and JS) |
/// | `etui/buffer` | Cell grid storage, Unicode-aware rendering, diff output |
/// | `etui/geometry` | Layout math: `Rect`, `Constraint`, `split`, `resolve_sizes` |
/// | `etui/style` | Colors (Default / Indexed / Rgb), modifiers, ANSI sequences |
/// | `etui/text` | Grapheme cluster width, truncate, pad, Unicode-correct |
/// | `etui/span` | Inline styled text (`Span`, `Line`) |
/// | `etui/keys` | Key name constants and `match/1` for pattern-based dispatch |
/// | `etui/keymap` | Command-table key dispatch with help-text generation |
/// | `etui/theme` | Built-in colour themes (Dracula, Nord, Catppuccin, Monokai, …) |
/// | `etui/anim` | Animation helpers: lerp, easing, oscillate, keyframe sequences |
/// | `etui/cursor` | Hardware cursor ANSI sequences (show/hide/move/shape) |
/// | `etui/focus` | Focus-ring for multi-panel UIs |
/// | `etui/undo` | Generic undo/redo history stack |
/// | `etui/color` | RGB interpolation, gradients, hue-to-RGB |
///
/// ### Widgets
///
/// All stateless unless noted; stateful widgets store state externally.
///
/// | Widget | Module |
/// |--------|--------|
/// | Block / border | `etui/widgets/block` |
/// | Paragraph (text) | `etui/widgets/paragraph` |
/// | Scrollable list | `etui/widgets/list` *(stateful)* |
/// | Table / grid | `etui/widgets/table` *(stateful)* |
/// | Tree view | `etui/widgets/tree` *(stateful)* |
/// | Single-line input | `etui/widgets/input` *(stateful)* |
/// | Multi-line textarea | `etui/widgets/textarea` *(stateful)* |
/// | Form (multi-field) | `etui/widgets/form` *(stateful)* |
/// | Tabs | `etui/widgets/tabs` |
/// | Dialog | `etui/widgets/dialog` *(stateful)* |
/// | Notification | `etui/widgets/notification` |
/// | Status bar | `etui/widgets/statusbar` |
/// | Progress bar | `etui/widgets/progress` |
/// | Horizontal bar | `etui/widgets/hbar` |
/// | Gradient bar | `etui/widgets/gradient_bar` |
/// | Scrollbar | `etui/widgets/scrollbar` |
/// | Spinner | `etui/widgets/spinner` |
/// | Marquee | `etui/widgets/marquee` |
/// | Scroll view | `etui/widgets/scroll_view` *(stateful)* |
/// | Canvas (pixel) | `etui/widgets/canvas` |
/// | Braille graphics | `etui/braille` |
/// | Chart | `etui/widgets/chart` |
/// | Scene (composition) | `etui/widgets/scene` |
/// | Clear | `etui/widgets/clear` |
/// | Paginator | `etui/widgets/paginator` |
/// | Help (key bindings) | `etui/widgets/help` |
/// | Fieldset | `etui/widgets/fieldset` |
/// | MultiSelect | `etui/widgets/multi_select` *(stateful)* |
pub const version = "1.0.0"
