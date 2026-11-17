import { test } from 'node:test';
import assert from 'node:assert/strict';
import { launchFixture } from './fixture.mjs';

test(
  'service card actions use installed native models and eligibility checks',
  { timeout: 15000 },
  async (t) => {
    const fixture = await launchFixture(t, { native: true });
    const result = await fixture.waitFor(/NATIVE_MODELS_OK (\d+) (\d+)/);
    assert.match(fixture.output(), /NATIVE_DISCOVERY_OK/);
    assert.match(fixture.output(), /NATIVE_SORT_OK/);
    assert.match(fixture.output(), /NATIVE_CHIP_SCOPE_OK/);
    assert.match(fixture.output(), /NATIVE_TARGETING_OK/);
    assert.match(fixture.output(), /NATIVE_RESULTS_OK/);
    assert.match(fixture.output(), /NATIVE_TREE_OK/);
    assert.match(fixture.output(), /NATIVE_TOOLTIP_LIFETIME_OK 1000/);
    assert.ok(Number(result[1]) > 0);
    assert.ok(Number(result[2]) > Number(result[1]));
    t.diagnostic(
      `${result[1]} installed consumable models; ${result[2]} native eligibility/service cases`,
    );
    assert.equal(await fixture.exited, 0, fixture.output());
  },
);
