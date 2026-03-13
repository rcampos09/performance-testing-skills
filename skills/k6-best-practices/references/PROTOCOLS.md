# k6 Protocols — WebSocket & gRPC Reference

Loaded on demand when the user mentions WebSocket, gRPC, or streaming. Contains connection setup, event handling, and common gotchas for non-HTTP protocols.

---

## WebSocket (`k6/ws`)

### Import and Basic Connection

```javascript
import ws from 'k6/ws';
import { check } from 'k6';

export default function() {
  const url     = `wss://${__ENV.WS_HOST || 'echo.websocket.org'}`;
  const params  = {
    tags:    { endpoint: 'ws-chat' },
    headers: { Authorization: `Bearer ${__ENV.TOKEN}` },
  };

  const res = ws.connect(url, params, function(socket) {
    socket.on('open', () => {
      console.log('connected');
      socket.send(JSON.stringify({ type: 'ping', ts: Date.now() }));
    });

    socket.on('message', (data) => {
      const msg = JSON.parse(data);
      check(msg, {
        'pong received':     (m) => m.type === 'pong',
        'latency < 200ms':   (m) => (Date.now() - m.ts) < 200,
      });
      socket.close();   // close after first exchange
    });

    socket.on('error', (e) => {
      console.error(`WebSocket error: ${e.error()}`);
    });

    socket.on('close', () => {
      console.log('disconnected');
    });

    // Heartbeat to keep connection alive during long sessions
    socket.setInterval(() => socket.ping(), 10000);

    // Safety timeout — close if no message after 30s
    socket.setTimeout(() => socket.close(), 30000);
  });

  check(res, { 'ws connected (101)': (r) => r && r.status === 101 });
}
```

### WebSocket Methods

| Method | Description |
|---|---|
| `ws.connect(url, params, callback)` | Open connection; returns Response object |
| `socket.send(data)` | Send text message |
| `socket.sendBinary(data)` | Send binary (ArrayBuffer) |
| `socket.ping()` | Send WebSocket ping |
| `socket.close([code])` | Graceful close (default code 1000) |
| `socket.on(event, fn)` | Register event handler |
| `socket.setInterval(fn, ms)` | Recurring action (e.g., heartbeat) |
| `socket.setTimeout(fn, ms)` | Scheduled action (e.g., safety close) |

### Event Types

| Event | When fired |
|---|---|
| `open` | Connection established |
| `message` | Text message received from server |
| `ping` | Ping received from server |
| `pong` | Pong received after `socket.ping()` |
| `close` | Connection closed |
| `error` | Connection error |

### Common WebSocket Gotchas

**1. Test ends before messages are received**
The default function returns as soon as the callback completes. If you don't block inside the callback (via `setInterval`, `setTimeout`, or waiting for a close event), the test ends immediately.

```javascript
// Wrong — callback returns before any messages arrive
ws.connect(url, params, function(socket) {
  socket.on('open', () => socket.send('hello'));
  // function returns immediately, no time to receive response
});

// Correct — keep connection alive until done
ws.connect(url, params, function(socket) {
  socket.on('open', () => socket.send('hello'));
  socket.on('message', (data) => {
    // process and then close explicitly
    socket.close();
  });
  socket.setTimeout(() => socket.close(), 10000); // safety net
});
```

**2. No error handler — silent failures**
Always register an `error` handler. Without it, connection errors fail silently and you lose diagnostic information.

**3. Binary vs text**
Use `socket.send()` for text/JSON. Use `socket.sendBinary()` for `ArrayBuffer` data. Mixing them causes protocol errors on most servers.

---

## gRPC (`k6/net/grpc`)

### Import and Client Setup

```javascript
import grpc   from 'k6/net/grpc';
import { check } from 'k6';

// Create client once in init context (shared across VUs)
const client = new grpc.Client();

// Load proto files — paths are relative to script location
client.load(
  ['./proto'],               // import paths (directories containing .proto files)
  'helloworld.proto',        // proto file name(s)
  'users.proto',
);

const BASE_URL = __ENV.GRPC_HOST || 'localhost:50051';
```

### Connection and Invocation

```javascript
export default function() {
  // Connect per VU (required — connections are VU-scoped)
  client.connect(BASE_URL, {
    plaintext: true,          // true for local/dev; false for TLS in production
    timeout:   '10s',
  });

  const metadata = { authorization: `Bearer ${__ENV.TOKEN}` };

  // Unary call (request → response)
  const response = client.invoke('helloworld.Greeter/SayHello',
    { name: 'k6 tester' },
    { metadata }
  );

  check(response, {
    'gRPC status OK':          (r) => r && r.status === grpc.StatusOK,
    'greeting not empty':      (r) => r.message.greeting.length > 0,
  });

  client.close();
}
```

### Loading Compiled Protoset (alternative to .proto files)

```javascript
// If you have a compiled .pb file (protoset format)
client.loadProtoset('./service.pb');
```

### gRPC Client Methods

| Method | Description |
|---|---|
| `client.load(importPaths, ...protoFiles)` | Load service definitions from .proto files |
| `client.loadProtoset(path)` | Load from compiled protoset |
| `client.connect(address, [params])` | Open connection (per VU, per iteration) |
| `client.invoke(url, request, [params])` | Synchronous unary call |
| `client.asyncInvoke(url, request, [params])` | Async unary call |
| `client.healthCheck()` | gRPC health check protocol |
| `client.close()` | Close connection |

### Invoke URL Format

```
'<package>.<ServiceName>/<MethodName>'

Examples:
  'helloworld.Greeter/SayHello'
  'com.example.users.UserService/GetUser'
  'orders.v1.OrderService/CreateOrder'
```

### gRPC Status Codes

```javascript
grpc.StatusOK                 // 0 - Success
grpc.StatusCancelled          // 1 - Client cancelled
grpc.StatusUnknown            // 2 - Unknown
grpc.StatusInvalidArgument    // 3 - Bad input
grpc.StatusDeadlineExceeded   // 4 - Timeout
grpc.StatusNotFound           // 5 - Resource not found
grpc.StatusAlreadyExists      // 6 - Duplicate
grpc.StatusPermissionDenied   // 7 - Not authorized
grpc.StatusResourceExhausted  // 8 - Quota exceeded
grpc.StatusUnauthenticated    // 16 - Missing credentials
```

### Server Streaming

```javascript
const stream = client.asyncInvoke('example.StreamService/ListItems', {});

stream.on('data', (data) => {
  check(data, { 'item has id': (d) => d.id !== undefined });
});

stream.on('end', () => {
  console.log('stream complete');
});

stream.on('error', (err) => {
  console.error(`stream error: ${err.code} ${err.message}`);
});
```

### Common gRPC Gotchas

**1. `client.load()` must be called in init context**
`client.load()` and `client.loadProtoset()` are init-context operations. Calling them inside `default()` throws an error.

```javascript
// Wrong — inside default function
export default function() {
  client.load(['./proto'], 'service.proto');  // ❌ runtime error
}

// Correct — at top level
const client = new grpc.Client();
client.load(['./proto'], 'service.proto');    // ✓ init context
```

**2. Connect and close per iteration**
Unlike HTTP, gRPC connections are stateful. k6 requires you to `connect()` and `close()` within each iteration (or manage the lifecycle explicitly).

```javascript
export default function() {
  client.connect('localhost:50051', { plaintext: true });
  // ... invoke calls ...
  client.close();   // always close to avoid connection exhaustion
}
```

**3. Import path must match proto `package` declaration**
The invoke URL must exactly match the `package` and `service` names in the .proto file, including capitalization.

**4. TLS in production**
For production endpoints, omit `plaintext: true` (defaults to TLS). If using self-signed certs, use:
```javascript
client.connect(address, {
  tls: { insecureSkipTLSVerify: true },
});
```
