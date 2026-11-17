import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';

test('native tree inspection, control activation and LÖVE-only runtime metadata', () => {
  const output = execFileSync('lua', ['test/scene_tree.lua'], { encoding: 'utf8' });

  assert.match(output, /Scene tree checks passed/);
});
