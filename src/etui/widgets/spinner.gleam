import etui/anim
import etui/buffer
import etui/geometry
import etui/style
import gleam/list

// ─────────────────────────────────────────────────────────────────
// Types

pub type SpinnerStyle {
  Dots
  Line
  Circle
  Bounce
  MiniDot
  Jump
  Pulse
  Points
  Globe
  Moon
  Monkey
  Meter
  Hamburger
  Ellipsis
  Custom(frames: List(String))
}

pub type Spinner {
  Spinner(style: SpinnerStyle, label: String, fg: style.Color, bg: style.Color)
}

// ─────────────────────────────────────────────────────────────────
// Constructors

pub fn spinner_new() -> Spinner {
  Spinner(style: Dots, label: "", fg: style.Default, bg: style.Default)
}

pub fn with_style(s: Spinner, spinner_style: SpinnerStyle) -> Spinner {
  Spinner(..s, style: spinner_style)
}

pub fn with_label(s: Spinner, label: String) -> Spinner {
  Spinner(..s, label: label)
}

pub fn with_colors(s: Spinner, fg: style.Color, bg: style.Color) -> Spinner {
  Spinner(..s, fg: fg, bg: bg)
}

pub fn with_render_style(s: Spinner, st: style.Style) -> Spinner {
  Spinner(..s, fg: st.fg, bg: st.bg)
}

// ─────────────────────────────────────────────────────────────────
// Rendering
//
// `frame` comes from the caller's AnimState.frame, the spinner is
// stateless and purely a function of the current frame number.

pub fn render(
  buf: buffer.Buffer,
  area: geometry.Rect,
  s: Spinner,
  frame: Int,
) -> buffer.Buffer {
  case area.size.width <= 0 || area.size.height <= 0 {
    True -> buf
    False -> {
      let char = spin_char(s.style, frame)
      let line = case s.label {
        "" -> char
        label -> char <> " " <> label
      }
      buffer.set_string(buf, area.position, line, s.fg, s.bg, style.none())
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Frame → character

fn spin_char(spinner_style: SpinnerStyle, frame: Int) -> String {
  case spinner_style {
    Dots -> {
      let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
      nth_frame(frames, anim.cycle(frame, 10))
    }
    Line -> {
      let frames = ["-", "\\", "|", "/"]
      nth_frame(frames, anim.cycle(frame, 4))
    }
    Circle -> {
      let frames = ["◐", "◓", "◑", "◒"]
      nth_frame(frames, anim.cycle(frame, 4))
    }
    Bounce -> {
      let frames = ["⠁", "⠂", "⠄", "⠂"]
      nth_frame(frames, anim.cycle(frame, 4))
    }
    MiniDot -> {
      let frames = ["⠂", "⠁", "⠈", "⠐", "⠠", "⢀", "⡀", "⠄"]
      nth_frame(frames, anim.cycle(frame, 8))
    }
    Jump -> {
      let frames = ["▀", "▄"]
      nth_frame(frames, anim.cycle(frame, 2))
    }
    Pulse -> {
      let frames = ["█", "▓", "▒", "░", "▒", "▓"]
      nth_frame(frames, anim.cycle(frame, 6))
    }
    Points -> {
      let frames = ["∙∙∙", "●∙∙", "∙●∙", "∙∙●"]
      nth_frame(frames, anim.cycle(frame, 4))
    }
    Globe -> {
      let frames = ["🌍", "🌎", "🌏"]
      nth_frame(frames, anim.cycle(frame, 3))
    }
    Moon -> {
      let frames = ["🌑", "🌒", "🌓", "🌔", "🌕", "🌖", "🌗", "🌘"]
      nth_frame(frames, anim.cycle(frame, 8))
    }
    Monkey -> {
      let frames = ["🙈", "🙉", "🙊"]
      nth_frame(frames, anim.cycle(frame, 3))
    }
    Meter -> {
      let frames = ["▱▱▱", "▰▱▱", "▰▰▱", "▰▰▰", "▰▰▱", "▰▱▱"]
      nth_frame(frames, anim.cycle(frame, 6))
    }
    Hamburger -> {
      let frames = ["☱", "☲", "☴", "☲"]
      nth_frame(frames, anim.cycle(frame, 4))
    }
    Ellipsis -> {
      let frames = ["   ", ".  ", ".. ", "..."]
      nth_frame(frames, anim.cycle(frame, 4))
    }
    Custom(frames) -> {
      let count = list.length(frames)
      nth_frame(frames, anim.cycle(frame, count))
    }
  }
}

fn nth_frame(frames: List(String), idx: Int) -> String {
  do_nth(frames, idx)
}

fn do_nth(items: List(String), n: Int) -> String {
  case items {
    [] -> "?"
    [h, ..] if n <= 0 -> h
    [_, ..rest] -> do_nth(rest, n - 1)
  }
}
