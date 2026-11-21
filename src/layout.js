// Distances are measured in one key pitch. Positive Z faces the typist.
const centerX = 8.1;
const centerZ = 2.67;
export const keys = [];

function row(index, z, entries, left = 0) {
  for (const entry of entries) {
    if (typeof entry === 'number') {
      left += entry;
      continue;
    }
    const [code, label, w = 1, tone = 'ivory', upper = ''] = entry;
    keys.push({ code, label, w, row: index, tone, upper,
      x: left + w / 2 - centerX, z: z - centerZ });
    left += w;
  }
}

row(0, 0, [
  ['Escape', 'esc', 1, 'forest'], .63,
  ...Array.from({ length: 12 }, (_, i) => [
    ...(i === 4 || i === 8 ? [.25] : []),
    ['F' + (i + 1), 'F' + (i + 1), 1, i < 4 || i >= 8 ? 'sage' : 'ivory']
  ]).flat(),
  .07, ['Delete', 'del', 1, 'sage']
]);

row(1, 1.25, [
  ['Backquote', '`', 1, 'ivory', '~'],
  ...'1234567890'.split('').map((n, i) => ['Digit' + n, n, 1, 'ivory', '!@#$%^&*()'[i]]),
  ['Minus', '−', 1, 'ivory', '_'], ['Equal', '=', 1, 'ivory', '+'],
  ['Backspace', 'delete', 2, 'sage', '⌫'], .2, ['Home', 'home', 1, 'mint']
]);
const letters = s => [...s].map(x => ['Key' + x, x]);
row(2, 2.25, [
  ['Tab', 'tab', 1.5, 'sage', '⇥'], ...letters('QWERTYUIOP'),
  ['BracketLeft', '[', 1, 'ivory', '{'], ['BracketRight', ']', 1, 'ivory', '}'],
  ['Backslash', '\\', 1.5, 'ivory', '|'], .2, ['PageUp', 'pg up', 1, 'mint']
]);
row(3, 3.25, [
  ['CapsLock', 'caps lock', 1.75, 'sage', '⇪'], ...letters('ASDFGHJKL'),
  ['Semicolon', ';', 1, 'ivory', ':'], ['Quote', "'", 1, 'ivory', '"'],
  ['Enter', 'return', 2.25, 'forest', '↵'], .2, ['PageDown', 'pg dn', 1, 'mint']
]);
row(4, 4.25, [
  ['ShiftLeft', 'shift', 2.25, 'sage', '⇧'], ...letters('ZXCVBNM'),
  ['Comma', ',', 1, 'ivory', '<'], ['Period', '.', 1, 'ivory', '>'],
  ['Slash', '/', 1, 'ivory', '?'], ['ShiftRight', 'shift', 1.75, 'sage', '⇧'],
  .2, ['ArrowUp', '↑', 1, 'evergreen'], ['End', 'end', 1, 'mint']
]);
row(5, 5.25, [
  ['ControlLeft', 'control', 1.25, 'sage', '⌃'], ['AltLeft', 'option', 1.25, 'sage', '⌥'],
  ['MetaLeft', 'command', 1.25, 'sage', '⌘'], ['Space', 'space', 6.25, 'mint'],
  ['MetaRight', 'command', 1, 'sage', '⌘'], ['AltRight', 'option', 1, 'sage', '⌥'],
  ['ControlRight', 'ctrl', 1, 'sage', '⌃'], .2,
  ['ArrowLeft', '←', 1, 'evergreen'], ['ArrowDown', '↓', 1, 'evergreen'],
  ['ArrowRight', '→', 1, 'evergreen']
]);
