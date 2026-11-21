import { test } from 'node:test';
import assert from 'node:assert/strict';
import { connectBalatro } from '../../client/balatro.mjs';
import { launchFixture } from './fixture.mjs';

test('LoveScript evaluates through the named wrapper and direct RPC without driving gameplay', async (t) => {
  const fixture = await launchFixture(t);
  const port = Number((await fixture.waitFor(/FIXTURE_READY (\d+)/))[1]);
  const game = await connectBalatro({ url: `http://127.0.0.1:${port}`, token: 'fixture-only' });
  t.after(() => game.close());
  const script = await game.client.root('LoveScript');
  const before = await game.state();
  const source = `
function evaluate(bindings)
    return {version = love.getVersion(), count = bindings.count, flag = bindings.flag,
        list = bindings.list, nested = bindings.nested}
end`;
  const bindings = { count: 0, flag: false, list: [], nested: { value: null } };

  assert.deepEqual(await script.evaluate({ source, bindings }), { version: 11, ...bindings });
  assert.deepEqual(await script.remote.invoke('evaluate', { source, bindings }), {
    version: 11,
    ...bindings,
  });
  assert.equal(await script.evaluate({ source: 'function evaluate(b) end' }), null);
  assert.deepEqual(await game.state(), before);

  await assert.rejects(
    script.evaluate({ source: 'function evaluate(b) error("controlled evaluation fault") end' }),
    (error) => error.code === -32603 && /controlled evaluation fault/.test(error.message),
  );
  await assert.rejects(
    script.evaluate({ source: 'function evaluate(b) coroutine.yield() end' }),
    (error) => error.code === -32602 && /synchronously/.test(error.message),
  );
  await assert.rejects(
    script.evaluate({ source: 'function evaluate(b) return {value = function() end} end' }),
    (error) => error.code === -32010,
  );
  assert.equal(await script.evaluate({ source: 'function evaluate(b) return 42 end' }), 42);
});

test('oversized escaped evaluation results fail without losing the connection or repeating writes', async (t) => {
  const fixture = await launchFixture(t);
  const port = Number((await fixture.waitFor(/FIXTURE_READY (\d+)/))[1]);
  const game = await connectBalatro({ url: `http://127.0.0.1:${port}`, token: 'fixture-only' });
  t.after(() => game.close());
  const script = await game.client.root('LoveScript');

  await assert.rejects(
    script.evaluate({
      source: `function evaluate(b)
    _G.stagehand_fixture_writes = (_G.stagehand_fixture_writes or 0) + 1
    return string.rep('"', 4 * 1024 * 1024)
end`,
    }),
    (error) => error.code === -32010 && /message limit/.test(error.message),
  );
  assert.equal(
    await script.evaluate({ source: 'function evaluate(b) return stagehand_fixture_writes end' }),
    1,
  );
  assert.equal((await game.state()).ready, true);
});

test('binary Lua values and keys fail without sending invalid WebSocket text', async (t) => {
  const fixture = await launchFixture(t);
  const port = Number((await fixture.waitFor(/FIXTURE_READY (\d+)/))[1]);
  const game = await connectBalatro({ url: `http://127.0.0.1:${port}`, token: 'fixture-only' });
  t.after(() => game.close());
  const script = await game.client.root('LoveScript');

  for (const expression of ['string.char(255)', '{[string.char(255)] = "binary key"}']) {
    await assert.rejects(
      script.evaluate({ source: `function evaluate(b) return ${expression} end` }),
      (error) => error.code === -32010 && /UTF-8/.test(error.message),
    );
    assert.equal(
      await script.evaluate({ source: 'function evaluate(b) return "still connected" end' }),
      'still connected',
    );
  }
});
