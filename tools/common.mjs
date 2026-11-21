import { createHash } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { readFile, stat } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';

export const ROOT = fileURLToPath(new URL('../', import.meta.url));

export function platformLayout(platform = process.platform, arch = process.arch) {
  const layouts = {
    darwin: {
      architectures: ['arm64', 'x64'],
      directory: 'Balatro.app',
      executable: 'Contents/MacOS/love',
      pack: 'Contents/Resources/Balatro.love',
      library: 'liblovely.dylib',
    },
    win32: {
      architectures: ['x64'],
      directory: 'Balatro',
      executable: 'Balatro.exe',
      pack: 'Balatro.exe',
      library: 'winmm.dll',
    },
    linux: {
      architectures: ['x64'],
      directory: 'Balatro',
      executable: null,
      pack: 'Balatro.exe',
      library: 'liblovely.so',
    },
  };
  const layout = layouts[platform];

  if (!layout?.architectures.includes(arch)) {
    throw new Error(`No pinned Lovely release for ${platform}/${arch}`);
  }

  return { ...layout, platform, arch };
}

export function defaultGame(platform = process.platform) {
  const paths = {
    darwin: join(
      homedir(),
      'Library/Application Support/Steam/steamapps/common/Balatro/Balatro.app',
    ),
    win32: join(
      process.env['ProgramFiles(x86)'] ?? 'C:\\Program Files (x86)',
      'Steam/steamapps/common/Balatro',
    ),
    linux: join(homedir(), '.local/share/Steam/steamapps/common/Balatro'),
  };

  return paths[platform];
}

export async function sha256(filename) {
  const hash = createHash('sha256');

  for await (const chunk of createReadStream(filename)) hash.update(chunk);

  return hash.digest('hex');
}

export async function isFile(filename) {
  try {
    return (await stat(filename)).isFile();
  } catch (error) {
    if (error.code === 'ENOENT') return false;

    throw error;
  }
}

export async function assertStopped(root) {
  let session;

  try {
    session = JSON.parse(await readFile(join(root, '.local/session.json'), 'utf8'));
  } catch (error) {
    if (error.code === 'ENOENT') return;

    throw error;
  }

  if (!Number.isSafeInteger(session.pid) || session.pid <= 0) {
    throw new Error('Invalid managed session PID; check .local/session.json');
  }

  try {
    process.kill(session.pid, 0);
  } catch (error) {
    if (error.code === 'ESRCH') return;

    throw new Error('Cannot verify that the isolated game has exited', { cause: error });
  }

  throw new Error('Quit the isolated game before changing or launching it');
}

export function cliOptions(options = {}) {
  return parseArgs({ options, allowPositionals: false }).values;
}

export async function runCli(url, main) {
  if (!process.argv[1] || resolve(process.argv[1]) !== fileURLToPath(url)) return;

  try {
    await main();
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
