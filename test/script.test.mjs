import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';

test('Lua evaluation binds values, uses live globals and reports synchronous failures', () => {
  assert.match(
    execFileSync('lua', ['test/script.lua'], { encoding: 'utf8' }),
    /Script checks passed/,
  );
});
