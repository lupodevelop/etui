/// Theming system for etui.
///
/// A `Theme` holds semantic color slots (not raw widget colors). Widgets
/// receive a `Theme` and pull the colors they need by name, so switching
/// themes is a one-line change.
///
/// ## Built-in themes
///
/// ```gleam
/// import etui/theme
///
/// let t = theme.dracula()    // dark purple palette, RGB
/// let t = theme.nord()       // arctic dark palette, RGB
/// let t = theme.catppuccin_mocha()  // pastel dark palette, RGB
/// let t = theme.dark()       // generic dark (Indexed, max compatibility)
/// let t = theme.light()      // generic light (Indexed)
/// ```
///
/// ## Using a theme
///
/// ```gleam
/// import etui/theme
///
/// let t = theme.nord()
///
/// // Get a pre-built Style from the theme
/// let sel_style = theme.selection(t)
/// let err_style = theme.error_style(t)
///
/// // Apply to widgets
/// block.block_new()
/// |> block.with_style(t.border, t.bg)
/// |> block.with_title("Panel", block.Top)
///
/// list.list_new(items)
/// |> list.with_highlight_style(theme.selection(t))
/// ```
///
/// ## Custom themes
///
/// ```gleam
/// let my_theme = theme.Theme(
///   bg:            style.Rgb(30, 30, 46),
///   fg:            style.Rgb(205, 214, 244),
///   border:        style.Rgb(137, 180, 250),
///   title:         style.Rgb(166, 227, 161),
///   selection_bg:  style.Rgb(69, 71, 90),
///   selection_fg:  style.Rgb(205, 214, 244),
///   accent:        style.Rgb(137, 180, 250),
///   muted:         style.Rgb(108, 112, 134),
///   error:         style.Rgb(243, 139, 168),
///   warning:       style.Rgb(249, 226, 175),
///   success:       style.Rgb(166, 227, 161),
///   info:          style.Rgb(137, 220, 235),
///   statusbar_bg:  style.Rgb(24, 24, 37),
///   statusbar_fg:  style.Rgb(205, 214, 244),
/// )
/// ```
import etui/style

// ─────────────────────────────────────────────────────────────────
// Theme type

/// Named color slots for a complete UI palette.
pub type Theme {
  Theme(
    /// Main background.
    bg: style.Color,
    /// Main foreground.
    fg: style.Color,
    /// Border lines.
    border: style.Color,
    /// Border titles.
    title: style.Color,
    /// Selected item background.
    selection_bg: style.Color,
    /// Selected item foreground.
    selection_fg: style.Color,
    /// Primary accent (links, highlights, active elements).
    accent: style.Color,
    /// Subdued/secondary text.
    muted: style.Color,
    /// Error messages.
    error: style.Color,
    /// Warnings.
    warning: style.Color,
    /// Success messages.
    success: style.Color,
    /// Informational messages.
    info: style.Color,
    /// Status bar background.
    statusbar_bg: style.Color,
    /// Status bar foreground.
    statusbar_fg: style.Color,
  )
}

// ─────────────────────────────────────────────────────────────────
// Style helpers

/// Normal text: fg on bg.
pub fn normal(t: Theme) -> style.Style {
  style.Style(fg: t.fg, bg: t.bg, modifier: style.none())
}

/// Selected item: selection_fg on selection_bg.
pub fn selection(t: Theme) -> style.Style {
  style.Style(fg: t.selection_fg, bg: t.selection_bg, modifier: style.none())
}

/// Accent text: accent on bg.
pub fn accent_style(t: Theme) -> style.Style {
  style.Style(fg: t.accent, bg: t.bg, modifier: style.none())
}

/// Border color: border on bg.
pub fn border_style(t: Theme) -> style.Style {
  style.Style(fg: t.border, bg: t.bg, modifier: style.none())
}

/// Title color: title on bg.
pub fn title_style(t: Theme) -> style.Style {
  style.Style(fg: t.title, bg: t.bg, modifier: style.none())
}

/// Muted/secondary text: muted on bg.
pub fn muted_style(t: Theme) -> style.Style {
  style.Style(fg: t.muted, bg: t.bg, modifier: style.none())
}

/// Error text: error color on bg, bold.
pub fn error_style(t: Theme) -> style.Style {
  style.Style(fg: t.error, bg: t.bg, modifier: style.bold())
}

/// Warning text: warning color on bg.
pub fn warning_style(t: Theme) -> style.Style {
  style.Style(fg: t.warning, bg: t.bg, modifier: style.none())
}

/// Success text: success color on bg.
pub fn success_style(t: Theme) -> style.Style {
  style.Style(fg: t.success, bg: t.bg, modifier: style.none())
}

/// Info text: info color on bg.
pub fn info_style(t: Theme) -> style.Style {
  style.Style(fg: t.info, bg: t.bg, modifier: style.none())
}

/// Status bar: statusbar_fg on statusbar_bg.
pub fn statusbar_style(t: Theme) -> style.Style {
  style.Style(fg: t.statusbar_fg, bg: t.statusbar_bg, modifier: style.none())
}

// ─────────────────────────────────────────────────────────────────
// Built-in themes

/// Generic dark theme using ANSI 16-color palette.
/// Works on every terminal, even without true-color support.
pub fn dark() -> Theme {
  Theme(
    bg: style.Default,
    fg: style.Default,
    border: style.Indexed(8),
    title: style.Indexed(15),
    selection_bg: style.Indexed(4),
    selection_fg: style.Indexed(15),
    accent: style.Indexed(12),
    muted: style.Indexed(8),
    error: style.Indexed(9),
    warning: style.Indexed(11),
    success: style.Indexed(10),
    info: style.Indexed(14),
    statusbar_bg: style.Indexed(0),
    statusbar_fg: style.Indexed(15),
  )
}

/// Generic light theme using ANSI 16-color palette.
pub fn light() -> Theme {
  Theme(
    bg: style.Default,
    fg: style.Default,
    border: style.Indexed(7),
    title: style.Indexed(0),
    selection_bg: style.Indexed(12),
    selection_fg: style.Indexed(15),
    accent: style.Indexed(4),
    muted: style.Indexed(7),
    error: style.Indexed(1),
    warning: style.Indexed(3),
    success: style.Indexed(2),
    info: style.Indexed(6),
    statusbar_bg: style.Indexed(7),
    statusbar_fg: style.Indexed(0),
  )
}

/// Dracula, dark purple palette.
/// Original palette: https://draculatheme.com
pub fn dracula() -> Theme {
  Theme(
    bg: style.Rgb(40, 42, 54),
    fg: style.Rgb(248, 248, 242),
    border: style.Rgb(98, 114, 164),
    title: style.Rgb(139, 233, 253),
    selection_bg: style.Rgb(68, 71, 90),
    selection_fg: style.Rgb(248, 248, 242),
    accent: style.Rgb(189, 147, 249),
    muted: style.Rgb(98, 114, 164),
    error: style.Rgb(255, 85, 85),
    warning: style.Rgb(255, 184, 108),
    success: style.Rgb(80, 250, 123),
    info: style.Rgb(139, 233, 253),
    statusbar_bg: style.Rgb(33, 34, 44),
    statusbar_fg: style.Rgb(248, 248, 242),
  )
}

/// Nord, arctic, north-bluish dark palette.
/// Original palette: https://www.nordtheme.com
pub fn nord() -> Theme {
  Theme(
    bg: style.Rgb(46, 52, 64),
    fg: style.Rgb(216, 222, 233),
    border: style.Rgb(76, 86, 106),
    title: style.Rgb(136, 192, 208),
    selection_bg: style.Rgb(67, 76, 94),
    selection_fg: style.Rgb(236, 239, 244),
    accent: style.Rgb(129, 161, 193),
    muted: style.Rgb(76, 86, 106),
    error: style.Rgb(191, 97, 106),
    warning: style.Rgb(235, 203, 139),
    success: style.Rgb(163, 190, 140),
    info: style.Rgb(143, 188, 187),
    statusbar_bg: style.Rgb(36, 41, 51),
    statusbar_fg: style.Rgb(216, 222, 233),
  )
}

/// Catppuccin Mocha, warm pastel dark palette.
/// Original palette: https://catppuccin.com
pub fn catppuccin_mocha() -> Theme {
  Theme(
    bg: style.Rgb(30, 30, 46),
    fg: style.Rgb(205, 214, 244),
    border: style.Rgb(88, 91, 112),
    title: style.Rgb(166, 227, 161),
    selection_bg: style.Rgb(69, 71, 90),
    selection_fg: style.Rgb(205, 214, 244),
    accent: style.Rgb(137, 180, 250),
    muted: style.Rgb(108, 112, 134),
    error: style.Rgb(243, 139, 168),
    warning: style.Rgb(249, 226, 175),
    success: style.Rgb(166, 227, 161),
    info: style.Rgb(137, 220, 235),
    statusbar_bg: style.Rgb(24, 24, 37),
    statusbar_fg: style.Rgb(205, 214, 244),
  )
}

/// Catppuccin Latte, warm pastel light palette.
/// Original palette: https://catppuccin.com
pub fn catppuccin_latte() -> Theme {
  Theme(
    bg: style.Rgb(239, 241, 245),
    fg: style.Rgb(76, 79, 105),
    border: style.Rgb(172, 176, 190),
    title: style.Rgb(64, 160, 43),
    selection_bg: style.Rgb(188, 192, 204),
    selection_fg: style.Rgb(76, 79, 105),
    accent: style.Rgb(30, 102, 245),
    muted: style.Rgb(172, 176, 190),
    error: style.Rgb(210, 15, 57),
    warning: style.Rgb(223, 142, 29),
    success: style.Rgb(64, 160, 43),
    info: style.Rgb(4, 165, 229),
    statusbar_bg: style.Rgb(204, 208, 218),
    statusbar_fg: style.Rgb(76, 79, 105),
  )
}

/// Monokai, vibrant dark palette.
/// Inspired by the Monokai color scheme.
pub fn monokai() -> Theme {
  Theme(
    bg: style.Rgb(39, 40, 34),
    fg: style.Rgb(248, 248, 242),
    border: style.Rgb(117, 113, 94),
    title: style.Rgb(166, 226, 46),
    selection_bg: style.Rgb(73, 72, 62),
    selection_fg: style.Rgb(248, 248, 242),
    accent: style.Rgb(102, 217, 239),
    muted: style.Rgb(117, 113, 94),
    error: style.Rgb(249, 38, 114),
    warning: style.Rgb(253, 151, 31),
    success: style.Rgb(166, 226, 46),
    info: style.Rgb(102, 217, 239),
    statusbar_bg: style.Rgb(30, 30, 27),
    statusbar_fg: style.Rgb(248, 248, 242),
  )
}

/// Solarized Dark, precision dark palette.
/// Original palette by Ethan Schoonover.
pub fn solarized_dark() -> Theme {
  Theme(
    bg: style.Rgb(0, 43, 54),
    fg: style.Rgb(131, 148, 150),
    border: style.Rgb(88, 110, 117),
    title: style.Rgb(38, 139, 210),
    selection_bg: style.Rgb(7, 54, 66),
    selection_fg: style.Rgb(147, 161, 161),
    accent: style.Rgb(38, 139, 210),
    muted: style.Rgb(88, 110, 117),
    error: style.Rgb(220, 50, 47),
    warning: style.Rgb(181, 137, 0),
    success: style.Rgb(133, 153, 0),
    info: style.Rgb(42, 161, 152),
    statusbar_bg: style.Rgb(0, 26, 33),
    statusbar_fg: style.Rgb(131, 148, 150),
  )
}

/// Gruvbox Dark, retro groove dark palette.
/// Inspired by the Gruvbox color scheme.
pub fn gruvbox_dark() -> Theme {
  Theme(
    bg: style.Rgb(29, 32, 33),
    fg: style.Rgb(235, 219, 178),
    border: style.Rgb(80, 73, 69),
    title: style.Rgb(184, 187, 38),
    selection_bg: style.Rgb(60, 56, 54),
    selection_fg: style.Rgb(235, 219, 178),
    accent: style.Rgb(215, 153, 33),
    muted: style.Rgb(102, 92, 84),
    error: style.Rgb(251, 73, 52),
    warning: style.Rgb(250, 189, 47),
    success: style.Rgb(184, 187, 38),
    info: style.Rgb(131, 165, 152),
    statusbar_bg: style.Rgb(20, 22, 23),
    statusbar_fg: style.Rgb(235, 219, 178),
  )
}

/// Tokyo Night, dark cool-blue palette.
/// Inspired by the Tokyo Night color scheme.
pub fn tokyo_night() -> Theme {
  Theme(
    bg: style.Rgb(26, 27, 38),
    fg: style.Rgb(169, 177, 214),
    border: style.Rgb(65, 72, 104),
    title: style.Rgb(122, 162, 247),
    selection_bg: style.Rgb(41, 46, 66),
    selection_fg: style.Rgb(192, 202, 245),
    accent: style.Rgb(187, 154, 247),
    muted: style.Rgb(86, 95, 137),
    error: style.Rgb(247, 118, 142),
    warning: style.Rgb(224, 175, 104),
    success: style.Rgb(158, 206, 106),
    info: style.Rgb(125, 207, 255),
    statusbar_bg: style.Rgb(22, 22, 30),
    statusbar_fg: style.Rgb(169, 177, 214),
  )
}

// ─────────────────────────────────────────────────────────────────
// Customisation helpers

/// Override individual fields on an existing theme.
/// Use Gleam's record update syntax directly:
/// ```gleam
/// let my = Theme(..theme.nord(), accent: style.Rgb(255, 165, 0))
/// ```
/// These helpers cover common single-field tweaks.
/// Replace the accent color.
pub fn with_accent(t: Theme, color: style.Color) -> Theme {
  Theme(..t, accent: color)
}

/// Replace the selection colors.
pub fn with_selection(t: Theme, bg: style.Color, fg: style.Color) -> Theme {
  Theme(..t, selection_bg: bg, selection_fg: fg)
}

/// Replace the status bar colors.
pub fn with_statusbar(t: Theme, bg: style.Color, fg: style.Color) -> Theme {
  Theme(..t, statusbar_bg: bg, statusbar_fg: fg)
}

/// Replace main bg/fg.
pub fn with_base(t: Theme, bg: style.Color, fg: style.Color) -> Theme {
  Theme(..t, bg: bg, fg: fg)
}
