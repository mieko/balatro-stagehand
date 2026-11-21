import { cp, mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { ROOT } from '../tools/common.mjs';

export async function copyProject(root, version = '1.2.3') {
  for (const directory of ['mod', 'client', 'docs']) {
    await cp(join(ROOT, directory), join(root, directory), { recursive: true });
  }

  const provider = 'stagehand/addons/stagehand';
  await mkdir(join(root, provider), { recursive: true });
  await cp(join(ROOT, provider, 'client.mjs'), join(root, provider, 'client.mjs'));
  await cp(join(ROOT, 'LICENSE'), join(root, 'LICENSE'));
  await writeFile(join(root, 'package.json'), JSON.stringify({ version }));
}
