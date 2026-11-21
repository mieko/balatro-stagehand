import { mkdtemp, mkdir, cp, symlink, rm } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { defaultGame, platformLayout } from '../../tools/common.mjs';
import { packageFixture } from './package.mjs';

export async function launchFixture(
  t,
  { native = false, config, token = 'fixture-only', resources } = {},
) {
  const temporary = await mkdtemp(join(tmpdir(), 'balatro-stagehand-runtime-'));
  t.after(() => rm(temporary, { recursive: true, force: true }));
  const layout = platformLayout();
  const game = process.env.BALATRO_APP ?? defaultGame();
  let executable = process.env.LOVE_BIN;
  let args;

  if (process.platform === 'darwin' && !executable) {
    const app = join(temporary, 'Fixture.app', 'Contents');
    await mkdir(join(app, 'MacOS'), { recursive: true });
    await mkdir(join(app, 'Resources'));
    executable = join(app, 'MacOS/love');
    await cp(join(game, layout.executable), executable);
    await symlink(join(game, 'Contents/Frameworks'), join(app, 'Frameworks'));
    await cp(new URL('./Info.plist', import.meta.url), join(app, 'Info.plist'));
    await packageFixture(
      join(app, 'Resources/fixture.love'),
      native ? join(game, layout.pack) : null,
      config,
    );
    args = [];
  } else {
    if (!executable)
      throw new Error('Set LOVE_BIN to an unfused LÖVE 11.5 executable for runtime tests');

    const pack = join(temporary, 'fixture.love');
    await packageFixture(pack, native ? join(game, layout.pack) : null, config);
    args = [pack];
  }

  const environment = { ...process.env };
  delete environment.DYLD_INSERT_LIBRARIES;
  delete environment.LD_PRELOAD;
  delete environment.LOVELY_MOD_DIR;

  for (const name of Object.keys(environment)) {
    if (name.startsWith('STAGEHAND_')) delete environment[name];
  }

  if (token !== null) environment.STAGEHAND_TOKEN = token;
  if (resources) environment.FIXTURE_RESOURCES = resources;

  const child = spawn(executable, args, { env: environment, windowsHide: true });
  let startupError;

  const exited = new Promise((resolve) => {
    child.once('exit', resolve);
    child.once('error', (error) => {
      startupError = error;
      resolve();
    });
  });

  let output = '';

  child.stdout.on('data', (bytes) => {
    output += bytes;
  });
  child.stderr.on('data', (bytes) => {
    output += bytes;
  });

  t.after(async () => {
    if (child.exitCode === null && child.signalCode === null) child.kill();

    await exited;
  });

  return {
    child,
    exited,
    output: () => output,
    waitFor(pattern) {
      const current = output.match(pattern);

      if (current) {
        return Promise.resolve(current);
      }

      if (startupError || child.exitCode !== null || child.signalCode !== null) {
        return Promise.reject(startupError ?? new Error(`Fixture exited: ${output}`));
      }

      return new Promise((resolve, reject) => {
        const clean = () => {
          clearTimeout(timer);
          child.stdout.off('data', received);
          child.off('exit', failed);
          child.off('error', failed);
        };
        const received = () => {
          const match = output.match(pattern);
          if (match) {
            clean();
            resolve(match);
          }
        };
        const failed = () => {
          clean();
          reject(new Error(`Fixture exited: ${output}`));
        };
        const timer = setTimeout(() => {
          clean();
          reject(new Error(`Fixture did not finish: ${output}`));
        }, 8000);
        child.stdout.on('data', received);
        child.once('exit', failed);
        child.once('error', failed);
      });
    },
  };
}
