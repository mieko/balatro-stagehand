import { cp, readdir, readFile, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { ROOT, cliOptions, runCli } from './common.mjs';
import { directoryFiles, writeZip } from './archives.mjs';
import { packageResources } from './package-resources.mjs';

export async function writeManifest(mod) {
  const metadata = JSON.parse(await readFile(join(mod, 'BalatroStagehand.json'), 'utf8'));
  const modules = [['dkjson', 'vendor/dkjson.lua']];

  for (const filename of (await readdir(mod)).sort()) {
    if (filename.endsWith('.lua') && filename !== 'entry.lua' && filename !== metadata.main_file) {
      modules.push([
        `balatro_stagehand.${filename.slice(0, -4)}`,
        filename === 'resources.lua' ? '{{lovely_hack:patch_dir}}/resources.lua' : filename,
      ]);
    }
  }

  for (const filename of (await readdir(join(mod, 'vendor/websocket'))).sort()) {
    if (filename.endsWith('.lua')) {
      modules.push([`websocket.${filename.slice(0, -4)}`, `vendor/websocket/${filename}`]);
    }
  }

  const patches = modules.map(
    ([name, filename]) =>
      `[[patches]]\n[patches.module]\nsource = "${filename}"\nname = "${name}"\nbefore = "main.lua"\n`,
  );
  const filename = join(mod, 'lovely.toml');
  const base = (await readFile(filename, 'utf8')).replace(
    /^# BEGIN MODULES[\s\S]*?# END MODULES\n\n/,
    '',
  );

  await writeFile(
    filename,
    '# BEGIN MODULES (npm run update:manifest)\n' + patches.join('\n') + '# END MODULES\n\n' + base,
  );
}

export async function buildMod({
  root = ROOT,
  directory = join(root, '.local/dist/BalatroStagehand'),
} = {}) {
  const { version } = JSON.parse(await readFile(join(root, 'package.json'), 'utf8'));

  if (
    typeof version !== 'string' ||
    !/^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$/.test(version)
  ) {
    throw new Error('package.json must contain a release version such as 0.1.0');
  }

  await rm(directory, { recursive: true, force: true });
  await cp(join(root, 'mod'), directory, { recursive: true });
  await cp(join(root, 'LICENSE'), join(directory, 'LICENSE'));
  await writeFile(join(directory, 'version.lua'), `return ${JSON.stringify(version)}\n`);

  const metadataFile = join(directory, 'BalatroStagehand.json');
  const metadata = JSON.parse(await readFile(metadataFile, 'utf8'));
  await writeFile(metadataFile, JSON.stringify({ ...metadata, version }, null, 2) + '\n');

  await packageResources(root, directory);
  await writeManifest(directory);

  return { directory, version };
}

export async function buildRelease({ root = ROOT } = {}) {
  const { directory, version } = await buildMod({ root });
  const zip = join(root, '.local/dist', `BalatroStagehand-${version}.zip`);

  await writeZip(zip, await directoryFiles(directory, 'BalatroStagehand'));

  return { directory, zip };
}

await runCli(import.meta.url, async () => {
  const options = cliOptions({ manifest: { type: 'boolean' } });

  if (options.manifest) return writeManifest(join(ROOT, 'mod'));

  const { directory, zip } = await buildRelease();
  console.log('Drop-in mod: ' + directory + '\nZIP: ' + zip);
});
