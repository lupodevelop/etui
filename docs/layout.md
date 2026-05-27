# Layout

Layout is pure math in `etui/geometry`. No rendering, no dependencies on the rest of etui.

## Rect

```gleam
import etui/geometry.{Position, Rect, Size}

let area = geometry.rect_new(0, 0, 80, 24)
// or
let area = Rect(position: Position(x: 0, y: 0), size: Size(width: 80, height: 24))
```

Rects don't overlap by default. The layout system produces non-overlapping children from a parent.

## Constraints

```gleam
import etui/geometry.{Fill, Length, Max, Min, Percentage, Ratio}

Length(20)       // exactly 20 cells, highest priority, allocated first
Min(10)          // at least 10 cells, joins the flexible pool
Max(40)          // at most 40 cells, joins the flexible pool
Percentage(30)   // 30% of total, cumulative, no jitter
Ratio(1, 3)      // one third of total, exact integer arithmetic
Fill             // remaining space after all other constraints
```

### Allocation order (highest to lowest priority)

1. **`Length`** is exact and clamped in order. It never gives up space.
2. **`Percentage`** is cumulative: `floor(total * cumsum_pct / 100)`. It scales down proportionally when the percentages sum past 100%.
3. **`Ratio(a, b)`** wants `total * a / b` cells, taken from the budget left after Percentage. It also scales down on overflow.
4. **`Fill`, `Min`, `Max`** split whatever remains. `Min(n)` sets a floor, `Max(n)` sets a ceiling, `Fill` takes an equal share of the rest.

When `Max` caps a slot below its equal share, the surplus goes to the `Fill` slots. The flexible pass runs in two sub-passes so `Fill` always consumes the full remaining budget.

## Split

```gleam
import etui/geometry.{Horizontal, Vertical}

// Split horizontally into three columns
let cols = geometry.split(Horizontal, area, [Length(20), Percentage(50), Fill])
// => List(Rect) with non-overlapping positioned Rects

// Split vertically into a header and content area
let rows = geometry.split(Vertical, area, [Length(3), Fill])

let header = case rows { [h, ..] -> h _ -> area }
let content = case rows { [_, c, ..] -> c _ -> area }
```

`split` always returns exactly as many `Rect`s as constraints given.

## resolve_sizes

```gleam
geometry.resolve_sizes(100, [Length(20), Percentage(30), Fill])
// => [20, 30, 50]

// Percentage overflow scales down
geometry.resolve_sizes(100, [Percentage(60), Percentage(60)])
// => [50, 50]

// Ratio: exact fraction
geometry.resolve_sizes(90, [Ratio(1, 3), Fill])
// => [30, 60]

// Min: at least n
geometry.resolve_sizes(100, [Length(80), Min(30)])
// => [80, 30]  (Min gets its floor even beyond budget)

// Max: at most n
geometry.resolve_sizes(100, [Max(30), Fill])
// => [30, 50]  (Max capped, Fill gets its base share)
```

Returns integer sizes (cell counts), not `Rect`s. Useful when you need sizes without positions.

## No-jitter guarantee

Sizes are computed from cumulative boundaries, not individual widths. Resizing one column doesn't shift others due to floating-point rounding.

## Spacing between splits

```gleam
// 1-cell gap between each column
geometry.split_with_spacing(Horizontal, area, [Fill, Fill, Fill], 1)

// 2-cell gap between rows
geometry.split_with_spacing(Vertical, area, [Length(3), Fill], 2)
```

Gap cells are subtracted from the total before constraints are applied. With spacing, the positioned rects skip the gap columns/rows.

## Rect helpers

```gleam
geometry.intersect(a, b)    // overlap Rect (Error(Nil) if no intersection)
geometry.union(a, b)        // bounding Rect
geometry.contains(r, pos)   // True if Position is inside Rect
```

## Nested layouts

```gleam
let [header, body] = geometry.split(Vertical, screen, [Length(1), Fill])
let [sidebar, main] = geometry.split(Horizontal, body, [Length(20), Fill])
```

Compose splits freely: each call takes a `Rect` and returns child `Rect`s at absolute positions.
