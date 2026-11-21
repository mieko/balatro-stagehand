import { test } from 'node:test';
import assert from 'node:assert/strict';
import { WebSocket } from 'ws';
import { createConnection } from 'node:net';
import { once } from 'node:events';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { pathToFileURL } from 'node:url';
import { readZip, zipData } from '../../tools/archives.mjs';
import { buildRelease } from '../../tools/build-mod.mjs';
import { copyProject } from '../project-fixture.mjs';
import { connect, connectBalatro } from '../../client/balatro.mjs';
import { launchFixture } from './fixture.mjs';

test(
  'real LÖVE transport, registration, subscriptions and fatal interruption',
  { timeout: 20000 },
  async (t) => {
    const fixture = await launchFixture(t);
    const port = Number((await fixture.waitFor(/FIXTURE_READY (\d+)/))[1]);
    const url = `http://127.0.0.1:${port}`;
    const raw = new WebSocket(`ws://127.0.0.1:${port}/rpc`);
    t.after(() => raw.close());
    await new Promise((resolve) => raw.once('open', resolve));
    const batch = new Promise((resolve) =>
      raw.once('message', (bytes) => resolve(JSON.parse(bytes))),
    );
    raw.send(
      JSON.stringify([
        {
          jsonrpc: '2.0',
          id: 1,
          method: 'session.hello',
          params: { protocol: 1, token: 'fixture-only' },
        },
        { jsonrpc: '2.0', id: 2, method: 'objects.list', params: {} },
      ]),
    );
    const responses = await batch;

    assert.equal(responses[0].result.engine.name, 'LÖVE');
    assert.equal(responses[1].result.length, 4);

    await assert.rejects(connect(url, { token: 'wrong' }), /Authentication failed/);
    const client = await connectBalatro({ url, token: 'fixture-only' });
    t.after(() => client.close());

    assert.deepEqual(
      (await client.client.objects()).map((object) => object.label),
      ['Balatro', 'LoveRuntime', 'LoveScript', 'Registry'],
    );
    const payload = { text: 'large λ payload '.repeat(10000), zero: 0, flag: false, list: [] };

    assert.deepEqual(await client.invoke('echo', payload), payload);
    assert.equal((await client.playHand([])).state.kind, 'FIXTURE');

    await assert.rejects(client.playHand([], { fail: true }), (error) => {
      assert.match(error.message, /controlled native fatal/);
      assert.match(error.fatal.traceback, /main.lua/);

      return true;
    });
  },
);

test(
  'TCP probes that disconnect before upgrade do not consume connection slots',
  { timeout: 15000 },
  async (t) => {
    const fixture = await launchFixture(t);
    const port = Number((await fixture.waitFor(/FIXTURE_READY (\d+)/))[1]);
    const url = `http://127.0.0.1:${port}`;
    const control = await connect(url, { token: 'fixture-only' });
    t.after(() => control.close());
    const root = await control.findObject('Balatro');

    for (let probe = 0; probe < 10; probe++) {
      const socket = createConnection({ host: '127.0.0.1', port });
      await once(socket, 'connect');
      const closed = once(socket, 'close');
      if (probe % 2) socket.write('GET / HTTP/1.1\r\n');
      socket.destroy();
      await closed;
      await root.invoke('echo', { probe });
    }

    const fresh = await connect(url, { token: 'fixture-only' });
    t.after(() => fresh.close());
    const game = await fresh.findObject('Balatro');

    assert.deepEqual(await game.invoke('state'), { kind: 'FIXTURE', ready: true });
  },
);

test(
  'tokenless loopback access works without launcher variables and refuses browser origins',
  { timeout: 15000 },
  async (t) => {
    const fixture = await launchFixture(t, { config: { port: 0 }, token: null });
    const port = Number((await fixture.waitFor(/FIXTURE_READY (\d+)/))[1]);
    const game = await connectBalatro({ url: `http://localhost:${port}` });
    t.after(() => game.close());

    assert.equal((await game.state()).kind, 'FIXTURE');

    for (const host of ['127.0.0.1', '[::1]']) {
      const local = await connectBalatro({ url: `http://${host}:${port}` });
      t.after(() => local.close());

      assert.equal((await local.state()).kind, 'FIXTURE');
    }
    const script = await game.client.root('LoveScript');

    assert.equal(await script.evaluate({ source: 'function evaluate() return 42 end' }), 42);

    const browser = new WebSocket(`ws://127.0.0.1:${port}/rpc`, { origin: 'https://example.com' });
    const failure = await new Promise((resolve) => browser.once('error', resolve));

    assert.match(failure.message, /Unexpected server response: 403/);

    browser.terminate();

    assert.equal((await game.state()).kind, 'FIXTURE');
  },
);

test(
  'wildcard listener accepts IPv4 and IPv6 with the same configured token',
  { timeout: 15000 },
  async (t) => {
    const fixture = await launchFixture(t, {
      config: { host: '*', port: 0, requireToken: true },
    });
    const port = Number((await fixture.waitFor(/FIXTURE_READY (\d+)/))[1]);
    for (const host of ['127.0.0.1', '[::1]']) {
      const game = await connectBalatro({ url: `http://${host}:${port}`, token: 'fixture-only' });
      t.after(() => game.close());

      assert.equal((await game.state()).kind, 'FIXTURE');
    }
  },
);

async function request(port, requestHead) {
  const socket = createConnection({ host: '127.0.0.1', port });
  try {
    await once(socket, 'connect');
    socket.write(requestHead);
    let response = '';
    socket.setEncoding('utf8');
    for await (const chunk of socket) {
      response += chunk;
    }
    return response;
  } finally {
    socket.destroy();
  }
}

test(
  'one listener serves the exact release downloads and speaks RPC',
  { timeout: 20000 },
  async (t) => {
    const root = await mkdtemp(join(tmpdir(), 'balatro-release-http-'));
    t.after(() => rm(root, { recursive: true, force: true }));
    await copyProject(root);
    const { zip } = await buildRelease({ root });
    const installed = join(root, 'Mods', 'Balatro Stagehand # é');
    await mkdir(join(installed, 'docs'), { recursive: true });

    const paths = {
      '/client.mjs': 'client.mjs',
      '/api.md': 'docs/api.md',
      '/game.md': 'docs/game.md',
    };
    const assets = await readZip(zip, async (entries) => {
      const bytes = {};
      for (const name of ['resources.lua', ...Object.values(paths)]) {
        const data = await zipData(entries, 'BalatroStagehand/' + name);
        await writeFile(join(installed, name), data);
        bytes[name] = Buffer.from(data);
      }
      return bytes;
    });

    const fixture = await launchFixture(t, { resources: join(installed, 'resources.lua') });
    const port = Number((await fixture.waitFor(/FIXTURE_READY (\d+)/))[1]);
    const base = `http://127.0.0.1:${port}`;

    const index = await fetch(base);
    assert.equal(index.status, 200);
    assert.match(index.headers.get('content-type'), /^text\/markdown/);
    const discovery = await index.text();
    assert.match(discovery, /Balatro.*JavaScript API/);
    assert.match(discovery, /Ask the game operator for the access token/);
    assert.match(discovery, /`\/rpc`/);
    assert.doesNotMatch(discovery, /fixture-only|Balatro Stagehand #/);

    // Requests keep serving the startup bytes even if the installed files change.
    await writeFile(join(installed, 'docs/game.md'), 'replacement on disk');

    for (const [route, path] of Object.entries(paths)) {
      assert.ok(discovery.includes(`](.${route})`));
      const downloaded = await fetch(base + route);
      assert.equal(downloaded.status, 200);
      const mime = route.endsWith('.mjs') ? 'text/javascript' : 'text/markdown';
      assert.equal(downloaded.headers.get('content-type'), mime + '; charset=utf-8');
      assert.equal(downloaded.headers.get('x-content-type-options'), 'nosniff');
      assert.deepEqual(Buffer.from(await downloaded.arrayBuffer()), assets[path]);

      const head = await fetch(base + route, { method: 'HEAD' });
      assert.equal(head.status, 200);
      assert.equal(Number(head.headers.get('content-length')), assets[path].length);
      assert.equal(await head.text(), '');
    }

    const standalone = join(root, 'downloaded.mjs');
    const downloaded = await fetch(base + '/client.mjs');
    await writeFile(standalone, Buffer.from(await downloaded.arrayBuffer()));
    const bundled = await import(pathToFileURL(standalone).href);
    const core = await bundled.connect(base, { token: 'fixture-only' });
    t.after(() => core.close());
    assert.ok(core instanceof bundled.StagehandClient);
    const registry = await core.root('Registry');
    assert.ok(registry instanceof bundled.RemoteObject);
    assert.equal(
      (await registry.invoke('list')).find((root) => root.label === 'Balatro').kind,
      'Balatro',
    );

    const game = await bundled.connectBalatro({ url: base, token: 'fixture-only' });
    t.after(() => game.close());
    assert.ok(game instanceof bundled.RemoteObject);
    assert.equal((await game.state()).kind, 'FIXTURE');
  },
);

test(
  'fixed HTTP routes and WebSocket admission are enforced before RPC',
  { timeout: 15000 },
  async (t) => {
    const fixture = await launchFixture(t);
    const port = Number((await fixture.waitFor(/FIXTURE_READY (\d+)/))[1]);
    const host = 'Host: 127.0.0.1:' + port + '\r\n';
    const upgrade =
      'Connection: keep-alive, Upgrade\r\nUpgrade: WebSocket\r\n' +
      'Sec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n';
    const cases = [
      ['GET /client.mjs HTTP/1.1\r\n' + host, 404],
      ['GET / HTTP/1.1\r\n' + host + upgrade, 200],
      ['GET /rpc HTTP/1.1\r\n' + host, 400],
      ['HEAD /rpc HTTP/1.1\r\n' + host + upgrade, 405],
      ['POST / HTTP/1.1\r\n' + host, 405],
      ['GET / HTTP/1.1\r\nHost: outside.example\r\n', 403],
      ['GET /rpc HTTP/1.1\r\nHost: outside.example\r\n' + upgrade, 403],
      ['GET / HTTP/1.1\r\nHost: localhost:49152\r\n', 200],
      ['GET / HTTP/1.1\r\nHost: localhost:65536\r\n', 400],
      ['GET / HTTP/1.1\r\n' + host + host, 400],
      ['GET / HTTP/1.1\r\nHost : localhost\r\n', 400],
      ['GET / HTTP/1.1\r\n' + host + 'Content-Length: 1\r\n', 400],
      ['GET / HTTP/1.1\r\n' + host + 'Transfer-Encoding: chunked\r\n', 400],
      ['GET /rpc HTTP/1.1\r\n' + host + upgrade + 'Origin:\r\n', 403],
      ['GET /rpc HTTP/1.1\r\n' + host + upgrade.replace('Version: 13', 'Version: 12'), 426],
      ['GET /rpc HTTP/1.1\r\n' + host + upgrade.replace('Key: dGhl', 'Key: abcd1234'), 400],
      ['GET / HTTP/1.1\r\n' + host + 'X-Long: ' + 'a'.repeat(8192) + '\r\n', 431],
      ['GET /resources.lua HTTP/1.1\r\n' + host, 404],
      ['GET /state HTTP/1.1\r\n' + host, 404],
    ];

    for (const [head, expected] of cases) {
      const response = await request(port, head + '\r\n');
      assert.match(response, new RegExp(`^HTTP/1\\.1 ${expected} `), head.slice(0, 100));
    }
  },
);
