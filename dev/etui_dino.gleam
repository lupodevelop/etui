/// GATUI DINO, Chrome T-Rex runner in the terminal.
/// Run: gleam run -m etui_dino
/// SPACE / ↑ to jump  ·  q / ESC to quit  ·  r to restart
import etui/anim
import etui/app
import etui/backend
import etui/backend/default
import etui/buffer
import etui/geometry.{type Rect, rect_new}
import etui/keys
import etui/span
import etui/style
import etui/widgets/paragraph
import gleam/int
import gleam/list
import gleam/string

// ─── Physics (fixed-point × 4) ───────────────────────────────────

const jump_vy = 20

// initial upward velocity in fp units (= 5 rows/frame)

const gravity = 3

// downward acceleration per frame

const initial_speed = 5

// obstacle speed in fp units/frame (= 1.25 cols/frame)

// ─── Palette ─────────────────────────────────────────────────────

const c_dino = style.Indexed(213)

const c_dino_dead = style.Indexed(196)

const c_cactus = style.Indexed(76)

const c_ground = style.Indexed(244)

const c_cloud = style.Indexed(237)

const c_score = style.Indexed(255)

const c_best = style.Indexed(214)

const c_dim = style.Indexed(238)

const c_hi = style.Indexed(226)

// ─── FFI: read actual terminal size before entering raw mode ─────

@external(erlang, "etui_terminal_ffi", "window_size")
fn tty_size() -> Result(#(Int, Int), String) {
  Error("not erlang")
}

// ─── Types ───────────────────────────────────────────────────────

type State {
  Title
  Playing
  Dead
}

// Cactus variant: determines sprite shape
type CKind {
  CSpike
  // 1 wide, pointed tip
  CSingle
  // 2 wide, one arm
  CBig
  // 3 wide, two arms
}

type Obs {
  Obs(x_fp: Int, h: Int, kind: CKind)
}

type Model {
  Model(
    state: State,
    y_fp: Int,
    vy_fp: Int,
    obs: List(Obs),
    frame: Int,
    next_obs: Int,
    speed: Int,
    score: Int,
    best: Int,
    width: Int,
    height: Int,
    quit: Bool,
  )
}

fn initial_size() -> #(Int, Int) {
  case tty_size() {
    Ok(#(c, r)) -> #(c, r)
    Error(_) -> #(80, 24)
  }
}

fn blank_model() -> Model {
  let #(w, h) = initial_size()
  Model(
    state: Title,
    y_fp: 0,
    vy_fp: 0,
    obs: [],
    frame: 0,
    next_obs: 50,
    speed: initial_speed,
    score: 0,
    best: 0,
    width: w,
    height: h,
    quit: False,
  )
}

fn restart(m: Model) -> Model {
  Model(
    ..m,
    state: Playing,
    y_fp: 0,
    vy_fp: 0,
    obs: [],
    frame: 0,
    next_obs: 50,
    speed: initial_speed,
    score: 0,
  )
}

// ─── Layout ──────────────────────────────────────────────────────

fn ground_row(h: Int) -> Int {
  h - 5
}

const dino_col = 8

const dino_h = 4

fn dino_top(h: Int, y_fp: Int) -> Int {
  ground_row(h) - dino_h - y_fp / 4
}

fn obs_width(kind: CKind) -> Int {
  case kind {
    CSpike -> 1
    CSingle -> 2
    CBig -> 3
  }
}

// ─── PRNG ────────────────────────────────────────────────────────

fn prng(seed: Int) -> Int {
  let v = seed * 1_664_525 + 1_013_904_223
  case v < 0 {
    True -> -v
    False -> v
  }
}

fn irange(n: Int) -> List(Int) {
  irange_acc(0, n, [])
}

fn irange_acc(i: Int, n: Int, acc: List(Int)) -> List(Int) {
  case i >= n {
    True -> list.reverse(acc)
    False -> irange_acc(i + 1, n, [i, ..acc])
  }
}

// ─── Game tick ───────────────────────────────────────────────────

fn tick(m: Model) -> Model {
  // Gravity
  let new_vy = m.vy_fp - gravity
  let new_y = m.y_fp + new_vy
  let #(y_fp, vy_fp) = case new_y <= 0 {
    True -> #(0, 0)
    False -> #(new_y, new_vy)
  }

  // Move obstacles left, remove offscreen
  let obs =
    m.obs
    |> list.map(fn(o) { Obs(..o, x_fp: o.x_fp - m.speed) })
    |> list.filter(fn(o) { o.x_fp > -{ obs_width(o.kind) + 2 } * 4 })

  let score = m.score + 1

  // Speed increases every 200 points, max +5
  let speed = initial_speed + int.min(score / 200, 5)

  // Spawn obstacle
  let #(obs, next_obs) = case m.frame >= m.next_obs {
    False -> #(obs, m.next_obs)
    True -> {
      let seed = m.frame * 31 + score * 7
      let gap = int.max(30 - speed * 2, 15) + prng(seed) % 25
      let h = 2 + prng(seed + 3) % 3
      let kind = case prng(seed + 11) % 3 {
        0 -> CSpike
        1 -> CSingle
        _ -> CBig
      }
      let new_obs = Obs(x_fp: m.width * 4, h: h, kind: kind)
      #(list.append(obs, [new_obs]), m.frame + gap)
    }
  }

  // Collision: dino body cols [dino_col+1 .. dino_col+3]
  // Dino clears obstacle when y_fp/4 >= obs.h - 1 (jumped high enough)
  let dino_left = dino_col + 1
  let dino_right = dino_col + 3

  let hit =
    list.any(obs, fn(o) {
      let ox = o.x_fp / 4
      let ow = obs_width(o.kind)
      // x overlap: cactus body overlaps dino body columns
      let x_hit = ox + ow - 1 >= dino_left && ox <= dino_right
      // y overlap: clear when jumped at least obs.h-1 rows above ground
      let y_hit = y_fp / 4 < o.h - 1
      x_hit && y_hit
    })

  let best = int.max(m.best, score)

  case hit {
    True ->
      Model(
        ..m,
        state: Dead,
        y_fp: y_fp,
        vy_fp: 0,
        obs: obs,
        score: score,
        best: best,
      )
    False ->
      Model(
        ..m,
        y_fp: y_fp,
        vy_fp: vy_fp,
        obs: obs,
        frame: m.frame + 1,
        next_obs: next_obs,
        speed: speed,
        score: score,
        best: best,
      )
  }
}

fn do_jump(m: Model) -> Model {
  case m.y_fp == 0 {
    True -> Model(..m, vy_fp: jump_vy)
    False -> m
  }
}

// ─── Span helpers ────────────────────────────────────────────────

fn sp(s: String, c: style.Color) -> span.Span {
  span.span_plain(s) |> span.span_fg(c)
}

fn sp_b(s: String, c: style.Color) -> span.Span {
  sp(s, c) |> span.span_modifier(style.bold())
}

fn row(
  buf: buffer.Buffer,
  x: Int,
  y: Int,
  w: Int,
  spans: List(span.Span),
) -> buffer.Buffer {
  case y < 0 || x < 0 {
    True -> buf
    False ->
      paragraph.render_styled(buf, rect_new(x, y, w, 1), [span.line_new(spans)])
  }
}

fn pad0(n: Int, d: Int) -> String {
  string.pad_start(int.to_string(n), d, "0")
}

// ─── Star sprite (5 wide × 4 tall) ──────────────────────────────
//
//   ★    row 0, top spike  (★/✦ alternating twinkle)
//  ███   row 1, upper body
// ◄███►  row 2, body with left/right spikes
//  ▼ ▼   row 3, lower spikes A  /  ▼   ▼  B

fn draw_dino(
  buf: buffer.Buffer,
  top: Int,
  anim_frame: Int,
  dead: Bool,
) -> buffer.Buffer {
  let c = case dead {
    True -> c_dino_dead
    False -> c_dino
  }
  let tip = case dead {
    True -> "  ✕  "
    False ->
      case anim_frame / 8 % 2 {
        0 -> "  ★  "
        _ -> "  ✦  "
      }
  }
  let legs = case dead {
    True -> " ▼ ▼ "
    False ->
      case anim_frame / 4 % 2 {
        0 -> " ▼ ▼ "
        _ -> "▼   ▼"
      }
  }
  let buf = row(buf, dino_col, top, 6, [sp_b(tip, c)])
  let buf = row(buf, dino_col, top + 1, 6, [sp_b(" ███ ", c)])
  let buf = row(buf, dino_col, top + 2, 6, [sp_b("◄███►", c)])
  row(buf, dino_col, top + 3, 6, [sp_b(legs, c)])
}

// ─── Cactus sprites ──────────────────────────────────────────────
//
// CSpike (1w): pointed narrow spike
//   ▲
//   █
//   █
//
// CSingle (2w): cactus with one arm
//   ▐█
//   ██  ← arm row uses "▐█" or "▐█▌" etc.
//   ██
//
// CBig (3w): branching cactus
//    ▲
//   ▐█▌
//    █
//    █

fn draw_cactus(
  buf: buffer.Buffer,
  col: Int,
  top: Int,
  h: Int,
  kind: CKind,
) -> buffer.Buffer {
  let c = c_cactus
  case kind {
    CSpike ->
      list.fold(irange(h), buf, fn(b, i) {
        let s = case i {
          0 -> "▲"
          _ -> "█"
        }
        row(b, col, top + i, 2, [sp_b(s, c)])
      })

    CSingle ->
      list.fold(irange(h), buf, fn(b, i) {
        // arm appears at the 2nd-from-top row
        let s = case i {
          0 -> "▗█"
          1 -> "▐█"
          _ -> "██"
        }
        row(b, col, top + i, 3, [sp_b(s, c)])
      })

    CBig ->
      list.fold(irange(h), buf, fn(b, i) {
        let s = case i {
          0 -> " ▲ "
          1 -> "▐█▌"
          _ -> " █ "
        }
        row(b, col, top + i, 4, [sp_b(s, c)])
      })
  }
}

// ─── Ground ──────────────────────────────────────────────────────

fn draw_ground(
  buf: buffer.Buffer,
  gr: Int,
  w: Int,
  frame: Int,
) -> buffer.Buffer {
  // Ground line
  let buf = row(buf, 0, gr, w, [sp_b(string.repeat("─", w), c_ground)])
  // Rolling pebbles / terrain below
  let pebbles =
    irange(w)
    |> list.map(fn(i) {
      case prng(i * 13 + frame / 4) % 10 {
        0 -> "·"
        1 -> "▫"
        _ -> " "
      }
    })
    |> string.concat
  row(buf, 0, gr + 1, w, [sp(pebbles, c_dim)])
}

// ─── Clouds ──────────────────────────────────────────────────────

fn draw_clouds(
  buf: buffer.Buffer,
  w: Int,
  h: Int,
  frame: Int,
) -> buffer.Buffer {
  let gr = ground_row(h)
  let x1 = { w * 2 - frame / 5 % w } % w
  let x2 = { w * 3 - frame / 10 % w } % w
  let x3 = { w + w / 2 - frame / 7 % w } % w
  let buf = case x1 + 8 < w {
    True -> row(buf, x1, gr - 10, 9, [sp(" ░▒▒▒░ ", c_cloud)])
    False -> buf
  }
  let buf = case x2 + 7 < w {
    True -> row(buf, x2, gr - 16, 8, [sp("░▒▒▒▒░", c_cloud)])
    False -> buf
  }
  case x3 + 6 < w {
    True -> row(buf, x3, gr - 13, 7, [sp(" ░▒▒░ ", c_cloud)])
    False -> buf
  }
}

// ─── Distant hills ───────────────────────────────────────────────

const mountain_tile = "        ▁▂▃▄▄▃▂▁         ▁▁▂▃▃▂▁▁        ▁▂▄▄▂▁      "

fn draw_mountains(
  buf: buffer.Buffer,
  w: Int,
  h: Int,
  frame: Int,
) -> buffer.Buffer {
  let gr = ground_row(h)
  let y = gr - 3
  case y > 0 {
    False -> buf
    True -> {
      let tlen = string.length(mountain_tile)
      let offset = frame / 25 % tlen
      let full = string.repeat(mountain_tile, w / tlen + 3)
      let line = string.slice(full, offset, w)
      row(buf, 0, y, w, [sp(line, style.Indexed(235))])
    }
  }
}

// ─── Birds ───────────────────────────────────────────────────────

fn draw_birds(buf: buffer.Buffer, w: Int, h: Int, frame: Int) -> buffer.Buffer {
  let gr = ground_row(h)
  let x1 = { w * 3 - frame / 6 % { w + 5 } } % w
  let x2 = { w * 2 - frame / 11 % { w + 8 } } % w
  let y1 = gr - 18
  let y2 = gr - 12
  let c = style.Indexed(240)
  let buf = case y1 > 2 && x1 + 4 < w {
    True -> row(buf, x1, y1, 4, [sp("v v", c)])
    False -> buf
  }
  case y2 > 2 && x2 + 4 < w {
    True -> row(buf, x2, y2, 4, [sp("v v", c)])
    False -> buf
  }
}

// ─── HUD ─────────────────────────────────────────────────────────

fn draw_hud(buf: buffer.Buffer, m: Model) -> buffer.Buffer {
  // Speed as multiplier
  let s10 = m.speed * 10 / initial_speed
  let speed_str =
    "×" <> int.to_string(s10 / 10) <> "." <> int.to_string(s10 % 10)
  // Left: name + speed
  let buf =
    row(buf, 1, 0, 24, [
      sp_b("GATUI DINO", c_dino),
      sp("  " <> speed_str, c_dim),
    ])
  // Right: best + score
  let score_col = int.max(m.width - 26, 28)
  row(buf, score_col, 0, 25, [
    sp("BEST ", c_dim),
    sp_b(pad0(m.best, 5), c_best),
    sp("  SCORE ", c_dim),
    sp_b(pad0(m.score, 5), c_score),
  ])
}

// ─── Obstacles render ────────────────────────────────────────────

fn draw_obs(
  buf: buffer.Buffer,
  obs: List(Obs),
  gr: Int,
  w: Int,
) -> buffer.Buffer {
  list.fold(obs, buf, fn(b, o) {
    let col = o.x_fp / 4
    let ow = obs_width(o.kind)
    case col + ow > 0 && col < w {
      True -> draw_cactus(b, col, gr - o.h, o.h, o.kind)
      False -> b
    }
  })
}

// ─── Screens ─────────────────────────────────────────────────────

fn screen_title(m: Model, frame: Int) -> buffer.Buffer {
  let buf = buffer.buffer_new(rect_new(0, 0, m.width, m.height))
  let gr = ground_row(m.height)
  let buf = draw_mountains(buf, m.width, m.height, frame)
  let buf = draw_clouds(buf, m.width, m.height, frame)
  let buf = draw_birds(buf, m.width, m.height, frame)
  let buf = draw_ground(buf, gr, m.width, frame)
  let buf = draw_dino(buf, gr - dino_h, frame, False)
  // Title
  let cx = int.max(m.width / 2 - 14, 2)
  let ty = gr - 12
  let blink = frame / 8 % 2 == 0
  let buf = row(buf, cx, ty, 30, [sp_b("  ▶  GATUI  DINO  ◀  ", c_dino)])
  let buf =
    row(buf, cx, ty + 1, 30, [sp("  T-Rex runner in the terminal", c_dim)])
  let buf =
    row(buf, cx, ty + 3, 30, [
      case blink {
        True -> sp_b("  ▶  SPACE to start  ◀  ", c_hi)
        False -> sp("  ▶  SPACE to start  ◀  ", c_dim)
      },
    ])
  row(buf, cx, ty + 5, 30, [sp("     ↑ / SPACE  jump  ·  q  quit", c_dim)])
}

fn screen_playing(m: Model, frame: Int) -> buffer.Buffer {
  let buf = buffer.buffer_new(rect_new(0, 0, m.width, m.height))
  let gr = ground_row(m.height)
  let buf = draw_mountains(buf, m.width, m.height, frame)
  let buf = draw_clouds(buf, m.width, m.height, frame)
  let buf = draw_birds(buf, m.width, m.height, frame)
  let buf = draw_hud(buf, m)
  let buf = draw_ground(buf, gr, m.width, frame)
  let buf = draw_obs(buf, m.obs, gr, m.width)
  draw_dino(buf, dino_top(m.height, m.y_fp), frame, False)
}

fn screen_dead(m: Model, frame: Int) -> buffer.Buffer {
  let buf = buffer.buffer_new(rect_new(0, 0, m.width, m.height))
  let gr = ground_row(m.height)
  let buf = draw_mountains(buf, m.width, m.height, frame)
  let buf = draw_clouds(buf, m.width, m.height, frame)
  let buf = draw_birds(buf, m.width, m.height, frame)
  let buf = draw_hud(buf, m)
  let buf = draw_ground(buf, gr, m.width, frame)
  let buf = draw_obs(buf, m.obs, gr, m.width)
  // Dead dino, frozen legs, red color
  let buf = draw_dino(buf, dino_top(m.height, m.y_fp), frame, True)
  // Game over overlay
  let cx = int.max(m.width / 2 - 13, 2)
  let oy = gr - 11
  let blink = frame / 8 % 2 == 0
  let buf = row(buf, cx, oy, 28, [sp_b("  ✖  GAME  OVER  ", c_dino_dead)])
  let buf =
    row(buf, cx, oy + 2, 28, [
      sp("  SCORE  ", c_dim),
      sp_b(pad0(m.score, 5), c_score),
    ])
  let buf =
    row(buf, cx, oy + 3, 28, [
      sp("  BEST   ", c_dim),
      sp_b(pad0(m.best, 5), c_best),
    ])
  row(buf, cx, oy + 5, 28, [
    case blink {
      True -> sp_b("  ▶  R to restart  ◀  ", c_hi)
      False -> sp("  ▶  R to restart  ◀  ", c_dim)
    },
  ])
}

// ─── Render ──────────────────────────────────────────────────────

fn render(m: Model, screen: Rect, anim_st: anim.AnimState) -> buffer.Buffer {
  let m = Model(..m, width: screen.size.width, height: screen.size.height)
  let frame = anim_st.frame
  case m.state {
    Title -> screen_title(m, frame)
    Playing -> screen_playing(m, frame)
    Dead -> screen_dead(m, frame)
  }
}

// ─── Update ──────────────────────────────────────────────────────

fn update(ev: backend.InputEvent, m: Model) -> Model {
  case m.state {
    Title ->
      case ev {
        backend.Resize(w, h) -> Model(..m, width: w, height: h)
        backend.KeyPress(raw) ->
          case keys.match(raw) {
            keys.Char(" ") | keys.Up | keys.Enter -> restart(m)
            keys.Char("q") | keys.Escape | keys.Ctrl("c") ->
              Model(..m, quit: True)
            _ -> m
          }
        _ -> m
      }

    Playing -> {
      let m = tick(m)
      case ev {
        backend.Resize(w, h) -> Model(..m, width: w, height: h)
        backend.KeyPress(raw) ->
          case keys.match(raw) {
            keys.Char(" ") | keys.Up -> do_jump(m)
            keys.Char("q") | keys.Escape | keys.Ctrl("c") ->
              Model(..m, quit: True)
            _ -> m
          }
        _ -> m
      }
    }

    Dead ->
      case ev {
        backend.Resize(w, h) -> Model(..m, width: w, height: h)
        backend.KeyPress(raw) ->
          case keys.match(raw) {
            // Only R restarts, no accidental restart from other keys
            keys.Char("r") -> restart(m)
            keys.Char("q") | keys.Escape | keys.Ctrl("c") ->
              Model(..m, quit: True)
            _ -> m
          }
        _ -> m
      }
  }
}

// ─── Entry point ─────────────────────────────────────────────────

pub fn main() -> Nil {
  let _ =
    app.run_animated(
      default.new(),
      blank_model(),
      render,
      update,
      fn(m) { m.quit },
      50,
    )
  Nil
}
