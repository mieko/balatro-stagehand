import { test } from 'node:test';
import assert from 'node:assert/strict';
import { WebSocket, WebSocketServer } from 'ws';
import { connectBalatro } from '../client/balatro.mjs';

async function server(
  t,
  {
    fatal = false,
    pending = false,
    completionTimeoutMs,
    withholdFatalReceipt = false,
    developerMode = true,
  } = {},
) {
  const listener = new WebSocketServer({ host: '127.0.0.1', port: 0, path: '/rpc' });
  t.after(async () => {
    for (const peer of listener.clients) {
      peer.terminate();
    }

    await new Promise((resolve) => listener.close(resolve));
  });
  await new Promise((resolve) => listener.once('listening', resolve));
  const objects = [
    { id: 'game', label: 'Balatro', kind: 'Balatro' },
    { id: 'runtime', label: 'LoveRuntime', kind: 'LoveRuntime' },
    { id: 'tree', label: 'BalatroSceneTree', kind: 'BalatroSceneTree' },
    { id: 'screen', label: 'LoveScreen', kind: 'LoveScreen' },
  ].filter((object) => developerMode || object.kind === 'Balatro');
  const calls = [];
  const hellos = [];
  let subscription = 0;

  listener.on('connection', (peer) => {
    const subscriptions = new Map();
    let autoskip = false;
    let discoveryLabels = false;
    const settings = () => ({ autoskip, discoveryLabels });
    const notify = (object, event, value) => {
      for (const [id, sub] of subscriptions) {
        if (sub.object === object && sub.event === event) {
          peer.send(
            JSON.stringify({
              jsonrpc: '2.0',
              method: 'object.event',
              params: {
                subscription: id,
                object,
                event,
                value,
                clock: {},
              },
            }),
          );
        }
      }
    };
    peer.on('message', (bytes) => {
      const { id, method, params } = JSON.parse(bytes);
      let result;
      if (method === 'session.hello') {
        hellos.push(params);
        result = { protocol: 1, objects };
      } else if (method === 'objects.list') {
        result = objects;
      } else if (method === 'object.subscribe') {
        result = String(++subscription);
        subscriptions.set(result, params);
      } else if (method === 'object.unsubscribe') {
        result = subscriptions.delete(params.subscription);
      } else if (method === 'object.call') {
        calls.push(params);
        if (params.object === 'screen') {
          result = { capture: 'capture-one', status: 'accepted' };
          for (const capture of ['old-capture', 'capture-one']) {
            notify('screen', 'captured', {
              capture,
              width: 320,
              height: 240,
              mime: 'image/png',
              base64: Buffer.from(capture).toString('base64'),
              phase: 'next_rendered_image',
            });
          }
        } else if (params.object === 'tree') {
          result =
            params.method === 'click'
              ? { clicked: true, node: params.params.node }
              : { nodes: [{ node: 'node', class: 'UIElement' }], more: false };
        } else if (params.method === 'settings') {
          result = settings();
        } else if (params.method === 'setAutoskip') {
          autoskip = params.params.enabled;
          result = settings();
        } else if (params.method === 'setDiscoveryLabels') {
          discoveryLabels = params.params.enabled;
          result = settings();
        } else {
          result = { action: 'accepted', status: 'accepted', completionTimeoutMs };
          // Exercise completion arriving before the request acknowledgment.
          if (fatal) {
            notify('runtime', 'fatal', { message: 'native fault', traceback: 'native trace' });
          } else if (!pending) {
            notify('game', 'completed', {
              action: 'accepted',
              status: 'completed',
              state: { kind: 'SELECTING_HAND', score: 42 },
            });
          }
        }
      }
      if (
        withholdFatalReceipt &&
        ((method === 'object.call' && fatal) || method === 'object.unsubscribe')
      )
        return;

      peer.send(JSON.stringify({ jsonrpc: '2.0', id, result }));
    });
  });

  return { url: `http://127.0.0.1:${listener.address().port}`, calls, hellos };
}

test('default connection uses the local endpoint without a token; explicit tokens still pass through', async (t) => {
  const fixture = await server(t);
  let requestedUrl;

  class LocalSocket extends WebSocket {
    constructor(url) {
      requestedUrl = url;
      super(new URL('/rpc', fixture.url.replace('http:', 'ws:')));
    }
  }

  const local = await connectBalatro({ WebSocket: LocalSocket });
  t.after(() => local.close());

  assert.equal(requestedUrl, 'ws://localhost:27121/rpc');
  assert.deepEqual(fixture.hellos, [{ protocol: 1 }]);

  const configured = await connectBalatro({ url: fixture.url, token: 'configured', WebSocket });
  t.after(() => configured.close());

  assert.deepEqual(fixture.hellos[1], { token: 'configured', protocol: 1 });
});

test('playHand retains the optional phase order and handles immediate completion', async (t) => {
  const fixture = await server(t);
  const game = await connectBalatro({ url: fixture.url, token: 'test', WebSocket });
  t.after(() => game.close());

  const card = { ref: 'card' };
  const order = [{ ref: 'blueprint' }, { ref: 'mime' }];

  const result = await game.playHand([card], { endOfRoundJokerOrder: order });

  assert.equal(result.state.score, 42);
  assert.deepEqual(fixture.calls[0].params, {
    cards: [card],
    endOfRoundJokerOrder: order,
    humanDelayMs: 0,
  });
  assert.equal(await game.client.findObject('Balatro'), game);
});

test('autoskip is off unless selected and each connection has independent settings', async (t) => {
  const fixture = await server(t);
  const manual = await connectBalatro({ url: fixture.url, token: 'test', WebSocket });
  const automatic = await connectBalatro({
    url: fixture.url,
    token: 'test',
    WebSocket,
    autoskip: true,
  });
  t.after(() => manual.close());
  t.after(() => automatic.close());

  assert.deepEqual(await manual.settings(), { autoskip: false, discoveryLabels: false });
  assert.deepEqual(await automatic.settings(), { autoskip: true, discoveryLabels: false });

  await automatic.setAutoskip(false);

  assert.deepEqual(await automatic.settings(), { autoskip: false, discoveryLabels: false });
});

test('discovery labels are a queryable session preference used by ordinary presentation', async (t) => {
  const fixture = await server(t);
  const normal = await connectBalatro({ url: fixture.url, token: 'test', WebSocket });
  const onboarding = await connectBalatro({
    url: fixture.url,
    token: 'test',
    WebSocket,
    discoveryLabels: true,
  });
  t.after(() => normal.close());
  t.after(() => onboarding.close());

  const state = {
    jokers: [{ ref: 'j', name: 'Joker', discoveryLabel: 'Non découvert', description: '+4 Mult' }],
  };

  assert.equal((await normal.settings()).discoveryLabels, false);
  assert.equal((await onboarding.settings()).discoveryLabels, true);
  assert.equal(normal.present(state).jokers[0].name, 'Joker');
  assert.equal(onboarding.present(state).jokers[0].name, 'Non découvert');

  await normal.setDiscoveryLabels(true);
  await onboarding.setDiscoveryLabels(false);

  assert.equal(normal.present(state).jokers[0].name, 'Non découvert');
  assert.equal(onboarding.present(state).jokers[0].name, 'Joker');
  assert.equal((await normal.settings()).discoveryLabels, true);
  assert.equal(state.jokers[0].name, 'Joker');

  await normal.setAutoskip(true);

  assert.deepEqual(await normal.settings(), { autoskip: true, discoveryLabels: true });

  const fresh = await connectBalatro({ url: fixture.url, token: 'test', WebSocket });
  t.after(() => fresh.close());

  assert.deepEqual(await fresh.settings(), { autoskip: false, discoveryLabels: false });
});

test('ordinary play does not request any phase-specific Joker decision', async (t) => {
  const fixture = await server(t);
  const game = await connectBalatro({ url: fixture.url, token: 'test', WebSocket });
  t.after(() => game.close());

  await game.playHand([{ ref: 'card' }]);

  assert.deepEqual(fixture.calls[0].params, { cards: [{ ref: 'card' }], humanDelayMs: 0 });
});

test('hand sorting submits a native sort mode and waits for its completion', async (t) => {
  const fixture = await server(t);
  const game = await connectBalatro({ url: fixture.url, token: 'test', WebSocket });
  t.after(() => game.close());

  const result = await game.sortHand('suit');

  assert.equal(result.status, 'completed');
  assert.equal(fixture.calls[0].method, 'sortHand');
  assert.deepEqual(fixture.calls[0].params, { by: 'suit', humanDelayMs: 0 });
});

test('BalatroSceneTree uses wrapped-root lookup independently of gameplay', async (t) => {
  const fixture = await server(t);
  const game = await connectBalatro({ url: fixture.url, token: 'test', WebSocket });
  t.after(() => game.close());
  const tree = await game.client.root('BalatroSceneTree');

  const found = await tree.query({ button: 'new_native_action' });
  const clicked = await tree.click({ node: found.nodes[0].node });

  assert.equal(clicked.clicked, true);
  assert.deepEqual(fixture.calls[0].params, { button: 'new_native_action' });
  assert.deepEqual(fixture.calls[1].params, { node: 'node' });
  assert.equal(tree.remote.id, 'tree');
});

test('screen capture waits for its own image and matches the standard decoded JS result', async (t) => {
  const fixture = await server(t);
  const game = await connectBalatro({ url: fixture.url, token: 'test', WebSocket });
  t.after(() => game.close());
  const screen = await game.client.root('LoveScreen');

  const shot = await screen.capture();
  const convenience = await game.screenshot();

  assert.equal(shot.image.toString(), 'capture-one');
  assert.equal(convenience.image.toString(), 'capture-one');
  assert.equal(shot.mime, 'image/png');
  assert.equal(shot.phase, 'next_rendered_image');
  assert.equal(shot.width, 320);
});

test('a native fatal error interrupts the wait with its traceback and stops queued input', async (t) => {
  const fixture = await server(t, { fatal: true });
  const game = await connectBalatro({ url: fixture.url, token: 'test', WebSocket });
  t.after(() => game.close());
  const first = game.playHand([{ ref: 'card' }]);
  const queued = game.discard([{ ref: 'other' }]);

  await assert.rejects(first, (error) => error.fatal.traceback === 'native trace');
  await assert.rejects(queued, /Balatro stopped: native fault/);

  assert.equal(fixture.calls.length, 1);

  game.resumeQueue();

  await assert.rejects(game.selectBlind(), /Balatro stopped/);
  await assert.rejects(game.state(), (error) => error.fatal.traceback === 'native trace');

  assert.equal(fixture.calls.length, 1);
});

test('human delay uses the StS2 call shape, defaults to zero and travels with game work', async (t) => {
  const fixture = await server(t);
  const game = await connectBalatro({ url: fixture.url, token: 'test', WebSocket });
  t.after(() => game.close());

  await game.cashOut();

  assert.equal(fixture.calls.findLast((call) => call.method === 'cashOut').params.humanDelayMs, 0);

  game.setHumanDelay(400);
  await game.cashOut();

  assert.equal(
    fixture.calls.findLast((call) => call.method === 'cashOut').params.humanDelayMs,
    400,
  );

  await game.state();

  assert.deepEqual(fixture.calls.findLast((call) => call.method === 'state').params, {});
  assert.throws(() => game.setHumanDelay(-1), RangeError);
  assert.throws(() => game.setHumanDelay(Infinity), RangeError);
  assert.throws(() => game.setHumanDelay(0.5), RangeError);

  game.setHumanDelay();
  await game.cashOut();

  assert.equal(fixture.calls.findLast((call) => call.method === 'cashOut').params.humanDelayMs, 0);
});

test('gameplay waiting uses the accepted service allowance without retrying work', async (t) => {
  const fixture = await server(t, { pending: true, completionTimeoutMs: 15 });
  const game = await connectBalatro({ url: fixture.url, token: 'test', WebSocket });
  t.after(() => game.close());

  await assert.rejects(game.cashOut(), /Game wait timed out; do not replay/);

  assert.equal(fixture.calls.filter((call) => call.method === 'cashOut').length, 1);
});

test(
  'native fatal cause wins over an outstanding receipt and unresponsive unsubscribe',
  { timeout: 1000 },
  async (t) => {
    const fixture = await server(t, { fatal: true, withholdFatalReceipt: true });
    const game = await connectBalatro({ url: fixture.url, token: 'test', WebSocket });
    t.after(() => game.close());
    const first = game.playHand([]);
    const queued = game.cashOut();

    await Promise.all(
      [first, queued].map((result) =>
        assert.rejects(result, (error) => {
          assert.match(error.message, /native fault/);
          assert.equal(error.fatal.traceback, 'native trace');

          return true;
        }),
      ),
    );
    assert.equal(fixture.calls.filter((call) => call.method === 'playHand').length, 1);
    assert.equal(fixture.calls.filter((call) => call.method === 'cashOut').length, 0);
  },
);

test('semantic-only games support ordinary calls without developer endpoints', async (t) => {
  const fixture = await server(t, { developerMode: false });
  const game = await connectBalatro({ url: fixture.url, WebSocket });
  t.after(() => game.close());

  const result = await game.playHand([{ ref: 'card' }]);

  assert.equal(result.state.score, 42);
  assert.equal(await game.client.findObject('Balatro'), game);
});
