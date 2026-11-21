import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { ROOT } from '../../tools/common.mjs';
import { directoryFiles, readZip, writeZip, zipData } from '../../tools/archives.mjs';

const NATIVE_FILES = [
  'engine/object.lua',
  'engine/ui.lua',
  'game.lua',
  'card.lua',
  'cardarea.lua',
  'functions/misc_functions.lua',
  'functions/button_callbacks.lua',
  'functions/UI_definitions.lua',
];

export async function packageFixture(filename, nativePack, config = { port: 0 }) {
  const files = [['stagehand.json', Buffer.from(JSON.stringify(config))]];

  files.push(
    ...(await directoryFiles(join(ROOT, 'mod'), 'mod')).filter(([name]) => name.endsWith('.lua')),
  );
  files.push(['conf.lua', await readFile(join(ROOT, 'test/runtime/conf.lua'))]);
  files.push([
    'main.lua',
    await readFile(join(ROOT, `test/runtime/${nativePack ? 'source' : 'main'}.lua`)),
  ]);

  if (nativePack) {
    await readZip(nativePack, async (entries) => {
      for (const name of NATIVE_FILES) files.push([`native/${name}`, await zipData(entries, name)]);
    });
  }

  await writeZip(filename, files);
}
