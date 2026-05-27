// Node.js terminal backend FFI for etui.
// Key normalization mirrors erlang.gleam's normalise_key so keys.match works
// identically on both targets.

import { Ok, Error } from "../../gleam.mjs";
import {
  KeyPress, Resize, Tick,
  MousePress, MouseRelease, MouseScroll,
  MouseLeft, MouseMiddle, MouseRight,
} from "../backend.mjs";

// ─── State ───────────────────────────────────────────────────────

let rawModeActive = false;
let inputBuffer = [];
let inputResolvers = [];
let resizeQueue = [];
let escapeBuffer = null;
let escapeTimer = null;

// ─── Terminal control ─────────────────────────────────────────────

export function enterRaw() {
  if (process.stdin.isTTY) {
    process.stdin.setRawMode(true);
    process.stdin.resume();
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", onData);
    rawModeActive = true;
  }
}

export function exitRaw() {
  if (rawModeActive && process.stdin.isTTY) {
    process.stdin.removeListener("data", onData);
    process.stdin.setRawMode(false);
    process.stdin.pause();
    rawModeActive = false;
  }
  if (escapeTimer !== null) {
    clearTimeout(escapeTimer);
    escapeTimer = null;
    escapeBuffer = null;
  }
}

export function writeStdout(s) {
  process.stdout.write(s);
}

export function windowSize() {
  const cols = process.stdout.columns || 80;
  const rows = process.stdout.rows || 24;
  return new Ok([cols, rows]);
}

// ─── Resize ───────────────────────────────────────────────────────

process.stdout.on("resize", () => {
  const cols = process.stdout.columns || 80;
  const rows = process.stdout.rows || 24;
  resizeQueue.push([cols, rows]);
  drainResolvers();
});

// ─── Input handling ───────────────────────────────────────────────

function onData(chunk) {
  if (escapeBuffer !== null) {
    // ESC was pending, combine (handles split \x1b + [B → \x1b[B)
    clearTimeout(escapeTimer);
    escapeTimer = null;
    const combined = escapeBuffer + chunk;
    escapeBuffer = null;
    inputBuffer.push(combined);
  } else if (chunk === "\x1b") {
    // Lone ESC: wait 20ms for a follow-up (e.g. "[B" for arrow keys)
    escapeBuffer = chunk;
    escapeTimer = setTimeout(() => {
      escapeBuffer = null;
      escapeTimer = null;
      inputBuffer.push("\x1b");
      drainResolvers();
    }, 20);
    return;
  } else {
    inputBuffer.push(chunk);
  }
  drainResolvers();
}

function drainResolvers() {
  while (inputResolvers.length > 0 && (inputBuffer.length > 0 || resizeQueue.length > 0)) {
    const resolve = inputResolvers.shift();
    resolve(null);
  }
}

// ─── Poll ─────────────────────────────────────────────────────────

export async function pollInput(timeoutMs) {
  if (resizeQueue.length > 0) {
    const [cols, rows] = resizeQueue.shift();
    return new Ok(new Resize(cols, rows));
  }
  if (inputBuffer.length > 0) {
    return new Ok(parseChunk(inputBuffer.shift()));
  }
  const result = await Promise.race([
    new Promise((resolve) => inputResolvers.push(resolve)),
    new Promise((resolve) => setTimeout(() => resolve("timeout"), timeoutMs)),
  ]);
  if (result === "timeout") return new Ok(new Tick());
  if (resizeQueue.length > 0) {
    const [cols, rows] = resizeQueue.shift();
    return new Ok(new Resize(cols, rows));
  }
  if (inputBuffer.length > 0) {
    return new Ok(parseChunk(inputBuffer.shift()));
  }
  return new Ok(new Tick());
}

// ─── Key normalisation (mirrors erlang.gleam normalise_key) ───────

// Map raw terminal bytes to the same friendly strings keys.match expects.
function normaliseKey(raw) {
  switch (raw) {
    // Arrow keys
    case "\x1b[A": case "\x1bOA": return "up";
    case "\x1b[B": case "\x1bOB": return "down";
    case "\x1b[C": case "\x1bOC": return "right";
    case "\x1b[D": case "\x1bOD": return "left";
    // Enter
    case "\r": case "\n": return "enter";
    // Backspace / Delete
    case "\x7f": case "\b": return "backspace";
    case "\x1b[3~": return "delete";
    // Tab / Shift-Tab
    case "\t": return "tab";
    case "\x1b[Z": return "backtab";
    // Escape (lone)
    case "\x1b": return "esc";
    // Navigation
    case "\x1b[2~": return "insert";
    case "\x1b[5~": return "pageup";
    case "\x1b[6~": return "pagedown";
    case "\x1b[H": case "\x1bOH": case "\x1b[1~": return "home";
    case "\x1b[F": case "\x1bOF": case "\x1b[4~": return "end";
    // Function keys
    case "\x1b[11~": case "\x1bOP": return "f1";
    case "\x1b[12~": case "\x1bOQ": return "f2";
    case "\x1b[13~": case "\x1bOR": return "f3";
    case "\x1b[14~": case "\x1bOS": return "f4";
    case "\x1b[15~": return "f5";
    case "\x1b[17~": return "f6";
    case "\x1b[18~": return "f7";
    case "\x1b[19~": return "f8";
    case "\x1b[20~": return "f9";
    case "\x1b[21~": return "f10";
    case "\x1b[23~": return "f11";
    case "\x1b[24~": return "f12";
    // Ctrl+letter (codepoints 0x01–0x1A)
    case "\x01": return "ctrl+a";
    case "\x02": return "ctrl+b";
    case "\x03": return "ctrl+c";
    case "\x04": return "ctrl+d";
    case "\x05": return "ctrl+e";
    case "\x06": return "ctrl+f";
    case "\x07": return "ctrl+g";
    case "\x0b": return "ctrl+k";
    case "\x0c": return "ctrl+l";
    case "\x0e": return "ctrl+n";
    case "\x0f": return "ctrl+o";
    case "\x10": return "ctrl+p";
    case "\x11": return "ctrl+q";
    case "\x12": return "ctrl+r";
    case "\x13": return "ctrl+s";
    case "\x14": return "ctrl+t";
    case "\x15": return "ctrl+u";
    case "\x16": return "ctrl+v";
    case "\x17": return "ctrl+w";
    case "\x18": return "ctrl+x";
    case "\x19": return "ctrl+y";
    case "\x1a": return "ctrl+z";
    default:
      // Alt+letter: ESC + single printable char
      if (raw.length === 2 && raw[0] === "\x1b") return "alt+" + raw[1];
      return raw;
  }
}

// Parse a chunk: SGR mouse or normalised key.
function parseChunk(chunk) {
  if (chunk.startsWith("\x1b[<")) {
    const mouse = parseSgrMouse(chunk.slice(3));
    if (mouse !== null) return mouse;
  }
  return new KeyPress(normaliseKey(chunk));
}

// Parse SGR mouse payload after "\x1b[<": "Cb;Cx;CyM" or "Cb;Cx;Cym"
function parseSgrMouse(payload) {
  const isPress = payload.endsWith("M");
  const trimmed = payload.slice(0, -1);
  const parts = trimmed.split(";");
  if (parts.length !== 3) return null;
  const cb = parseInt(parts[0], 10);
  const cx = parseInt(parts[1], 10);
  const cy = parseInt(parts[2], 10);
  if (isNaN(cb) || isNaN(cx) || isNaN(cy)) return null;
  const x = cx - 1;
  const y = cy - 1;
  if (cb === 64) return new MouseScroll(x, y, true);
  if (cb === 65) return new MouseScroll(x, y, false);
  const btn = [new MouseLeft(), new MouseMiddle(), new MouseRight()][cb % 4] ?? new MouseLeft();
  return isPress ? new MousePress(x, y, btn) : new MouseRelease(x, y, btn);
}

// ─── Crash-restore ────────────────────────────────────────────────

export function registerCleanup(cleanupFn) {
  const handler = () => {
    try { cleanupFn(); } catch (_) {}
    exitRaw();
  };
  process.on("exit", handler);
  process.on("SIGINT", () => { handler(); process.exit(0); });
  process.on("SIGTERM", () => { handler(); process.exit(0); });
}
