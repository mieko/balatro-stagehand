import assert from 'node:assert/strict';
import { test } from 'node:test';
import { execFileSync } from 'node:child_process';
import { mkdtemp, rename, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { buildRelease } from '../tools/build-mod.mjs';
import { copyProject } from './project-fixture.mjs';

test('installed resources resolve after relocation and the bundled client imports without npm', async (t) => {
  const root = await mkdtemp(join(tmpdir(), 'balatro-resources-'));
  t.after(() => rm(root, { recursive: true, force: true }));

  await copyProject(root);

  const { directory } = await buildRelease({ root });
  const installed = join(root, 'Moved mod # café');
  await rename(directory, installed);

  for (const source of ['client', 'docs', 'stagehand']) {
    await rm(join(root, source), { recursive: true });
  }

  const output = execFileSync(
    'lua',
    ['test/resources.lua', join(installed, 'resources.lua'), join(installed, 'vendor/dkjson.lua')],
    {
      input: JSON.stringify([
        '/tmp/é #.md',
        'C:\\Users\\Some User\\API #.md',
        '\\\\server\\share\\API.md',
      ]),
      encoding: 'utf8',
    },
  );
  const { resources, urls } = JSON.parse(output);

  assert.deepEqual(resources.stagehandApi, {
    path: join(installed, 'docs/api.md'),
    url: pathToFileURL(join(installed, 'docs/api.md')).href,
    available: true,
  });
  assert.deepEqual(resources.agentApi, {
    path: join(installed, 'docs/game.md'),
    url: pathToFileURL(join(installed, 'docs/game.md')).href,
    available: true,
  });
  assert.deepEqual(resources.client, {
    path: join(installed, 'client.mjs'),
    url: pathToFileURL(join(installed, 'client.mjs')).href,
    available: true,
  });
  assert.deepEqual(urls, [
    'file:///tmp/%C3%A9%20%23.md',
    'file:///C:/Users/Some%20User/API%20%23.md',
    'file://server/share/API.md',
  ]);

  const imported = execFileSync(
    process.execPath,
    [
      '--input-type=module',
      '-e',
      'const module = await import(process.argv[1]); console.log(typeof module.connectBalatro, typeof module.present);',
      resources.client.url,
    ],
    { cwd: tmpdir(), encoding: 'utf8' },
  );

  assert.equal(imported.trim(), 'function function');
});
