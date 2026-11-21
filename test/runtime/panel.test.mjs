import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { readZip, zipData } from '../../tools/archives.mjs';
import { defaultGame, platformLayout } from '../../tools/common.mjs';

test('shared panel uses installed native settings builders and callbacks', async (t) => {
  const directory = await mkdtemp(join(tmpdir(), 'balatro-panel-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const game = process.env.BALATRO_APP ?? defaultGame();
  await readZip(join(game, platformLayout().pack), async (entries) => {
    for (const file of ['UI_definitions.lua', 'button_callbacks.lua']) {
      await writeFile(join(directory, file), await zipData(entries, `functions/${file}`));
    }
    await writeFile(
      join(directory, 'controller.lua'),
      await zipData(entries, 'engine/controller.lua'),
    );
    await writeFile(join(directory, 'ui.lua'), await zipData(entries, 'engine/ui.lua'));
  });
  const output = execFileSync('lua', ['test/panel.lua', directory], { encoding: 'utf8' });

  assert.match(output, /Native panel assertions passed:/);
});
