// Property-based tests for etui/geometry.resolve_sizes.
// Hand-rolled mini quickcheck: deterministic seeds → reproducible CI.
// Properties from ARCHITECTURE.md §11.2.

import etui/geometry
import gleam/list
import gleeunit/should

// ─── PRNG ─────────────────────────────────────────────────────────
// Linear congruential generator. Always returns non-negative value.

fn lcg(seed: Int) -> Int {
  let r = { seed * 1_664_525 + 1_013_904_223 } % 2_147_483_647
  case r < 0 {
    True -> r + 2_147_483_647
    False -> r
  }
}

// ─── Generators ────────────────────────────────────────────────────

fn gen_constraints(seed: Int, n: Int) -> #(List(geometry.Constraint), Int) {
  gen_loop(seed, n, [])
}

fn gen_loop(
  seed: Int,
  n: Int,
  acc: List(geometry.Constraint),
) -> #(List(geometry.Constraint), Int) {
  case n <= 0 {
    True -> #(list.reverse(acc), seed)
    False -> {
      let s1 = lcg(seed)
      let s2 = lcg(s1)
      // s1 picks kind, s2 picks value; s2 advances the seed
      let c = case s1 % 3 {
        0 -> geometry.Length(s2 % 80 + 1)
        1 -> geometry.Percentage(s2 % 100 + 1)
        _ -> geometry.Fill
      }
      gen_loop(s2, n - 1, [c, ..acc])
    }
  }
}

// ─── Properties ────────────────────────────────────────────────────

fn sum_ints(xs: List(Int)) -> Int {
  list.fold(xs, 0, fn(acc, x) { acc + x })
}

fn has_fill(cs: List(geometry.Constraint)) -> Bool {
  list.any(cs, fn(c) { c == geometry.Fill })
}

fn cumsum(xs: List(Int)) -> List(Int) {
  let #(_, rev) =
    list.fold(xs, #(0, []), fn(st, x) {
      let #(cur, acc) = st
      #(cur + x, [cur + x, ..acc])
    })
  list.reverse(rev)
}

fn monotone(a: List(Int), b: List(Int)) -> Bool {
  case a, b {
    [], [] -> True
    [x, ..xs], [y, ..ys] -> y >= x && monotone(xs, ys)
    _, _ -> True
  }
}

// Checks all four invariants from §11.2:
//   len(result) == len(constraints)
//   ∀ s ∈ result: s >= 0
//   sum(result) <= total
//   (∃ Fill) → sum(result) == total
fn prop_invariants(total: Int, cs: List(geometry.Constraint)) -> Bool {
  let sizes = geometry.resolve_sizes(total, cs)
  let sum = sum_ints(sizes)
  let fill_ok = case has_fill(cs) {
    True -> sum == total
    False -> True
  }
  list.length(sizes) == list.length(cs)
  && list.all(sizes, fn(s) { s >= 0 })
  && sum <= total
  && fill_ok
}

// Monotonicity: cumsum(total) ≤ cumsum(total+1) pointwise.
fn prop_monotone(total: Int, cs: List(geometry.Constraint)) -> Bool {
  monotone(
    cumsum(geometry.resolve_sizes(total, cs)),
    cumsum(geometry.resolve_sizes(total + 1, cs)),
  )
}

// ─── Runner ────────────────────────────────────────────────────────

fn run(
  seed: Int,
  iters: Int,
  max_total: Int,
  max_n: Int,
  prop: fn(Int, List(geometry.Constraint)) -> Bool,
) -> Bool {
  run_loop(seed, iters, max_total, max_n, prop)
}

fn run_loop(
  seed: Int,
  rem: Int,
  max_total: Int,
  max_n: Int,
  prop: fn(Int, List(geometry.Constraint)) -> Bool,
) -> Bool {
  case rem <= 0 {
    True -> True
    False -> {
      let s1 = lcg(seed)
      let total = s1 % { max_total + 1 }
      let s2 = lcg(s1)
      let n = s2 % max_n + 1
      let s3 = lcg(s2)
      let #(cs, s4) = gen_constraints(s3, n)
      case prop(total, cs) {
        False -> False
        True -> run_loop(s4, rem - 1, max_total, max_n, prop)
      }
    }
  }
}

// ─── Tests ─────────────────────────────────────────────────────────

pub fn prop_basic_invariants_test() {
  run(42, 500, 1000, 8, prop_invariants)
  |> should.equal(True)
}

pub fn prop_monotone_test() {
  run(137, 500, 500, 6, prop_monotone)
  |> should.equal(True)
}

pub fn prop_invariants_alt_seeds_test() {
  run(7919, 300, 1000, 10, prop_invariants)
  |> should.equal(True)
  run(31_337, 300, 1000, 10, prop_invariants)
  |> should.equal(True)
}

pub fn prop_monotone_alt_seeds_test() {
  run(1234, 300, 500, 8, prop_monotone)
  |> should.equal(True)
  run(99_991, 300, 500, 8, prop_monotone)
  |> should.equal(True)
}

// Edge: total=0 → all zeros regardless of constraints
pub fn prop_zero_total_all_zeros_test() {
  let #(cs, _) = gen_constraints(42, 6)
  geometry.resolve_sizes(0, cs)
  |> list.all(fn(s) { s == 0 })
  |> should.equal(True)
}

// Edge: total<0 → all zeros
pub fn prop_negative_total_all_zeros_test() {
  let #(cs, _) = gen_constraints(99, 5)
  geometry.resolve_sizes(-1, cs)
  |> list.all(fn(s) { s == 0 })
  |> should.equal(True)
}

// Edge: no constraints → []
pub fn prop_empty_constraints_test() {
  list.each([0, 1, 50, 100, 999], fn(total) {
    geometry.resolve_sizes(total, [])
    |> should.equal([])
  })
}

// Edge: single Fill absorbs everything
pub fn prop_single_fill_absorbs_all_test() {
  list.each([0, 1, 50, 100, 200], fn(total) {
    geometry.resolve_sizes(total, [geometry.Fill])
    |> should.equal([total])
  })
}
