import { test } from 'node:test';
import assert from 'node:assert/strict';
import { connectBalatro } from '../../client/balatro.mjs';
import { launchFixture } from './fixture.mjs';

test('a separate observer follows native changed events without taking driver ownership', async (t) => {
  const fixture = await launchFixture(t);
  const port = Number((await fixture.waitFor(/FIXTURE_READY (\d+)/))[1]);
  const url = `http://127.0.0.1:${port}`;
  const driver = await connectBalatro({ url, token: 'fixture-only' });
  const observer = await connectBalatro({ url, token: 'fixture-only' });
  t.after(() => driver.close());
  t.after(() => observer.close());

  const first = await observer.spectate();

  assert.equal(first.view.kind, 'FIXTURE');

  const next = observer.spectate({ after: first });
  await driver.invoke('setPosition', { kind: 'SHOP', ready: false, money: 20 });
  await driver.invoke('setPosition', {
    kind: 'PLANET_PACK',
    ready: true,
    money: 16,
    pack: { choicesLeft: 1, cards: [{ ref: 'planet', name: 'Earth' }] },
  });
  const frame = await next;

  assert.equal(frame.boundary, 'choice_required');
  assert.equal(frame.view.money, 16);
  assert.equal(frame.state.pack.cards[0].ref, 'planet');
  assert.equal(await observer.spectate({ after: frame, timeoutMs: 20 }), null);
  assert.equal((await driver.state()).pack.choicesLeft, 1);
});
