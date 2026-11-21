import { test } from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { Balatro } from '../client/balatro.mjs';

function fixture(initial, { subscribeGate, read, onSubscribed } = {}) {
  let state = initial;
  const client = new EventEmitter();
  const listeners = new Set();
  const calls = [];
  let unsubscribed = 0;

  client.subscribe = async (_object, event, listener) => {
    assert.equal(event, 'changed');

    if (subscribeGate) await subscribeGate;

    listeners.add(listener);
    onSubscribed?.();

    return async () => {
      listeners.delete(listener);
      unsubscribed++;
    };
  };

  client.request = async (method, params) => {
    calls.push(params.method);

    assert.equal(method, 'object.call');
    assert.equal(params.method, 'state', 'Spectating must not submit input or normalization');

    return read ? read(state) : structuredClone(state);
  };

  return {
    game: new Balatro(client, 'game'),
    client,
    listeners,
    calls,
    unsubscribed: () => unsubscribed,
    update(next) {
      state = next;

      for (const listener of listeners) listener({ value: structuredClone(state) });
    },
  };
}

const position = (money = 10) => ({
  kind: 'SELECTING_HAND',
  ready: true,
  money,
  handsLeft: 3,
  hand: [{ ref: 'one', rank: '9', suit: 'Hearts', chips: 9 }],
  choices: [],
});

test('spectate gives a rich baseline and then changed settled positions without input', async () => {
  let sawBusy;
  const busyRead = new Promise((resolve) => (sawBusy = resolve));
  const source = fixture(position(), {
    read: (state) => {
      if (!state.ready) sawBusy();

      return structuredClone(state);
    },
  });
  const first = await source.game.spectate();

  assert.equal(first.position, 1);
  assert.equal(first.boundary, 'settled_position');
  assert.equal(first.view.money, 10);
  assert.deepEqual(first.state, position());

  const next = source.game.spectate({ after: first });
  source.update({ ...position(9), ready: false });
  await busyRead;
  source.update(position(8));
  const second = await next;

  assert.equal(second.position, 2);
  assert.equal(second.view.money, 8);
  assert.equal(source.listeners.size, 0);
  assert.ok(source.calls.every((method) => method === 'state'));
});

test('a change during an in-flight stale read is not lost', async () => {
  let release, entered;
  const reading = new Promise((resolve) => (entered = resolve));
  let reads = 0;
  const source = fixture(
    { ...position(), ready: false },
    {
      read: (state) => {
        if (++reads > 1) return structuredClone(state);

        entered();

        return new Promise((resolve) => (release = () => resolve(structuredClone(state))));
      },
    },
  );
  const waiting = source.game.spectate();
  await reading;
  source.update(position(20));
  release();
  const frame = await waiting;

  assert.equal(frame.state.money, 20);
  assert.equal(reads, 2);
  assert.equal(source.listeners.size, 0);
});

test('idle ignores widget, typing and object-key-order churn but preserves real selections', async () => {
  const initial = {
    ...position(),
    dialogue: 'Typing',
    ui: { overlay: false },
    choices: [{ ref: 'widget', label: 'Play', action: 'play', enabled: true }],
  };
  const source = fixture(initial);
  const first = await source.game.spectate();
  source.update({
    ...initial,
    dialogue: 'Typing more',
    hand: [{ suit: 'Hearts', chips: 9, rank: '9', ref: 'one' }],
    ui: { overlay: false, rect: [4, 5, 6, 7] },
    choices: [{ ref: 'new-widget', label: 'Play', action: 'play', enabled: true, rect: [1, 2] }],
  });
  assert.equal(await source.game.spectate({ after: first, timeoutMs: 5 }), null);
  assert.equal(source.calls.length, 2, 'No polling while idle');

  source.update({ ...initial, hand: [{ ...initial.hand[0], highlighted: true }] });
  const selected = await source.game.spectate({ after: first });

  assert.equal(selected.position, 2);
  assert.equal(selected.view.hand[0].selected, true);
});

test('native packs and tutorial or earned-notice choices are visible without autoskip', async () => {
  const initial = {
    kind: 'PLANET_PACK',
    ready: true,
    pack: { choicesLeft: 1, cards: [{ ref: 'planet', name: 'Earth' }] },
  };
  const source = fixture(initial);
  const first = await source.game.spectate();

  assert.equal(first.boundary, 'choice_required');
  assert.equal(first.view.pack.choicesLeft, 1);

  source.update({
    kind: 'MENU',
    ready: true,
    ui: { overlay: true },
    notice: { kind: 'unlock', text: 'Earned!', advance: 'continue' },
    choices: [{ ref: 'continue', action: 'continue_unlock', enabled: true }],
  });
  const earned = await source.game.spectate();

  assert.equal(earned.boundary, 'choice_required');
  assert.equal(earned.view.notice.text, 'Earned!');

  source.update({
    kind: 'SELECTING_HAND',
    ready: true,
    ui: { tutorial: true },
    dialogue: 'Choose an observed card',
    choices: [{ ref: 'next', action: 'tutorial_next', enabled: true }],
  });
  const tutorial = await source.game.spectate();

  assert.equal(tutorial.boundary, 'choice_required');
  assert.equal(tutorial.view.dialogue, 'Choose an observed card');
  assert.ok(source.calls.every((method) => method === 'state'));
});

test('continuations belong to one observer and a single active wait', async () => {
  const source = fixture(position());
  const first = await source.game.spectate();
  const waiting = source.game.spectate({ after: first, timeoutMs: 20 });
  await assert.rejects(source.game.spectate(), /already waiting/);

  assert.equal(await waiting, null);

  await assert.rejects(source.game.spectate({ after: { ...first } }), /last frame/);
  source.update(position(20));
  const second = await source.game.spectate();

  assert.equal(second.position, 2);

  await assert.rejects(source.game.spectate({ after: first }), /last frame/);
});

test('abort, disconnect, endpoint removal and native errors reject and detach listeners', async () => {
  for (const mode of ['abort', 'close', 'removed', 'fatal', 'error', 'observation']) {
    let entered;
    const subscribed = new Promise((resolve) => (entered = resolve));
    const source = fixture({ ...position(), ready: false }, { onSubscribed: () => entered() });
    const control = new AbortController();
    const waiting = source.game.spectate({ signal: control.signal });
    const rejected = assert.rejects(waiting);
    await subscribed;
    if (mode === 'abort') control.abort();
    else if (mode === 'close') source.client.emit('close');
    else if (mode === 'removed')
      source.client.emit('notification', { method: 'objects.removed', params: { object: 'game' } });
    else if (mode === 'fatal') source.client.emit('runtimeFatal', new Error('native fault'));
    else if (mode === 'error') source.client.emit('error', new Error('decode fault'));
    else source.update({ kind: 'ERROR', ready: false, error: 'Observation failed' });
    await rejected;

    assert.equal(source.listeners.size, 0);

    for (const event of ['close', 'notification', 'runtimeFatal', 'error'])
      assert.equal(source.client.listenerCount(event), 0);
  }
});

test('timeout or abort during setup/read cleans up without hiding RPC failures', async () => {
  let release;
  const gate = new Promise((resolve) => (release = resolve));
  const source = fixture(position(), { subscribeGate: gate });

  assert.equal(await source.game.spectate({ timeoutMs: 5 }), null);

  release();
  await new Promise((resolve) => setImmediate(resolve));

  assert.equal(source.listeners.size, 0);
  assert.equal(source.unsubscribed(), 1);

  const reading = fixture(position(), { read: () => new Promise(() => {}) });

  assert.equal(await reading.game.spectate({ timeoutMs: 5 }), null);
  assert.equal(reading.listeners.size, 0);

  const broken = fixture(position(), { read: () => Promise.reject(new Error('RPC failed')) });
  await assert.rejects(broken.game.spectate(), /RPC failed/);

  assert.equal(broken.listeners.size, 0);

  const cancelled = new AbortController();
  cancelled.abort();
  await assert.rejects(source.game.spectate({ signal: cancelled.signal }), { name: 'AbortError' });

  assert.equal(source.listeners.size, 0);

  for (const timeoutMs of [-1, NaN, Infinity, 2147483648])
    await assert.rejects(source.game.spectate({ timeoutMs }), RangeError);
});
