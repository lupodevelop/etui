// JS fallback: immutable flat array (copy-on-write).
// Performance is O(N) per set, acceptable for the JS/Node target.

export function make(size, defaultValue) {
  return { data: new Array(size).fill(defaultValue), size, defaultValue };
}

export function get(index, arr) {
  if (index >= 0 && index < arr.size) return arr.data[index];
  return arr.defaultValue;
}

export function set(index, value, arr) {
  const data = arr.data.slice();
  data[index] = value;
  return { data, size: arr.size, defaultValue: arr.defaultValue };
}
