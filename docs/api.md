# Stagehand API in Balatro

Fetch the game's Stagehand HTTP base address to read the Markdown index of the
client and references. Use the same address to download the matching client.

```sh
curl -fsS http://localhost:27121/client.mjs -o balatro-stagehand.mjs
```

Use Node.js 22 or newer to import it. The same module exports the generic Stagehand
client and the [Balatro gameplay helpers](./game.md).

```js
import { connect } from './balatro-stagehand.mjs';

const client = await connect('http://localhost:27121', { token: process.env.STAGEHAND_TOKEN });
try {
  console.log(await client.objects());
  const game = await client.root('Balatro');
  console.log(await game.invoke('state'));
} finally {
  client.close();
}
```

Supply your game's access token when required. The default loopback listener accepts
a connection without a token. Remote listening requires authentication.

The generic client provides `objects()`, `root(label)` for a named root,
`findObject(label)` for an optional root, and `close()`. A root supports
`describe()`, `observe()`, `invoke(method, params)` and
`subscribe(event, listener)`. The awaited subscription returns a function to
unsubscribe. `Registry` is always available and lists the registered roots.

Balatro's registered operations use JSON data and the [game reference](./game.md)
describes the engine-specific roots. Some core exports target Godot's native value
codec and builtins such as `Object`, `Screen`, `Input` and `Script`. Those APIs
belong to Godot integrations. Balatro uses the separate LÖVE services described in
its game reference.

## Wire protocol 1

Given the HTTP or HTTPS base address, open `/rpc` on the same host and port
using `ws` or `wss`. The listener rejects upgrades carrying an `Origin` header.
Use a native client without that header. WebSocket version 13 carries UTF-8
JSON-RPC 2.0 text messages up to 8 MiB. The server supports continuation frames and
rejects binary messages and frame extensions.

The discovery page at `/` and the files it links are public downloads. The
WebSocket handshake establishes the transport. Start the RPC session within
five seconds of the connection:

```json
{
  "jsonrpc": "2.0",
  "id": "1",
  "method": "session.hello",
  "params": { "protocol": 1 }
}
```

Add `token` to the parameters when the listener requires authentication.
The hello result includes the protocol, the running instance identity, a clock,
engine metadata and the registered endpoint descriptors. Descriptors have opaque
`id`, `label`, `kind`, `operations`, `operation_info`, `events` and an optional
API `version`. Use the `id` to address a registered object.

| Method               | Named parameters                         | Result                       |
| -------------------- | ---------------------------------------- | ---------------------------- |
| `session.hello`      | `protocol:1`, optional `token`           | Session snapshot             |
| `objects.list`       | none                                     | Fresh registered descriptors |
| `object.describe`    | `object` handle                          | Descriptor                   |
| `object.observe`     | `object` handle                          | `{object,value,clock}`       |
| `object.call`        | `object`, `method`, optional `params:{}` | Registered operation's value |
| `object.subscribe`   | `object`, `event`                        | Ready subscription ID        |
| `object.unsubscribe` | `subscription`                           | Whether removed              |

Published events arrive as `object.event` notifications with
`{subscription,object,event,value,clock}`. Subscriptions belong to the connection.
Native work may survive a disconnect or timeout. Inspect the current position
before retrying a gameplay command. See the [Balatro game reference](./game.md)
for completion and recovery.
