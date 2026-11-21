import { cp, mkdir } from 'node:fs/promises';
import { join } from 'node:path';
import { build } from 'esbuild';

export async function packageResources(root, directory) {
  // Resolve the exact pinned core entry even in a build checkout without node_modules.
  await build({
    absWorkingDir: root,
    entryPoints: ['client/balatro.mjs'],
    alias: { 'godot-stagehand': './stagehand/addons/stagehand/client.mjs' },
    outfile: join(directory, 'client.mjs'),
    bundle: true,
    platform: 'node',
    format: 'esm',
    target: 'node22',
  });

  const docs = join(directory, 'docs');
  await mkdir(docs, { recursive: true });

  for (const name of ['api.md', 'game.md', 'security.md', 'install.md']) {
    await cp(join(root, 'docs', name), join(docs, name));
  }
}
