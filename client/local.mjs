import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { connectBalatro } from './balatro.mjs';

const require = createRequire(import.meta.url);

export async function connectLocal(options = {}) {
  const filename = new URL('../.local/session.json', import.meta.url);
  const session = JSON.parse(await readFile(filename, 'utf8'));
  return connectBalatro({
    WebSocket: globalThis.WebSocket ?? require('ws'),
    ...options,
    url: session.url,
    token: session.token,
  });
}
