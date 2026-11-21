import { randomBytes, randomInt } from 'node:crypto';
import { spawn } from 'node:child_process';
import { chmod, cp, open, readFile, writeFile } from 'node:fs/promises';
import { createServer } from 'node:net';
import { join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { ROOT, assertStopped, cliOptions, isFile, platformLayout, runCli } from './common.mjs';

export async function launchConfiguration({
  root = ROOT,
  layout = platformLayout(),
  love = process.env.LOVE_BIN ?? 'love',
} = {}) {
  await assertStopped(root);

  const local = join(root, '.local');
  const app = join(local, layout.directory);
  const library = join(local, 'deps', layout.library);
  const required = [
    join(local, 'prepared.json'),
    join(local, 'deps/lovely.json'),
    library,
    join(local, 'mods/BalatroStagehand/lovely.toml'),
    join(local, 'mods/BalatroStagehand/entry.lua'),
    join(app, layout.pack),
    ...(layout.executable ? [join(app, layout.executable)] : []),
  ];

  for (const filename of required) {
    if (!(await isFile(filename))) {
      throw new Error(
        `Incomplete installation: ${filename}. Run npm run fetch:lovely and npm run prepare:game`,
      );
    }
  }

  const prepared = JSON.parse(await readFile(join(local, 'prepared.json'), 'utf8'));

  if (prepared.platform !== layout.platform || prepared.arch !== layout.arch) {
    throw new Error('Preparation belongs to another platform; run npm run prepare:game');
  }

  const lovely = JSON.parse(await readFile(join(local, 'deps/lovely.json'), 'utf8'));

  if (lovely.platform !== layout.platform || lovely.arch !== layout.arch) {
    throw new Error('Lovely belongs to another platform; run npm run fetch:lovely');
  }

  return {
    command: layout.platform === 'linux' ? love : join(app, layout.executable),
    args: layout.platform === 'linux' ? [join(app, layout.pack)] : [],
    cwd: app,
    library,
    environment: {
      STAGEHAND_HOST: '127.0.0.1',
      ...(layout.platform === 'darwin'
        ? { DYLD_INSERT_LIBRARIES: library }
        : layout.platform === 'linux'
          ? { LD_PRELOAD: library }
          : {}),
    },
  };
}

async function freePort() {
  const server = createServer();

  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });

  const port = server.address().port;

  await new Promise((resolve, reject) =>
    server.close((error) => (error ? reject(error) : resolve())),
  );

  return port;
}

async function waitForStartup(child, log) {
  for (let attempt = 0; attempt < 200; attempt++) {
    if ((await readFile(log, 'utf8')).includes('Stagehand ready:')) return;

    if (child.exitCode !== null || child.signalCode !== null) {
      throw new Error(`Game exited; inspect ${log}`);
    }

    await delay(100);
  }

  throw new Error(`Startup not confirmed; process outcome unknown. Inspect ${log}`);
}

export async function launch({ root = ROOT, layout = platformLayout(), love } = {}) {
  const plan = await launchConfiguration({ root, layout, love });

  if (layout.platform === 'win32') {
    await cp(plan.library, join(plan.cwd, layout.library));
  }

  const local = join(root, '.local');
  const port = await freePort();
  const alphabet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  const token = Array.from({ length: 20 }, () => alphabet[randomInt(alphabet.length)]).join('');
  const instance = randomBytes(8).toString('hex');
  const log = join(local, `game-${Date.now()}.log`);
  const output = await open(log, 'w');
  let child;

  try {
    child = spawn(plan.command, plan.args, {
      cwd: plan.cwd,
      detached: true,
      windowsHide: true,
      stdio: ['ignore', output.fd, output.fd],
      env: {
        ...process.env,
        ...plan.environment,
        STAGEHAND_TOKEN: token,
        STAGEHAND_INSTANCE: instance,
        STAGEHAND_PORT: String(port),
        STAGEHAND_ISOLATED: '1',
        LOVELY_MOD_DIR: join(local, 'mods'),
      },
    });

    await new Promise((resolve, reject) => {
      child.once('spawn', resolve);
      child.once('error', reject);
    });
  } finally {
    await output.close();
  }

  child.unref();
  const session = join(local, 'session.json');

  await writeFile(
    session,
    JSON.stringify(
      {
        url: `http://127.0.0.1:${port}`,
        token,
        instance,
        pid: child.pid,
        log,
      },
      null,
      2,
    ),
    { mode: 0o600 },
  );

  if (process.platform !== 'win32') await chmod(session, 0o600);

  await waitForStartup(child, log);

  console.log(`Isolated Balatro ready, PID ${child.pid}; session in .local/session.json`);
}

await runCli(import.meta.url, () => {
  const options = cliOptions({ love: { type: 'string' } });

  return launch({ love: options.love });
});
