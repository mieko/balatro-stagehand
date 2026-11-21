import assert from 'node:assert/strict';
import { test } from 'node:test';
import { lstat, mkdir, mkdtemp, readFile, rm, symlink, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { pathToFileURL } from 'node:url';
import { c } from 'tar';
import { ROOT, assertStopped, platformLayout, sha256 } from '../tools/common.mjs';
import { readZip, writeZip, zipData } from '../tools/archives.mjs';
import { extractLovely, fetchLovely, lovelyRelease } from '../tools/fetch-lovely.mjs';
import { prepare } from '../tools/prepare.mjs';
import { launchConfiguration } from '../tools/launch.mjs';
import { copyProject } from './project-fixture.mjs';

const DEFINITIONS = `options = {0.5, 1, 2, 4}, opt_callback = 'change_gamespeed'
card_type = ({localize('k_common'), localize('k_uncommon'), localize('k_rare')})[card.config.center.rarity]`;

async function temporary(t) {
  const root = await mkdtemp(join(tmpdir(), 'balatro-setup-test-'));
  t.after(() => rm(root, { recursive: true, force: true }));

  return root;
}

async function put(filename, data = 'fixture') {
  await mkdir(join(filename, '..'), { recursive: true });
  await writeFile(filename, data);
}

async function sourceGame(root, layout) {
  const source = join(root, 'steam', layout.directory);
  const archive = join(source, layout.pack);

  await mkdir(join(archive, '..'), { recursive: true });
  await writeZip(archive, [['functions/UI_definitions.lua', Buffer.from(DEFINITIONS)]]);

  if (layout.platform !== 'darwin') {
    await writeFile(
      archive,
      Buffer.concat([Buffer.from('MZ executable fixture'), await readFile(archive)]),
    );
  }

  if (layout.executable && layout.executable !== layout.pack) {
    await put(join(source, layout.executable));
  }

  await copyProject(root);

  return source;
}

async function completeInstallation(root, layout) {
  const source = await sourceGame(root, layout);

  await prepare({ root, layout, source });
  await put(join(root, '.local/deps', layout.library));
  await put(join(root, '.local/deps/lovely.json'), JSON.stringify(layout));

  return source;
}

for (const [platform, arch] of [
  ['darwin', 'arm64'],
  ['darwin', 'x64'],
  ['win32', 'x64'],
  ['linux', 'x64'],
]) {
  test(`prepare and launch configuration: ${platform}/${arch}`, async (t) => {
    const root = await temporary(t);
    const layout = platformLayout(platform, arch);
    const source = await completeInstallation(root, layout);
    const originalHash = await sha256(join(source, layout.pack));
    const prepared = JSON.parse(await readFile(join(root, '.local/prepared.json')));

    assert.equal(prepared.sha256, originalHash);
    assert.equal(await sha256(join(root, '.local', layout.directory, layout.pack)), originalHash);

    const mod = join(root, '.local/mods/BalatroStagehand');

    assert.equal(
      await readFile(join(mod, 'native_data.lua'), 'utf8'),
      await readFile(join(ROOT, 'mod/native_data.lua'), 'utf8'),
    );

    const manifest = await readFile(join(mod, 'lovely.toml'), 'utf8');

    assert.match(manifest, /sources = \["entry.lua"\]/);
    assert.doesNotMatch(manifest, /source = "entry.lua"/);
    assert.match(manifest, /name = "websocket.frame"/);

    const plan = await launchConfiguration({ root, layout, love: '/custom/love' });

    assert.equal(plan.environment.STAGEHAND_HOST, '127.0.0.1');
    assert.equal(plan.cwd, join(root, '.local', layout.directory));

    if (platform === 'linux') {
      assert.equal(plan.command, '/custom/love');
      assert.deepEqual(plan.args, [join(plan.cwd, 'Balatro.exe')]);
      assert.equal(plan.environment.LD_PRELOAD, plan.library);
    } else {
      assert.equal(plan.command, join(plan.cwd, layout.executable));
      assert.deepEqual(plan.args, []);
      assert.deepEqual(plan.environment, {
        STAGEHAND_HOST: '127.0.0.1',
        ...(platform === 'darwin' ? { DYLD_INSERT_LIBRARIES: plan.library } : {}),
      });
    }

    assert.equal(lovelyRelease(layout).sha256.length, 64);
  });
}

test('a linked game directory produces an independent installation', async (t) => {
  const root = await temporary(t);
  const layout = platformLayout('win32', 'x64');
  const source = await sourceGame(root, layout);
  const link = join(root, 'linked-game');

  await symlink(source, link, 'junction');
  await prepare({ root, layout, source: link });

  const copy = join(root, '.local', layout.directory);

  assert.equal((await lstat(copy)).isSymbolicLink(), false);

  await put(join(copy, layout.library), 'isolated injector');
  await assert.rejects(readFile(join(source, layout.library)), { code: 'ENOENT' });
});

test('appended executable ZIP can supply native source without changing its bytes', async (t) => {
  const root = await temporary(t);
  const layout = platformLayout('win32', 'x64');
  const source = await sourceGame(root, layout);
  const archive = join(source, layout.pack);
  const hash = await sha256(archive);
  const definitions = await readZip(archive, async (entries) =>
    Buffer.from(await zipData(entries, 'functions/UI_definitions.lua')).toString('utf8'),
  );

  assert.equal(definitions, DEFINITIONS);
  assert.equal(await sha256(archive), hash);
});

test('failed mod replacement invalidates previous preparation', async (t) => {
  const root = await temporary(t);
  const layout = platformLayout('darwin', 'arm64');
  const source = await completeInstallation(root, layout);
  await rm(join(root, 'mod'), { recursive: true });

  await assert.rejects(prepare({ root, layout, source }), { code: 'ENOENT' });
  await assert.rejects(readFile(join(root, '.local/prepared.json')), { code: 'ENOENT' });
});

test('incomplete installations refuse launch before any process can be started', async (t) => {
  const root = await temporary(t);
  const layout = platformLayout('darwin', 'arm64');
  await completeInstallation(root, layout);

  const paths = [
    'prepared.json',
    'Balatro.app/Contents/MacOS/love',
    'deps/liblovely.dylib',
    'deps/lovely.json',
    'mods/BalatroStagehand/entry.lua',
    'mods/BalatroStagehand/lovely.toml',
  ];

  for (const path of paths) {
    const filename = join(root, '.local', path);
    const data = await readFile(filename);

    await rm(filename);
    await assert.rejects(launchConfiguration({ root, layout }), /Incomplete installation/);

    await writeFile(filename, data);
  }
});

test('active managed session blocks preparation and dependency replacement', async (t) => {
  const root = await temporary(t);
  await put(join(root, '.local/session.json'), JSON.stringify({ pid: process.pid }));

  await assert.rejects(assertStopped(root), /Quit the isolated game/);
  await assert.rejects(prepare({ root }), /Quit the isolated game/);
  await assert.rejects(fetchLovely({ root }), /Quit the isolated game/);
  await assert.rejects(launchConfiguration({ root }), /Quit the isolated game/);
});

test('preparation refuses to copy the managed directory onto itself or its ancestor', async (t) => {
  const root = await temporary(t);
  const layout = platformLayout('win32', 'x64');

  for (const source of [root, join(root, '.local/Balatro'), join(root, '.local/Balatro/subdir')]) {
    await assert.rejects(prepare({ root, layout, source }), /original Steam installation/);
  }

  const link = join(root, 'linked-root');
  await symlink(root, link, 'junction');
  await assert.rejects(prepare({ root, layout, source: link }), /original Steam installation/);
});

test('a linked local directory cannot redirect preparation onto the original game', async (t) => {
  const root = await temporary(t);
  const layout = platformLayout('win32', 'x64');
  const source = await sourceGame(root, layout);
  const archive = join(source, layout.pack);
  const originalHash = await sha256(archive);
  await symlink(join(root, 'steam'), join(root, '.local'), 'junction');

  await assert.rejects(prepare({ root, layout, source }), /original Steam installation/);

  assert.equal(await sha256(archive), originalHash);
});

test('launch refuses artifacts prepared for another platform', async (t) => {
  const root = await temporary(t);
  const layout = platformLayout('darwin', 'arm64');
  await completeInstallation(root, layout);
  await put(
    join(root, '.local/deps/lovely.json'),
    JSON.stringify({ platform: 'darwin', arch: 'x64' }),
  );

  await assert.rejects(launchConfiguration({ root, layout }), /Lovely belongs to another platform/);
});

test('unsupported platforms fail before installation', () => {
  assert.throws(() => platformLayout('linux', 'arm64'), /No pinned Lovely release/);
  assert.throws(() => platformLayout('freebsd', 'x64'), /No pinned Lovely release/);
});

test('Lovely checksum mismatch refuses extraction', async (t) => {
  const root = await temporary(t);
  const layout = platformLayout('win32', 'x64');
  await put(join(root, '.local/deps', lovelyRelease(layout).filename), 'wrong download');

  await assert.rejects(fetchLovely({ root, layout }), /checksum mismatch/);
  await assert.rejects(readFile(join(root, '.local/deps/winmm.dll')), { code: 'ENOENT' });
});

test('Lovely ZIP extracts only the expected DLL', async (t) => {
  const root = await temporary(t);
  const archive = join(root, 'lovely.zip');
  const layout = platformLayout('win32', 'x64');

  await writeZip(archive, [['winmm.dll', Buffer.from('dll')]]);
  await extractLovely(archive, root, layout);

  assert.equal(await readFile(join(root, 'winmm.dll'), 'utf8'), 'dll');

  await writeZip(archive, [['unexpected.dll', Buffer.from('bad')]]);
  await assert.rejects(extractLovely(archive, root, layout), /Unexpected Lovely ZIP/);
});

test('Lovely TAR validates every member before extracting its library', async (t) => {
  const root = await temporary(t);
  const input = join(root, 'input');
  const output = join(root, 'output');

  await mkdir(output);
  await put(join(input, 'liblovely.so'), 'library');
  await put(join(input, 'run_lovely_linux.sh'), 'script');

  const archive = join(root, 'lovely.tar.gz');
  await c({ file: archive, cwd: input, gzip: true }, ['liblovely.so', 'run_lovely_linux.sh']);
  const layout = platformLayout('linux', 'x64');

  await extractLovely(archive, output, layout);

  assert.equal(await readFile(join(output, 'liblovely.so'), 'utf8'), 'library');

  await assert.rejects(readFile(join(output, 'run_lovely_linux.sh')), { code: 'ENOENT' });

  await put(join(input, 'unexpected'), 'bad');
  await c({ file: archive, cwd: input, gzip: true }, ['unexpected']);
  await assert.rejects(extractLovely(archive, output, layout), /Unexpected Lovely TAR/);
});

test('release bundle includes the mod and matching resources without an installed game', async (t) => {
  const root = await temporary(t);
  await copyProject(root);

  const { buildRelease } = await import('../tools/build-mod.mjs');
  const { directory, zip } = await buildRelease({ root });

  assert.equal(zip, join(root, '.local/dist/BalatroStagehand-1.2.3.zip'));

  const client = await import(pathToFileURL(join(directory, 'client.mjs')).href);

  assert.equal(typeof client.connectBalatro, 'function');
  assert.equal(typeof client.connect, 'function');

  const original = await readFile(join(ROOT, 'mod/lovely.toml'), 'utf8');

  assert.equal(await readFile(join(directory, 'lovely.toml'), 'utf8'), original);
  assert.match(original, /name = "balatro_stagehand.server_config"/);
  assert.match(original, /name = "balatro_stagehand.native_data"/);

  await readZip(zip, async (entries) => {
    assert.ok(entries.every((entry) => entry.filename.startsWith('BalatroStagehand/')));
    assert.ok(await zipData(entries, 'BalatroStagehand/vendor/websocket/COPYRIGHT'));
    assert.equal(
      Buffer.from(await zipData(entries, 'BalatroStagehand/LICENSE')).toString(),
      await readFile(join(ROOT, 'LICENSE'), 'utf8'),
    );
    assert.ok(await zipData(entries, 'BalatroStagehand/docs/api.md'));
    assert.ok(await zipData(entries, 'BalatroStagehand/docs/game.md'));
    assert.ok(await zipData(entries, 'BalatroStagehand/client.mjs'));

    const metadata = JSON.parse(
      Buffer.from(await zipData(entries, 'BalatroStagehand/BalatroStagehand.json')),
    );
    assert.equal(metadata.id, 'balatro_stagehand');
    assert.equal(metadata.name, 'Balatro Stagehand');
    assert.equal(metadata.version, '1.2.3');
    assert.deepEqual(metadata.dependencies, ['Lovely', 'Balatro']);

    await zipData(entries, 'BalatroStagehand/' + metadata.main_file);

    assert.equal(
      Buffer.from(await zipData(entries, 'BalatroStagehand/version.lua')).toString(),
      'return "1.2.3"\n',
    );
    assert.equal(
      Buffer.from(await zipData(entries, 'BalatroStagehand/entry.lua')).toString(),
      await readFile(join(ROOT, 'mod/entry.lua'), 'utf8'),
    );
    assert.equal(
      entries.some((entry) => /session|node_modules/.test(entry.filename)),
      false,
    );
  });
});

test('release packaging rejects a missing or unsafe version before preparing files', async (t) => {
  const root = await temporary(t);
  const { buildRelease } = await import('../tools/build-mod.mjs');

  for (const version of [undefined, '../outside', '1.2.3/path']) {
    await put(join(root, 'package.json'), JSON.stringify({ version }));
    await assert.rejects(buildRelease({ root }), /package.json must contain a release version/);
  }
});
