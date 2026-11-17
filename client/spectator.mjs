const IDLE = Symbol('idle');

function observationError(state) {
  if (state?.kind === 'ERROR' || state?.error) {
    return new Error(state.error ?? 'Native observation failed');
  }
}

function stableJSON(value) {
  return JSON.stringify(value, (_key, value) => {
    if (value && typeof value === 'object' && !Array.isArray(value)) {
      return Object.fromEntries(Object.entries(value).sort(([a], [b]) => a.localeCompare(b)));
    }
    return value;
  });
}

export function observationKey(state) {
  const { ui, dialogue, choices, notice, ...position } = state;
  position.choices = Array.isArray(choices)
    ? choices
        .map(({ action, label, enabled, selected }) =>
          stableJSON({ action, label, enabled, selected }),
        )
        .sort()
    : choices;
  if (notice != null) {
    const { advance, ...facts } = notice;
    position.notice = facts;
  } else if (notice === null) position.notice = null;

  // UI container identity can churn; its decision context still matters.
  position.ui = ui && { overlay: ui.overlay, tutorial: ui.tutorial, menu: ui.menu };

  return stableJSON(position);
}

export function observationBoundary(state) {
  return state.pack || state.notice || state.ui?.overlay || state.ui?.tutorial
    ? 'choice_required'
    : 'settled_position';
}

export async function waitForObservation(remote, predicate, { timeoutMs = 30_000, signal } = {}) {
  if (!Number.isFinite(timeoutMs) || timeoutMs < 0 || timeoutMs > 2147483647) {
    throw new RangeError('timeoutMs must be a finite nonnegative 32-bit duration');
  }

  signal?.throwIfAborted();
  if (remote.client.fatalError) throw remote.client.fatalError;

  let wake, unsubscribe, rejectStop, finishIdle;
  let finished = false;
  const stopped = new Promise((resolve, reject) => {
    finishIdle = resolve;
    rejectStop = reject;
  });
  const timer = setTimeout(() => finishIdle(IDLE), timeoutMs);
  const closed = () => rejectStop(new Error('Stagehand disconnected while spectating'));
  const failed = (error) => rejectStop(error);
  const aborted = () => rejectStop(signal.reason);
  const removed = (item) => {
    if (item.method === 'objects.removed' && item.params.object === remote.id)
      rejectStop(new Error('Observation endpoint was removed'));
  };
  const changed = ({ value }) => {
    const error = observationError(value);
    if (error) rejectStop(error);
    else wake?.();
  };
  remote.client.on('close', closed);
  remote.client.on('runtimeFatal', failed);
  remote.client.on('error', failed);
  remote.client.on('notification', removed);
  signal?.addEventListener('abort', aborted, { once: true });

  try {
    const setup = remote.subscribe('changed', changed).then((cancel) => {
      if (finished) void cancel().catch(() => {});
      else unsubscribe = cancel;
    });
    if ((await Promise.race([setup, stopped])) === IDLE) return null;

    while (true) {
      const notified = new Promise((resolve) => (wake = resolve));
      const state = await Promise.race([remote.state(), stopped]);
      if (state === IDLE) return null;

      const error = observationError(state);
      if (error) throw error;
      if (predicate(state)) return state;
      if ((await Promise.race([notified, stopped])) === IDLE) return null;
    }
  } finally {
    finished = true;
    clearTimeout(timer);
    remote.client.off('close', closed);
    remote.client.off('runtimeFatal', failed);
    remote.client.off('error', failed);
    remote.client.off('notification', removed);
    signal?.removeEventListener('abort', aborted);
    // Detach local delivery immediately; remote acknowledgment cannot extend a wait.
    if (unsubscribe) void unsubscribe().catch(() => {});
  }
}
