import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';

test('boot records bound endpoints and startup failures without changing native load', () => {
  const output = execFileSync('lua', ['test/boot.lua'], { encoding: 'utf8' });

  assert.match(output, /Boot assertions passed:/);
});
