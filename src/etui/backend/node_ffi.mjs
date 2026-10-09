// Node.js terminal backend FFI for etui.
//
// This layer moves bytes and nothing else. Turning bytes into events is
// etui/input's job, which is ordinary Gleam and therefore the same code on
// every target. It used to be reimplemented here in JavaScript, which is how
// the JavaScript target came to be missing modified keys, bracketed paste and
// mouse drags long after the Erlang one had them.

import { toList } from "../../gleam.mjs";

// ─── State ───────────────────────────────────────────────────────

let rawModeActive = false;
let inputBuffer = [];
let inputResolvers = [];
let resizeQueue = [];

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
//
// Chunks are queued exactly as they arrive. A sequence split across two reads
// is handled by the parser, which keeps the incomplete tail and prepends it to
// the next chunk, so there is no need to guess here with a timer.

function onData(chunk) {
  inputBuffer.push(chunk);
  drainResolvers();
}

function drainResolvers() {
  while (inputResolvers.length > 0 && (inputBuffer.length > 0 || resizeQueue.length > 0)) {
    const resolve = inputResolvers.shift();
    resolve(null);
  }
}

// ─── Reading ──────────────────────────────────────────────────────

/// The bytes waiting to be read, or "" if none arrived before the timeout.
export async function readChunk(timeoutMs) {
  if (inputBuffer.length > 0) return inputBuffer.shift();
  if (resizeQueue.length > 0) return "";
  const result = await Promise.race([
    new Promise((resolve) => inputResolvers.push(resolve)),
    new Promise((resolve) => setTimeout(() => resolve("timeout"), timeoutMs)),
  ]);
  if (result === "timeout") return "";
  if (inputBuffer.length > 0) return inputBuffer.shift();
  return "";
}

/// A pending resize as [cols, rows], or [] if there is none. Returned as a
/// list so no Gleam constructors have to be imported here.
export function takeResize() {
  if (resizeQueue.length === 0) return toList([]);
  const [cols, rows] = resizeQueue.shift();
  return toList([cols, rows]);
}

// Hand the terminal back however the process ends.
//
// `restore` is the same byte sequence etui/backend defines for every target,
// passed in rather than spelled out again here. It is written directly, not
// only through `cleanupFn`: cleanup runs when things have already gone wrong,
// and a callback that throws must not be the reason the cursor stays hidden.
//
// Registration is idempotent. Each `app.run` used to add another set of
// listeners, and Node warns and then leaks once eleven pile up.
let cleanupRegistered = false;

export function registerCleanup(cleanupFn, restore) {
  if (cleanupRegistered) return;
  cleanupRegistered = true;

  let done = false;
  const handler = () => {
    if (done) return;
    done = true;
    try { cleanupFn(); } catch (_) {}
    try { process.stdout.write(restore); } catch (_) {}
    exitRaw();
  };

  process.on("exit", handler);
  // 128 + signal number, the convention a shell reads back from $?.
  process.on("SIGINT", () => { handler(); process.exit(130); });
  process.on("SIGTERM", () => { handler(); process.exit(143); });
  process.on("SIGHUP", () => { handler(); process.exit(129); });
}
