import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';

test('whole-game native boundaries, ordering and public inspection', () => {
  assert.match(
    execFileSync('lua', ['test/gameplay.lua'], { encoding: 'utf8' }),
    /Gameplay checks passed/,
  );
});
