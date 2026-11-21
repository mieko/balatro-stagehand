import { constants } from 'node:fs';
import { cp, mkdir, realpath, rm, writeFile } from 'node:fs/promises';
import { isAbsolute, join, relative, resolve, sep } from 'node:path';
import {
  ROOT,
  assertStopped,
  cliOptions,
  defaultGame,
  platformLayout,
  runCli,
  sha256,
} from './common.mjs';
import { buildMod } from './build-mod.mjs';

function containsPath(parent, child) {
  const path = relative(parent, child);

  return path === '' || (path !== '..' && !path.startsWith('..' + sep) && !isAbsolute(path));
}

function requireSeparateSource(source, app) {
  if (containsPath(source, app) || containsPath(app, source)) {
    throw new Error('Use the original Steam installation as --game, not the prepared copy');
  }
}

export async function prepare({
  root = ROOT,
  layout = platformLayout(),
  source = defaultGame(layout.platform),
} = {}) {
  await assertStopped(root);

  source = resolve(source);
  const local = join(root, '.local');
  const app = join(local, layout.directory);

  requireSeparateSource(source, app);
  source = await realpath(source);
  await mkdir(local, { recursive: true });
  requireSeparateSource(source, join(await realpath(local), layout.directory));

  const sourcePack = join(source, layout.pack);
  const originalHash = await sha256(sourcePack);

  await rm(join(local, 'prepared.json'), { force: true });
  await rm(app, { recursive: true, force: true });
  await cp(source, app, {
    recursive: true,
    mode: constants.COPYFILE_FICLONE,
    verbatimSymlinks: true,
  });
  await buildMod({ root, directory: join(local, 'mods/BalatroStagehand') });

  if (
    (await sha256(sourcePack)) !== originalHash ||
    (await sha256(join(app, layout.pack))) !== originalHash
  ) {
    throw new Error('Game archive changed during preparation; installation is incomplete');
  }

  await writeFile(
    join(local, 'prepared.json'),
    JSON.stringify(
      {
        source,
        sha256: originalHash,
        platform: layout.platform,
        arch: layout.arch,
      },
      null,
      2,
    ),
  );

  console.log('Prepared isolated game and mod; original archive unchanged.');
}

await runCli(import.meta.url, () => {
  const options = cliOptions({ game: { type: 'string' } });

  return prepare({ source: options.game });
});
