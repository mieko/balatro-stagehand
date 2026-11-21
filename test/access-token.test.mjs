import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';

test('access token is supplied or generated once per game launch', () => {
  const output = execFileSync('lua', ['test/access_token.lua'], { encoding: 'utf8' });

  assert.match(output, /Access token checks passed/);
});
