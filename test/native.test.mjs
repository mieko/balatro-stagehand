import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';

test('Lua action boundaries, state projection and fatal reporting', () => {
  const output = execFileSync('lua', ['test/native.lua'], { encoding: 'utf8' });
  assert.match(output, /Native behavior assertions passed:/);
});
