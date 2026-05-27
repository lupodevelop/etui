/// Toast notification overlay widget.
///
/// Displays timed notifications stacked in a corner of the screen.
/// Advance time each frame with `tick/1`; expired notifications are removed.
///
/// ```gleam
/// import etui/widgets/notification as notif
///
/// // In your model:
/// let queue = notif.queue_new(max: 5)
///
/// // Push a message (ttl = frames to show):
/// let queue = notif.push(queue, notif.info("File saved", ttl: 60))
///
/// // In update (once per frame):
/// let queue = notif.tick(queue)
///
/// // In render:
/// notif.render(buf, screen_area, queue)
/// ```
import etui/buffer
import etui/geometry
import etui/style
import etui/text
import etui/widgets/block
import gleam/list

// ─────────────────────────────────────────────────────────────────
// Types

/// Notification severity level.
pub type Level {
  Info
  Success
  Warning
  Error
}

/// A single notification.
pub type Notification {
  Notification(
    message: String,
    level: Level,
    /// Remaining ticks before expiry. 0 = expired, -1 = persistent.
    ttl: Int,
  )
}

/// Active notification queue.
pub type NotificationQueue {
  NotificationQueue(
    items: List(Notification),
    /// Maximum simultaneous notifications shown (oldest dropped first).
    max: Int,
    /// Corner to stack notifications in.
    corner: Corner,
  )
}

/// Which screen corner to render notifications in.
pub type Corner {
  TopRight
  TopLeft
  BottomRight
  BottomLeft
}

// ─────────────────────────────────────────────────────────────────
// Constructors

/// New empty queue. Max = 5, corner = BottomRight.
pub fn queue_new(max max: Int) -> NotificationQueue {
  NotificationQueue(items: [], max: max, corner: BottomRight)
}

/// Set which corner to stack notifications.
pub fn with_corner(q: NotificationQueue, corner: Corner) -> NotificationQueue {
  NotificationQueue(..q, corner: corner)
}

/// Build an Info notification.
pub fn info(message: String, ttl ttl: Int) -> Notification {
  Notification(message: message, level: Info, ttl: ttl)
}

/// Build a Success notification.
pub fn success(message: String, ttl ttl: Int) -> Notification {
  Notification(message: message, level: Success, ttl: ttl)
}

/// Build a Warning notification.
pub fn warning(message: String, ttl ttl: Int) -> Notification {
  Notification(message: message, level: Warning, ttl: ttl)
}

/// Build an Error notification (persistent by default: ttl = -1).
pub fn error(message: String, ttl ttl: Int) -> Notification {
  Notification(message: message, level: Error, ttl: ttl)
}

/// Persistent notification (never auto-expires; dismiss manually).
pub fn persistent(message: String, level: Level) -> Notification {
  Notification(message: message, level: level, ttl: -1)
}

// ─────────────────────────────────────────────────────────────────
// Queue operations

/// Add a notification. If queue is full, the oldest is dropped.
pub fn push(q: NotificationQueue, n: Notification) -> NotificationQueue {
  let items = list.append(q.items, [n])
  let trimmed = case list.length(items) > q.max {
    True -> list.drop(items, list.length(items) - q.max)
    False -> items
  }
  NotificationQueue(..q, items: trimmed)
}

/// Advance time by one tick. Decrements TTL on all non-persistent
/// notifications and removes expired ones (ttl == 0).
pub fn tick(q: NotificationQueue) -> NotificationQueue {
  let items =
    q.items
    |> list.map(fn(n) {
      case n.ttl {
        -1 -> n
        t -> Notification(..n, ttl: t - 1)
      }
    })
    |> list.filter(fn(n) { n.ttl != 0 })
  NotificationQueue(..q, items: items)
}

/// Dismiss all notifications matching `level`.
pub fn dismiss_level(q: NotificationQueue, level: Level) -> NotificationQueue {
  NotificationQueue(
    ..q,
    items: list.filter(q.items, fn(n) { n.level != level }),
  )
}

/// Dismiss all notifications.
pub fn dismiss_all(q: NotificationQueue) -> NotificationQueue {
  NotificationQueue(..q, items: [])
}

/// Dismiss the oldest notification.
pub fn dismiss_first(q: NotificationQueue) -> NotificationQueue {
  case q.items {
    [] -> q
    [_, ..rest] -> NotificationQueue(..q, items: rest)
  }
}

/// True if there are active notifications.
pub fn has_notifications(q: NotificationQueue) -> Bool {
  !list.is_empty(q.items)
}

/// Count of active notifications.
pub fn count(q: NotificationQueue) -> Int {
  list.length(q.items)
}

// ─────────────────────────────────────────────────────────────────
// Rendering

/// Render all active notifications stacked in the configured corner.
/// Each notification is a single-row bordered box; they stack inward.
pub fn render(
  buf: buffer.Buffer,
  area: geometry.Rect,
  q: NotificationQueue,
) -> buffer.Buffer {
  case list.is_empty(q.items) || area.size.width <= 0 || area.size.height <= 0 {
    True -> buf
    False -> render_items(buf, area, q.items, q.corner, 0)
  }
}

fn render_items(
  buf: buffer.Buffer,
  area: geometry.Rect,
  items: List(Notification),
  corner: Corner,
  index: Int,
) -> buffer.Buffer {
  case items {
    [] -> buf
    [n, ..rest] -> {
      let box_h = 3
      let msg_w = text.cell_width(n.message)
      let box_w = case msg_w + 4 > 30 {
        True ->
          case msg_w + 4 > area.size.width {
            True -> area.size.width
            False -> msg_w + 4
          }
        False -> 30
      }

      let #(x, y) = case corner {
        TopRight -> #(
          area.position.x + area.size.width - box_w,
          area.position.y + index * box_h,
        )
        TopLeft -> #(area.position.x, area.position.y + index * box_h)
        BottomRight -> #(
          area.position.x + area.size.width - box_w,
          area.position.y + area.size.height - box_h - index * box_h,
        )
        BottomLeft -> #(
          area.position.x,
          area.position.y + area.size.height - box_h - index * box_h,
        )
      }

      let fits =
        x >= area.position.x
        && y >= area.position.y
        && x + box_w <= area.position.x + area.size.width
        && y + box_h <= area.position.y + area.size.height

      let buf2 = case fits {
        False -> buf
        True -> {
          let box_area =
            geometry.Rect(
              position: geometry.Position(x: x, y: y),
              size: geometry.Size(width: box_w, height: box_h),
            )
          let #(fg, bg) = level_colors(n.level)
          let blk =
            block.block_new()
            |> block.with_border(block.Rounded)
            |> block.with_style(fg, bg)
            |> block.with_bg_fill
          let buf_b = block.render(buf, box_area, blk)
          let inner = block.inner(box_area, blk)
          let msg_x =
            inner.position.x
            + { inner.size.width - text.cell_width(n.message) }
            / 2
          case inner.size.width > 0 && inner.size.height > 0 {
            False -> buf_b
            True ->
              buffer.set_string(
                buf_b,
                geometry.Position(x: msg_x, y: inner.position.y),
                text.truncate(n.message, inner.size.width, "…"),
                fg,
                bg,
                style.none(),
              )
          }
        }
      }

      render_items(buf2, area, rest, corner, index + 1)
    }
  }
}

fn level_colors(level: Level) -> #(style.Color, style.Color) {
  case level {
    Info -> #(style.Indexed(15), style.Indexed(4))
    Success -> #(style.Indexed(15), style.Indexed(2))
    Warning -> #(style.Indexed(0), style.Indexed(3))
    Error -> #(style.Indexed(15), style.Indexed(1))
  }
}
