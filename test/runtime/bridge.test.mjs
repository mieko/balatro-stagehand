import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { WebSocket } from 'ws';
import { createConnection } from 'node:net';
import { once } from 'node:events';
import { connectBalatro } from '../../client/balatro.mjs';
import { launchFixture } from './fixture.mjs';

const { connect } = await import(createRequire(import.meta.url).resolve('godot-stagehand'));

test(
  'real LÖVE transport, registration, subscriptions and fatal interruption',
  { timeout: 20000 },
  async (t) => {
    const fixture = await launchFixture(t);
    const port = Number((await fixture.waitFor(/FIXTURE_READY (\d+)/))[1]);
    const url = `ws://127.0.0.1:${port}`;
    const raw = new WebSocket(url);
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
    assert.equal(responses[1].result.length, 3);
    await assert.rejects(connect(url, { token: 'wrong' }), /Authentication failed/);
    const client = await connectBalatro(url, { token: 'fixture-only' });
    t.after(() => client.close());
    assert.deepEqual(
      (await client.client.objects()).map((object) => object.label),
      ['Balatro', 'LoveRuntime', 'Registry'],
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
    const url = `ws://127.0.0.1:${port}`;
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
