/// Pure layout mathematics. Zero dependencies. No terminal knowledge.
/// All functions are deterministic and testable without I/O.
import gleam/int
import gleam/list

/// Coordinate on the screen.
pub type Position {
  Position(x: Int, y: Int)
}

/// Dimensions in cells.
pub type Size {
  Size(width: Int, height: Int)
}

/// A rectangular area on screen.
pub type Rect {
  Rect(position: Position, size: Size)
}

/// How to split a rectangle when laying out widgets.
pub type Direction {
  /// Constraints stacked along X axis (side-by-side columns).
  Horizontal
  /// Constraints stacked along Y axis (rows).
  Vertical
}

/// Layout constraint: how much space to claim.
///
/// Priority (highest → lowest):
///   Length > Min/Max > Ratio/Percentage > Fill
pub type Constraint {
  /// Fixed cell count. Highest priority. Allocated first.
  Length(Int)
  /// At least n cells. Participates in flexible distribution with a floor.
  Min(Int)
  /// At most n cells. Participates in flexible distribution with a ceiling.
  Max(Int)
  /// Percentage of total (0..100). Computed cumulatively to avoid pixel loss.
  Percentage(Int)
  /// Rational fraction of total: numerator/denominator. Exact integer math.
  /// `Ratio(1, 3)` is one-third of the total space.
  Ratio(Int, Int)
  /// Flexible. Divides leftover equally after Length + Percentage + Ratio.
  Fill
}

// ─────────────────────────────────────────────────────────────────
// Constructors

/// Create a Rect with clamped width/height to non-negative.
pub fn rect_new(x: Int, y: Int, width: Int, height: Int) -> Rect {
  Rect(
    position: Position(x: x, y: y),
    size: Size(width: int.max(0, width), height: int.max(0, height)),
  )
}

/// Zero-sized rect at origin.
pub fn rect_zero() -> Rect {
  Rect(position: Position(x: 0, y: 0), size: Size(width: 0, height: 0))
}

// ─────────────────────────────────────────────────────────────────
// Queries

/// X coordinate of the right edge (exclusive: x + width).
pub fn right(rect: Rect) -> Int {
  rect.position.x + rect.size.width
}

/// Y coordinate of the bottom edge (exclusive: y + height).
pub fn bottom(rect: Rect) -> Int {
  rect.position.y + rect.size.height
}

/// Area in cells.
pub fn area(rect: Rect) -> Int {
  rect.size.width * rect.size.height
}

/// Check if a position is inside the rect (inclusive of edges).
pub fn contains(rect: Rect, pos: Position) -> Bool {
  pos.x >= rect.position.x
  && pos.x < right(rect)
  && pos.y >= rect.position.y
  && pos.y < bottom(rect)
}

/// True if terminal cell `(x, y)` is inside `rect`.
/// Convenience wrapper over `contains` for use with mouse event coordinates.
pub fn hit_test(rect: Rect, x: Int, y: Int) -> Bool {
  contains(rect, Position(x: x, y: y))
}

/// Intersection of two rects. Returns the overlapping rect if any.
pub fn intersect(a: Rect, b: Rect) -> Result(Rect, Nil) {
  let left = int.max(a.position.x, b.position.x)
  let top = int.max(a.position.y, b.position.y)
  let right_edge = int.min(right(a), right(b))
  let bottom_edge = int.min(bottom(a), bottom(b))

  case left < right_edge && top < bottom_edge {
    True ->
      Ok(Rect(
        position: Position(x: left, y: top),
        size: Size(width: right_edge - left, height: bottom_edge - top),
      ))
    False -> Error(Nil)
  }
}

/// Union of two rects: smallest rect that contains both.
pub fn union(a: Rect, b: Rect) -> Rect {
  let left = int.min(a.position.x, b.position.x)
  let top = int.min(a.position.y, b.position.y)
  let right_edge = int.max(right(a), right(b))
  let bottom_edge = int.max(bottom(a), bottom(b))

  Rect(
    position: Position(x: left, y: top),
    size: Size(width: right_edge - left, height: bottom_edge - top),
  )
}

// ─────────────────────────────────────────────────────────────────
// Core algorithm: resolve_sizes

/// Distribute total space among constraints.
///
/// Returns a list of sizes (one per constraint) that sum to ≤ total.
/// Sum equals total when Fill (or Min/Max) is present or constraints saturate.
///
/// Algorithm (three-phase Discrete Cumulative Allocation):
/// 1. Length, exact, allocated first. Clamped to remaining budget in order.
/// 2. Percentage + Ratio, proportional from total. Cumulative to prevent jitter.
///    Scaled proportionally if combined demand exceeds available budget.
/// 3. Fill + Min + Max, divide remaining equally.
///    Min applies a floor; Max applies a ceiling. Fill gets equal share.
pub fn resolve_sizes(total: Int, constraints: List(Constraint)) -> List(Int) {
  case total < 0 {
    True -> list.map(constraints, fn(_) { 0 })
    False -> resolve_sizes_impl(total, constraints)
  }
}

fn resolve_sizes_impl(total: Int, constraints: List(Constraint)) -> List(Int) {
  // Phase 1: Length (exact, highest priority)
  let #(length_sizes, length_used) = phase_length(constraints, total, 0, [])
  let prop_budget = int.max(0, total - length_used)

  // Phase 2: Percentage (old cumulative algorithm, preserves stability invariant)
  // Cumulative targets: floor(base * cumsum_pct / denom). Diffs give exact sizes.
  let pct_total_pct =
    list.fold(constraints, 0, fn(acc, c) {
      case c {
        Percentage(p) -> acc + p
        _ -> acc
      }
    })
  let #(denom, pct_base) = case total * pct_total_pct > prop_budget * 100 {
    True -> #(pct_total_pct, prop_budget)
    False -> #(100, total)
  }
  let #(pct_sizes, pct_used) =
    phase_percentage(constraints, denom, pct_base, 0, 0, [])

  // Phase 2b: Ratio, each Ratio(a, b) desires total * a / b cells.
  // Uses demand-based cumulative scaling, allocated from budget after Percentage.
  let ratio_budget = int.max(0, prop_budget - pct_used)
  let ratio_demands =
    list.map(constraints, fn(c) {
      case c {
        Ratio(a, b) ->
          case b {
            0 -> 0
            _ -> total * a / b
          }
        _ -> 0
      }
    })
  let total_ratio_demand = list.fold(ratio_demands, 0, fn(acc, d) { acc + d })
  let #(ratio_sizes, ratio_used) =
    phase_proportional(
      ratio_demands,
      ratio_budget,
      total_ratio_demand,
      0,
      0,
      [],
    )

  // Phase 3: Fill + Min + Max (flexible, divide remaining)
  let flex_budget = int.max(0, total - length_used - pct_used - ratio_used)
  let flex_count =
    list.count(constraints, fn(c) {
      case c {
        Fill | Min(_) | Max(_) -> True
        _ -> False
      }
    })
  let flex_sizes = phase_flex(constraints, flex_count, flex_budget, 0, [])

  assemble_sizes(
    constraints,
    length_sizes,
    pct_sizes,
    ratio_sizes,
    flex_sizes,
    [],
  )
}

fn phase_length(
  constraints: List(Constraint),
  total: Int,
  used: Int,
  acc: List(Int),
) -> #(List(Int), Int) {
  case constraints {
    [] -> #(list.reverse(acc), used)
    [c, ..rest] -> {
      let #(size, new_used) = case c {
        Length(v) -> {
          let take = int.min(v, int.max(0, total - used))
          #(take, used + take)
        }
        _ -> #(0, used)
      }
      phase_length(rest, total, new_used, [size, ..acc])
    }
  }
}

// Old cumulative Percentage algorithm. Preserves the stability invariant:
// sum(pct_sizes) = floor(base * total_pct / denom). Rounding goes to last element.
fn phase_percentage(
  constraints: List(Constraint),
  denom: Int,
  base: Int,
  acc_pct: Int,
  prev_target: Int,
  acc: List(Int),
) -> #(List(Int), Int) {
  case constraints {
    [] -> #(list.reverse(acc), prev_target)
    [c, ..rest] -> {
      let #(size, new_acc, new_target) = case c {
        Percentage(p) -> {
          let new_acc_pct = acc_pct + p
          let target = case denom {
            0 -> 0
            _ -> base * new_acc_pct / denom
          }
          let s = target - prev_target
          #(s, new_acc_pct, target)
        }
        _ -> #(0, acc_pct, prev_target)
      }
      phase_percentage(rest, denom, base, new_acc, new_target, [size, ..acc])
    }
  }
}

// Cumulative proportional allocation. Prevents pixel-loss jitter.
// When total_demand <= budget: uses demands as-is (no scaling).
// When total_demand > budget: scales proportionally via cumulative targets.
fn phase_proportional(
  demands: List(Int),
  budget: Int,
  total_demand: Int,
  cumsum: Int,
  prev_target: Int,
  acc: List(Int),
) -> #(List(Int), Int) {
  case demands {
    [] -> #(list.reverse(acc), prev_target)
    [d, ..rest] -> {
      let new_cumsum = cumsum + d
      let target = case total_demand {
        0 -> 0
        _ ->
          case total_demand <= budget {
            True -> new_cumsum
            False -> budget * new_cumsum / total_demand
          }
      }
      let size = target - prev_target
      phase_proportional(rest, budget, total_demand, new_cumsum, target, [
        size,
        ..acc
      ])
    }
  }
}

// Flexible allocation for Fill, Min, Max.
// Two-sub-pass algorithm so Fill always consumes the full budget:
//   1) Compute each Min/Max's effective size at base share.
//   2) Distribute remaining budget equally among Fill constraints.
// This guarantees sum(flex_sizes) = budget (before build_rects clamping).
fn phase_flex(
  constraints: List(Constraint),
  flex_count: Int,
  budget: Int,
  _idx: Int,
  _acc: List(Int),
) -> List(Int) {
  case flex_count {
    0 -> list.map(constraints, fn(_) { 0 })
    _ -> {
      let base = budget / flex_count
      // Sub-pass 1: compute total claimed by Min/Max at their effective sizes.
      let min_max_used =
        list.fold(constraints, 0, fn(acc, c) {
          case c {
            Min(n) -> acc + int.max(n, base)
            Max(n) -> acc + int.min(n, base)
            _ -> acc
          }
        })
      let fill_count =
        list.count(constraints, fn(c) {
          case c {
            Fill -> True
            _ -> False
          }
        })
      let fill_budget = int.max(0, budget - min_max_used)
      let fill_base = case fill_count {
        0 -> 0
        _ -> fill_budget / fill_count
      }
      let fill_rem = case fill_count {
        0 -> 0
        _ -> fill_budget % fill_count
      }
      // Sub-pass 2: assign sizes.
      let #(sizes, _) =
        list.fold(constraints, #([], 0), fn(state, c) {
          let #(acc, fill_idx) = state
          let #(size, new_fill_idx) = case c {
            Fill -> {
              let s = case fill_idx < fill_rem {
                True -> fill_base + 1
                False -> fill_base
              }
              #(s, fill_idx + 1)
            }
            Min(n) -> #(int.max(n, base), fill_idx)
            Max(n) -> #(int.min(n, base), fill_idx)
            _ -> #(0, fill_idx)
          }
          #([size, ..acc], new_fill_idx)
        })
      list.reverse(sizes)
    }
  }
}

fn assemble_sizes(
  constraints: List(Constraint),
  length_sizes: List(Int),
  pct_sizes: List(Int),
  ratio_sizes: List(Int),
  flex_sizes: List(Int),
  acc: List(Int),
) -> List(Int) {
  case constraints {
    [] -> list.reverse(acc)
    [c, ..cs] -> {
      let size = pick_size(c, length_sizes, pct_sizes, ratio_sizes, flex_sizes)
      let ls = case length_sizes {
        [_, ..t] -> t
        _ -> []
      }
      let ps = case pct_sizes {
        [_, ..t] -> t
        _ -> []
      }
      let rs = case ratio_sizes {
        [_, ..t] -> t
        _ -> []
      }
      let fs = case flex_sizes {
        [_, ..t] -> t
        _ -> []
      }
      assemble_sizes(cs, ls, ps, rs, fs, [size, ..acc])
    }
  }
}

fn pick_size(
  constraint: Constraint,
  lengths: List(Int),
  pcts: List(Int),
  ratios: List(Int),
  flexes: List(Int),
) -> Int {
  case constraint {
    Length(_) ->
      case lengths {
        [h, ..] -> h
        _ -> 0
      }
    Percentage(_) ->
      case pcts {
        [h, ..] -> h
        _ -> 0
      }
    Ratio(_, _) ->
      case ratios {
        [h, ..] -> h
        _ -> 0
      }
    Fill | Min(_) | Max(_) ->
      case flexes {
        [h, ..] -> h
        _ -> 0
      }
  }
}

// ─────────────────────────────────────────────────────────────────
// Layout: split a rect by constraints

/// Split horizontally (columns side-by-side). Shorthand for `split(Horizontal, ...)`.
pub fn split_h(area: Rect, constraints: List(Constraint)) -> List(Rect) {
  split(Horizontal, area, constraints)
}

/// Split vertically (rows stacked). Shorthand for `split(Vertical, ...)`.
pub fn split_v(area: Rect, constraints: List(Constraint)) -> List(Rect) {
  split(Vertical, area, constraints)
}

/// Center a rect of `width × height` within `area`.
/// Clamps to area bounds. Common for popup placement.
///
/// ```gleam
/// let popup_area = geometry.centered_rect(60, 20, screen)
/// ```
pub fn centered_rect(width: Int, height: Int, area: Rect) -> Rect {
  let w = int.min(width, area.size.width)
  let h = int.min(height, area.size.height)
  let x = area.position.x + { area.size.width - w } / 2
  let y = area.position.y + { area.size.height - h } / 2
  Rect(position: Position(x: x, y: y), size: Size(width: w, height: h))
}

/// Center a rect sized as a percentage of `area` (`pct_w` and `pct_h` are 0–100).
/// Useful for responsive popup sizing:
///
/// ```gleam
/// let popup_area = geometry.percent_rect(60, 40, screen)  // 60% wide, 40% tall
/// ```
pub fn percent_rect(pct_w: Int, pct_h: Int, area: Rect) -> Rect {
  let w = area.size.width * int.clamp(pct_w, 0, 100) / 100
  let h = area.size.height * int.clamp(pct_h, 0, 100) / 100
  centered_rect(w, h, area)
}

/// Split a rect along a direction by applying constraints.
pub fn split(
  direction: Direction,
  area: Rect,
  constraints: List(Constraint),
) -> List(Rect) {
  let total = case direction {
    Vertical -> area.size.height
    Horizontal -> area.size.width
  }

  let sizes = resolve_sizes(total, constraints)

  build_rects(direction, area, sizes, 0, [])
}

fn build_rects(
  direction: Direction,
  area: Rect,
  sizes: List(Int),
  cursor: Int,
  acc: List(Rect),
) -> List(Rect) {
  let limit = case direction {
    Vertical -> area.size.height
    Horizontal -> area.size.width
  }
  case sizes {
    [] -> list.reverse(acc)
    [size, ..rest] -> {
      // Clamp so no child Rect extends past the parent boundary.
      // This guards against over-budget Min/Max constraints.
      let start = int.min(cursor, limit)
      let clamped = int.min(size, int.max(0, limit - start))
      let rect = case direction {
        Vertical ->
          Rect(
            position: Position(x: area.position.x, y: area.position.y + start),
            size: Size(width: area.size.width, height: clamped),
          )
        Horizontal ->
          Rect(
            position: Position(x: area.position.x + start, y: area.position.y),
            size: Size(width: clamped, height: area.size.height),
          )
      }
      build_rects(direction, area, rest, start + clamped, [rect, ..acc])
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Layout with spacing

/// Split a rect with `spacing` cells of gap between each child.
/// Gap cells are taken from the total before distributing to constraints.
///
/// ```gleam
/// // Two columns with a 1-cell gap
/// split_with_spacing(Horizontal, area, [Fill, Fill], 1)
/// ```
pub fn split_with_spacing(
  direction: Direction,
  area: Rect,
  constraints: List(Constraint),
  spacing: Int,
) -> List(Rect) {
  let n = list.length(constraints)
  case n <= 1 {
    True -> split(direction, area, constraints)
    False -> {
      let gap_total = int.max(0, spacing) * { n - 1 }
      let total = case direction {
        Vertical -> area.size.height
        Horizontal -> area.size.width
      }
      let available = int.max(0, total - gap_total)
      let sizes = resolve_sizes(available, constraints)
      build_rects_spaced(direction, area, sizes, int.max(0, spacing), 0, [])
    }
  }
}

fn build_rects_spaced(
  direction: Direction,
  area: Rect,
  sizes: List(Int),
  spacing: Int,
  cursor: Int,
  acc: List(Rect),
) -> List(Rect) {
  let limit = case direction {
    Vertical -> area.size.height
    Horizontal -> area.size.width
  }
  case sizes {
    [] -> list.reverse(acc)
    [size, ..rest] -> {
      let start = int.min(cursor, limit)
      let clamped = int.min(size, int.max(0, limit - start))
      let rect = case direction {
        Vertical ->
          Rect(
            position: Position(x: area.position.x, y: area.position.y + start),
            size: Size(width: area.size.width, height: clamped),
          )
        Horizontal ->
          Rect(
            position: Position(x: area.position.x + start, y: area.position.y),
            size: Size(width: clamped, height: area.size.height),
          )
      }
      let next_cursor = case rest {
        [] -> start + clamped
        _ -> start + clamped + spacing
      }
      build_rects_spaced(direction, area, rest, spacing, next_cursor, [
        rect,
        ..acc
      ])
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Flex layout

/// How to distribute leftover space among children in a flex layout.
///
/// | Justify      | Description                                             |
/// |--------------|----------------------------------------------------------|
/// | `FlexStart`  | Pack children at the start; leftover space at the end.  |
/// | `FlexEnd`    | Pack children at the end; leftover space at the start.  |
/// | `FlexCenter` | Center children; leftover space split evenly on both sides. |
/// | `FlexBetween`| Children spread out; space between them (none at edges). |
/// | `FlexAround` | Equal space around each child (half at edges).          |
pub type FlexJustify {
  FlexStart
  FlexEnd
  FlexCenter
  FlexBetween
  FlexAround
}

/// Flex layout: children have fixed sizes (from constraints), leftover space
/// distributed according to `justify`. Use for toolbars, status bars, centering
/// a widget in a larger area, or equal-gap grids.
///
/// `gap` is the minimum gap between children (cells). Ignored when `justify`
/// provides its own spacing (Between/Around). With `FlexStart`/`End`/`Center`,
/// `gap` acts like `split_with_spacing`'s spacing parameter.
///
/// ```gleam
/// // Center a 20-wide widget in a 80-wide area:
/// split_flex(Horizontal, area, [Length(20)], FlexCenter, 0)
///
/// // Three buttons with 2-cell gap between:
/// split_flex(Horizontal, area, [Length(10), Length(10), Length(10)], FlexStart, 2)
///
/// // Toolbar: left item + right item, space between:
/// split_flex(Horizontal, area, [Length(10), Length(10)], FlexBetween, 0)
/// ```
pub fn split_flex(
  direction: Direction,
  area: Rect,
  constraints: List(Constraint),
  justify: FlexJustify,
  gap: Int,
) -> List(Rect) {
  let n = list.length(constraints)
  case n == 0 {
    True -> []
    False -> {
      let total = case direction {
        Vertical -> area.size.height
        Horizontal -> area.size.width
      }
      let gap_cells = int.max(0, gap) * int.max(0, n - 1)
      let available = int.max(0, total - gap_cells)
      let sizes = resolve_sizes(available, constraints)
      let content_width =
        list.fold(sizes, 0, fn(acc, s) { acc + s }) + gap_cells
      let leftover = int.max(0, total - content_width)
      let offsets = flex_offsets(sizes, justify, gap, leftover, n)
      build_flex_rects(direction, area, sizes, offsets, [])
    }
  }
}

fn flex_offsets(
  sizes: List(Int),
  justify: FlexJustify,
  gap: Int,
  leftover: Int,
  n: Int,
) -> List(Int) {
  case justify {
    FlexStart -> start_offsets(sizes, gap, 0, [])
    FlexEnd -> start_offsets(sizes, gap, leftover, [])
    FlexCenter -> start_offsets(sizes, gap, leftover / 2, [])
    FlexBetween -> between_offsets(sizes, leftover, n, 0, [])
    FlexAround -> around_offsets(sizes, leftover, n, 0, [])
  }
}

fn start_offsets(
  sizes: List(Int),
  gap: Int,
  start: Int,
  acc: List(Int),
) -> List(Int) {
  case sizes {
    [] -> list.reverse(acc)
    [s, ..rest] -> {
      let next = start + s + gap
      start_offsets(rest, gap, next, [start, ..acc])
    }
  }
}

fn between_offsets(
  sizes: List(Int),
  leftover: Int,
  n: Int,
  cursor: Int,
  acc: List(Int),
) -> List(Int) {
  let gaps = int.max(1, n - 1)
  let gap_size = case gaps {
    0 -> 0
    _ -> leftover / gaps
  }
  case sizes {
    [] -> list.reverse(acc)
    [s, ..rest] -> {
      let next = cursor + s + gap_size
      between_offsets(rest, leftover, n, next, [cursor, ..acc])
    }
  }
}

fn around_offsets(
  sizes: List(Int),
  leftover: Int,
  n: Int,
  cursor: Int,
  acc: List(Int),
) -> List(Int) {
  let slot = case n {
    0 -> 0
    _ -> leftover / n
  }
  let half = slot / 2
  case sizes {
    [] -> list.reverse(acc)
    [s, ..rest] -> {
      let pos = cursor + half
      let next = pos + s + half + slot % 2
      around_offsets(rest, leftover, n, next, [pos, ..acc])
    }
  }
}

fn build_flex_rects(
  direction: Direction,
  area: Rect,
  sizes: List(Int),
  offsets: List(Int),
  acc: List(Rect),
) -> List(Rect) {
  case sizes, offsets {
    [], _ | _, [] -> list.reverse(acc)
    [size, ..rest_s], [offset, ..rest_o] -> {
      let rect = case direction {
        Vertical ->
          Rect(
            position: Position(x: area.position.x, y: area.position.y + offset),
            size: Size(width: area.size.width, height: size),
          )
        Horizontal ->
          Rect(
            position: Position(x: area.position.x + offset, y: area.position.y),
            size: Size(width: size, height: area.size.height),
          )
      }
      build_flex_rects(direction, area, rest_s, rest_o, [rect, ..acc])
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Responsive layout

/// A responsive breakpoint: applies `constraints` when `area` width >= `min_width`.
pub type Breakpoint {
  Breakpoint(min_width: Int, constraints: List(Constraint))
}

/// Split `area` horizontally using the first breakpoint whose `min_width` <=
/// `area.size.width`, evaluated in descending order. Falls back to the last
/// breakpoint (assumed smallest). Returns `[area]` if `breakpoints` is empty.
///
/// Example, two columns on wide screens, stacked on narrow:
/// ```gleam
/// geometry.split_responsive(area, [
///   geometry.Breakpoint(80, [Percentage(50), Percentage(50)]),
///   geometry.Breakpoint(0,  [Percentage(100)]),
/// ])
/// ```
pub fn split_responsive(
  area: Rect,
  breakpoints: List(Breakpoint),
) -> List(Rect) {
  case breakpoints {
    [] -> [area]
    _ -> {
      let sorted =
        list.sort(breakpoints, fn(a, b) {
          int.compare(b.min_width, a.min_width)
        })
      let chosen = pick_breakpoint(sorted, area.size.width)
      split_h(area, chosen)
    }
  }
}

fn pick_breakpoint(
  sorted_desc: List(Breakpoint),
  width: Int,
) -> List(Constraint) {
  case sorted_desc {
    [] -> []
    [bp] -> bp.constraints
    [bp, ..rest] ->
      case width >= bp.min_width {
        True -> bp.constraints
        False -> pick_breakpoint(rest, width)
      }
  }
}
