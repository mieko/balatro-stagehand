import { mkdtemp, mkdir, cp, symlink, rm } from 'node:fs/promises';
import { spawn, execFileSync } from 'node:child_process';
import { tmpdir, homedir } from 'node:os';
import { join } from 'node:path';

export async function launchFixture(t, { native = false } = {}) {
  const temporary = await mkdtemp(join(tmpdir(), 'balatro-stagehand-runtime-'));
  t.after(() => rm(temporary, { recursive: true, force: true }));
  const game =
    process.env.BALATRO_APP ??
    join(homedir(), 'Library/Application Support/Steam/steamapps/common/Balatro/Balatro.app');
  const app = join(temporary, 'Fixture.app', 'Contents');
  await mkdir(join(app, 'MacOS'), { recursive: true });
  await mkdir(join(app, 'Resources'));
  await cp(join(game, 'Contents/MacOS/love'), join(app, 'MacOS/love'));
  await symlink(join(game, 'Contents/Frameworks'), join(app, 'Frameworks'));
  await cp('test/runtime/Info.plist', join(app, 'Info.plist'));
  execFileSync('python3', [
    'test/runtime/package.py',
    join(app, 'Resources', 'fixture.love'),
    ...(native ? [join(game, 'Contents/Resources/Balatro.love')] : []),
  ]);
  const environment = { ...process.env };
  delete environment.DYLD_INSERT_LIBRARIES;
  const child = spawn(join(app, 'MacOS/love'), [], { env: environment });
  const exited = new Promise((resolve) => child.once('exit', resolve));
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
