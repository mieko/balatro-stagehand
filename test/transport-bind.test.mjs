import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';

test('transport handles loopback families, port conflicts and stalled connection slots', () => {
  const output = execFileSync('lua', ['test/transport-bind.lua'], { encoding: 'utf8' });

  assert.match(output, /Loopback transport assertions passed/);
  assert.match(output, /Connection deadline assertions passed/);
});
