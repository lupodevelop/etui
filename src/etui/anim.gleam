import gleam/int
import gleam/list

// ─────────────────────────────────────────────────────────────────
// Animation state

pub type AnimState {
  AnimState(frame: Int)
}

pub fn anim_new() -> AnimState {
  AnimState(frame: 0)
}

pub fn tick(state: AnimState) -> AnimState {
  AnimState(frame: state.frame + 1)
}

pub fn reset(_state: AnimState) -> AnimState {
  AnimState(frame: 0)
}

pub fn is_done(state: AnimState, duration: Int) -> Bool {
  state.frame >= duration
}

// ─────────────────────────────────────────────────────────────────
// Interpolation (integer math only, deterministic on all targets)

/// Linear interpolation from `start` to `end_` over `duration` frames.
pub fn lerp(start: Int, end_: Int, frame: Int, duration: Int) -> Int {
  case duration <= 0 {
    True -> end_
    False -> {
      let t = int.clamp(frame, 0, duration)
      start + { end_ - start } * t / duration
    }
  }
}

/// EaseOut (fast start, slow end). Quadratic approximation with integers.
pub fn ease_out(start: Int, end_: Int, frame: Int, duration: Int) -> Int {
  case duration <= 0 {
    True -> end_
    False -> {
      let t = int.clamp(frame, 0, duration) * 100 / duration
      let curve = t * { 200 - t } / 100
      start + { end_ - start } * curve / 100
    }
  }
}

/// EaseIn (slow start, fast end). Quadratic approximation.
pub fn ease_in(start: Int, end_: Int, frame: Int, duration: Int) -> Int {
  case duration <= 0 {
    True -> end_
    False -> {
      let t = int.clamp(frame, 0, duration) * 100 / duration
      let curve = t * t / 100
      start + { end_ - start } * curve / 100
    }
  }
}

/// Oscillate between `min` and `max` with a given `period` (in frames).
/// Returns current value in the triangle wave.
pub fn oscillate(min: Int, max: Int, frame: Int, period: Int) -> Int {
  case period <= 0 {
    True -> min
    False -> {
      let range = max - min
      let half = period / 2
      let pos = frame % period
      case pos < half {
        True -> min + range * pos / int.max(1, half)
        False -> max - range * { pos - half } / int.max(1, period - half)
      }
    }
  }
}

/// Returns True during the "on" half of each blink period.
/// `period` ≤ 0 means always on.
pub fn blink(frame: Int, period: Int) -> Bool {
  case period <= 0 {
    True -> True
    False -> frame % period < period / 2
  }
}

/// Cycle through [0, count) returning the current index for the given frame.
pub fn cycle(frame: Int, count: Int) -> Int {
  case count <= 0 {
    True -> 0
    False -> frame % count
  }
}

// ─────────────────────────────────────────────────────────────────
// Easing enum

pub type Easing {
  Linear
  EaseIn
  EaseOut
  EaseInOut
}

/// Unified interpolation with selectable easing curve.
pub fn interpolate(
  start: Int,
  end_: Int,
  frame: Int,
  duration: Int,
  easing: Easing,
) -> Int {
  case easing {
    Linear -> lerp(start, end_, frame, duration)
    EaseIn -> ease_in(start, end_, frame, duration)
    EaseOut -> ease_out(start, end_, frame, duration)
    EaseInOut -> ease_in_out(start, end_, frame, duration)
  }
}

/// EaseInOut (slow start, fast middle, slow end). Quadratic approximation.
pub fn ease_in_out(start: Int, end_: Int, frame: Int, duration: Int) -> Int {
  case duration <= 0 {
    True -> end_
    False -> {
      let t = int.clamp(frame, 0, duration) * 100 / duration
      let curve = case t < 50 {
        True -> t * t / 50
        False -> {
          let inv = 100 - t
          100 - inv * inv / 50
        }
      }
      start + { end_ - start } * curve / 100
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Keyframe sequences

pub type Keyframe {
  Keyframe(at: Int, value: Int)
}

/// Interpolate along a keyframe sequence at the given frame.
/// Keyframes are sorted automatically, so order at the call site doesn't matter.
/// Returns the last keyframe value if frame exceeds the sequence.
pub fn sequence(keyframes: List(Keyframe), frame: Int, easing: Easing) -> Int {
  let sorted = list.sort(keyframes, fn(a, b) { int.compare(a.at, b.at) })
  find_segment(sorted, frame, easing)
}

fn find_segment(kfs: List(Keyframe), frame: Int, easing: Easing) -> Int {
  case kfs {
    [] -> 0
    [Keyframe(_, v)] -> v
    [Keyframe(at1, v1), Keyframe(at2, v2), ..rest] ->
      case frame < at2 {
        True -> interpolate(v1, v2, frame - at1, at2 - at1, easing)
        False -> find_segment([Keyframe(at2, v2), ..rest], frame, easing)
      }
  }
}
