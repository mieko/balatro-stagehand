import { createRequire } from 'node:module';
import { present } from './present.mjs';
import { observationKey, observationBoundary, waitForObservation } from './spectator.mjs';
export { present } from './present.mjs';

const { connect, RemoteObject, forwardMethods } = await import(
  createRequire(import.meta.url).resolve('godot-stagehand')
);

const facades = new WeakMap();

async function completion(remote, event, submit, matches, timeoutMs = 130_000) {
  let accepted;
  const early = [];

  let resolve, reject;
  const done = new Promise((yes, no) => {
    resolve = yes;
    reject = no;
  });
  done.catch(() => {});

  const closed = () => reject(new Error('Disconnected; accepted game work was not cancelled'));
  const fatal = (error) => reject(error);
  remote.client.once('close', closed);
  remote.client.once('runtimeFatal', fatal);

  const timedOut = () => reject(new Error('Game wait timed out; do not replay automatically'));
  let timer = setTimeout(timedOut, timeoutMs);
  let unsubscribe,
    finished = false;

  try {
    const subscribing = remote.subscribe(event, ({ value }) => {
      if (!accepted) {
        early.push(value);
      } else if (matches(value, accepted)) {
        resolve(value);
      }
    });

    subscribing.then(
      (stop) => {
        unsubscribe = stop;
        if (finished) void stop().catch(() => {});
      },
      () => {},
    );
    await Promise.race([subscribing, done]);

    accepted = await Promise.race([submit(), done]);
    if (Number.isFinite(accepted.completionTimeoutMs) && accepted.completionTimeoutMs > 0) {
      clearTimeout(timer);
      timer = setTimeout(timedOut, accepted.completionTimeoutMs);
    }

    for (const value of early) {
      if (matches(value, accepted)) {
        resolve(value);
      }
    }

    return await done;
  } catch (error) {
    throw remote.client.fatalError ?? error;
  } finally {
    finished = true;
    clearTimeout(timer);
    remote.client.off('close', closed);
    remote.client.off('runtimeFatal', fatal);
    if (unsubscribe) {
      void unsubscribe().catch(() => {});
    }
  }
}

export class Balatro extends RemoteObject {
  #queue = Promise.resolve();
  #discoveryLabels = false;
  #humanDelayMs = 0;
  #spectatorLast;
  #spectatorWaiting = false;
  #spectatorPosition = 0;

  invoke(method, params = {}) {
    if (this.client.fatalError) {
      return Promise.reject(this.client.fatalError);
    }

    return super.invoke(method, params);
  }

  state() {
    return this.invoke('state');
  }

  async spectate({ after, ...options } = {}) {
    if (this.#spectatorWaiting)
      throw new Error('This observer is already waiting; await or abort that spectate call');

    if (after !== undefined && after !== this.#spectatorLast?.frame)
      throw new Error(
        'Pass the last frame returned by this observer; reconnect starts a new baseline',
      );

    this.#spectatorWaiting = true;
    try {
      const state = await waitForObservation(
        this,
        (state) => state.ready && observationKey(state) !== this.#spectatorLast?.key,
        options,
      );
      if (state === null) return null;

      const frame = {
        position: ++this.#spectatorPosition,
        boundary: observationBoundary(state),
        view: this.present(state),
        state,
      };
      this.#spectatorLast = { frame, key: observationKey(state) };
      return frame;
    } finally {
      this.#spectatorWaiting = false;
    }
  }

  inspectCard(card) {
    return this.invoke('inspectCard', { ref: card.ref ?? card });
  }

  blinds() {
    return this.invoke('blinds');
  }

  handTypes() {
    return this.invoke('handTypes');
  }

  deck(params = {}) {
    return this.invoke('deck', params);
  }

  runOptions() {
    return this.invoke('runOptions');
  }

  async settings() {
    const settings = await this.invoke('settings');
    this.#discoveryLabels = settings.discoveryLabels;

    return settings;
  }

  options() {
    return this.invoke('options');
  }

  setOptions(params) {
    return this.invoke('setOptions', params);
  }

  setAutoskip(enabled) {
    return this.invoke('setAutoskip', { enabled });
  }

  async setDiscoveryLabels(enabled) {
    const settings = await this.invoke('setDiscoveryLabels', { enabled });
    this.#discoveryLabels = settings.discoveryLabels;

    return settings;
  }

  info() {
    return this.invoke('info');
  }

  setHumanDelay(milliseconds = 0) {
    if (!Number.isInteger(milliseconds) || milliseconds < 0 || milliseconds > 5000) {
      throw new RangeError('Human delay must be an integer in 0..5000 milliseconds');
    }

    this.#humanDelayMs = milliseconds;
  }

  recover() {
    return this.invoke('operation');
  }

  present(result, options) {
    return present(result, { ...options, discoveryLabels: this.#discoveryLabels });
  }

  close() {
    this.client.close();
  }

  resumeQueue() {
    this.#queue = Promise.resolve();
  }

  #act(method, params = {}) {
    const run = async () => {
      if (this.client.fatalError) {
        throw this.client.fatalError;
      }

      const result = await completion(
        this,
        'completed',
        () => this.invoke(method, { ...params, humanDelayMs: this.#humanDelayMs }),
        (value, accepted) => value.action === accepted.action,
      );
      if (!['completed', 'choice_required'].includes(result.status)) {
        throw Object.assign(new Error(result.error ?? result.status), { outcome: result });
      }
      return result;
    };
    const result = this.#queue.then(run);
    this.#queue = result;
    result.catch(() => {});
    return result;
  }

  startRun(params = {}) {
    return this.#act('startRun', params);
  }

  decision() {
    return this.#act('decision');
  }

  continueRun() {
    return this.#act('continueRun');
  }

  selectBlind() {
    return this.#act('selectBlind');
  }

  skipBlind() {
    return this.#act('skipBlind');
  }

  rerollBoss() {
    return this.#act('rerollBoss');
  }

  continueEndless() {
    return this.#act('continueEndless');
  }

  returnToMenu() {
    return this.#act('returnToMenu');
  }

  selectCards(cards) {
    return this.#act('selectCards', { cards });
  }

  sortHand(by) {
    return this.#act('sortHand', { by });
  }

  playHand(cards, options = {}) {
    return this.#act('playHand', { cards, ...options });
  }

  discard(cards) {
    return this.#act('discard', { cards });
  }

  cashOut() {
    return this.#act('cashOut');
  }

  leaveShop() {
    return this.#act('leaveShop');
  }

  buy(items) {
    return this.#act('buy', { items: Array.isArray(items) ? items : [items] });
  }

  buyAndUse(card, targets) {
    return this.#act('buyAndUse', { ref: card.ref ?? card, targets });
  }

  sell(card) {
    return this.#act('sell', { ref: card.ref ?? card });
  }

  useConsumable(card, targets) {
    return this.#act('useConsumable', { ref: card.ref ?? card, targets });
  }

  pickPackCard(card, targets) {
    return this.#act('pickPackCard', { ref: card.ref ?? card, targets });
  }

  skipPack() {
    return this.#act('skipPack');
  }

  rerollShop() {
    return this.#act('rerollShop');
  }

  reorderJokers(cards) {
    return this.#act('reorderJokers', { cards });
  }

  reorderHand(cards) {
    return this.#act('reorderHand', { cards });
  }

  reorderConsumables(cards) {
    return this.#act('reorderConsumables', { cards });
  }

  choose(choice) {
    return this.#act('choose', { ref: choice.ref ?? choice });
  }

  async screenshot() {
    const screen = await this.client.builtin('LoveScreen');

    return screen.capture();
  }
}

export const balatroWrappers = {
  Balatro: (remote) => {
    let objects = facades.get(remote.client);
    if (!objects) {
      facades.set(remote.client, (objects = new Map()));
    }

    if (!objects.has(remote.id)) {
      objects.set(remote.id, new Balatro(remote.client, remote.id));
    }

    return objects.get(remote.id);
  },
  LoveRuntime: forwardMethods(['info', 'quit']),
  LoveScript: forwardMethods(['evaluate']),
  LoveInput: forwardMethods(['press', 'release']),
  LoveScreen: (remote) => ({
    ...forwardMethods(['dimensions'])(remote),
    async capture(params = {}) {
      const shot = await completion(
        remote,
        'captured',
        () => remote.invoke('capture', params),
        (value, accepted) => value.capture === accepted.capture,
        10_000,
      );
      const { base64, ...metadata } = shot;

      return { ...metadata, image: Buffer.from(base64, 'base64') };
    },
  }),
  BalatroSceneTree: forwardMethods(['roots', 'inspect', 'children', 'query', 'click']),
};

export async function connectBalatro(url, options = {}) {
  const client = await connect(url, {
    ...options,
    wrappers: { ...balatroWrappers, ...options.wrappers },
  });
  try {
    const game = await client.findObject('Balatro');
    if (!game) {
      throw new Error('Balatro endpoint is unavailable');
    }

    const runtime = await client.builtin('LoveRuntime');
    await runtime.remote.subscribe('fatal', ({ value }) => {
      const error = Object.assign(new Error(`Balatro stopped: ${value.message}`), { fatal: value });
      client.fatalError = error;
      client.emit('runtimeFatal', error);
    });
    if (options.autoskip !== undefined) {
      await game.setAutoskip(options.autoskip);
    }

    if (options.discoveryLabels !== undefined) {
      await game.setDiscoveryLabels(options.discoveryLabels);
    }

    return game;
  } catch (error) {
    client.close();
    throw error;
  }
}
