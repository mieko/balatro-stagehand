import { mkdir, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { t, x } from 'tar';
import { ROOT, assertStopped, isFile, platformLayout, runCli, sha256 } from './common.mjs';
import { readZip, zipData } from './archives.mjs';

const VERSION = 'v0.10.0';
const RELEASES = {
  'darwin/arm64': [
    'lovely-aarch64-apple-darwin.tar.gz',
    '77aeab72adb4e89a5ff6f4df17c4035236d047f46f7513092b042b1558302436',
  ],
  'darwin/x64': [
    'lovely-x86_64-apple-darwin.tar.gz',
    '0c9e08cac8837b500290a4106221da364ce3610bc0d4a927ba02d6c48e84cf5a',
  ],
  'win32/x64': [
    'lovely-x86_64-pc-windows-msvc.zip',
    '7f481f984ab8ee633c90ce18220c88a2da8f93ca86b6c3e3ff70a725c05807ab',
  ],
  'linux/x64': [
    'lovely-x86_64-unknown-linux-gnu.tar.gz',
    '436879f4951cbff9fb5075484bd924fb9ad028495b73c59b07c78f9da4b53675',
  ],
};

export function lovelyRelease(layout) {
  const [filename, digest] = RELEASES[`${layout.platform}/${layout.arch}`];

  return {
    version: VERSION,
    filename,
    sha256: digest,
    url: `https://github.com/ethangreen-dev/lovely-injector/releases/download/${VERSION}/${filename}`,
  };
}

export async function extractLovely(archive, directory, layout) {
  if (layout.platform === 'win32') {
    return readZip(archive, async (entries) => {
      if (entries.length !== 1 || entries[0].filename !== layout.library || entries[0].directory) {
        throw new Error('Unexpected Lovely ZIP members');
      }

      await writeFile(join(directory, layout.library), await zipData(entries, layout.library));
    });
  }

  const names = [
    layout.library,
    `run_lovely_${layout.platform === 'darwin' ? 'macos' : 'linux'}.sh`,
  ];
  const members = [];

  await t({
    file: archive,
    strict: true,
    onReadEntry: (entry) => {
      members.push({ name: entry.path, type: entry.type });
    },
  });

  if (
    members.length !== names.length ||
    names.some(
      (name) =>
        members.filter((entry) => entry.name === name && entry.type === 'File').length !== 1,
    )
  ) {
    throw new Error('Unexpected Lovely TAR members');
  }

  await x({
    file: archive,
    cwd: directory,
    strict: true,
    filter: (name) => name === layout.library,
  });
}

export async function fetchLovely({ root = ROOT, layout = platformLayout() } = {}) {
  await assertStopped(root);
  const release = lovelyRelease(layout);
  const directory = join(root, '.local/deps');

  await mkdir(directory, { recursive: true });

  const archive = join(directory, release.filename);

  if (!(await isFile(archive))) {
    const response = await fetch(release.url, { signal: AbortSignal.timeout(60_000) });

    if (!response.ok) throw new Error(`Lovely download failed: HTTP ${response.status}`);

    await writeFile(archive, new Uint8Array(await response.arrayBuffer()));
  }

  if ((await sha256(archive)) !== release.sha256) {
    throw new Error(`Lovely checksum mismatch; remove ${archive} and retry`);
  }

  await rm(join(directory, 'lovely.json'), { force: true });
  await extractLovely(archive, directory, layout);
  await writeFile(
    join(directory, 'lovely.json'),
    JSON.stringify(
      {
        ...release,
        platform: layout.platform,
        arch: layout.arch,
      },
      null,
      2,
    ),
  );

  console.log(`Lovely installed locally: ${release.version} (${layout.platform}/${layout.arch})`);
}

await runCli(import.meta.url, () => fetchLovely());
