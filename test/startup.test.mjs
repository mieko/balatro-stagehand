import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { buildRelease } from '../tools/build-mod.mjs';
import { copyProject } from './project-fixture.mjs';

test('ordinary mod startup, optional configuration and native source data', () => {
  const output = execFileSync('lua', ['test/startup.lua'], { encoding: 'utf8' });

  assert.match(output, /Startup assertions passed:/);
});

test('packaged Lua embeds the package version independently of the checkout', async (t) => {
  const root = await mkdtemp(join(tmpdir(), 'balatro-version-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  await copyProject(root, '3.2.1');

  const { directory } = await buildRelease({ root });
  await rm(join(root, 'package.json'));
  const output = execFileSync(
    'lua',
    ['-e', 'print(dofile(arg[1]))', '-', join(directory, 'version.lua')],
    { input: '', encoding: 'utf8' },
  );

  assert.equal(output.trim(), '3.2.1');
});
