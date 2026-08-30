import http from "node:http";
import { WebSocketServer, type WebSocket } from "ws";

const port = Number(process.env.PORT || process.env.WS_PORT || 4001);
const server = http.createServer((req, res) => {
  if (req.url === "/health") {
    res.writeHead(200, { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" });
    res.end(JSON.stringify({ ok: true, service: "jz-ws", version: "1.2.0" }));
    return;
  }
  res.writeHead(404);
  res.end();
});

const wss = new WebSocketServer({ server, path: "/ws" });
wss.on("connection", (socket: WebSocket) => {
  socket.send(JSON.stringify({ type: "welcome", service: "jz-ws" }));
});

server.listen(port, "0.0.0.0", () => console.log(`J&Z WebSocket listening on ${port}`));

const shutdown = (signal: string): void => {
  console.log(`Received ${signal}; shutting down`);
  wss.close(() => server.close(() => process.exit(0)));
  setTimeout(() => process.exit(1), 10_000).unref();
};
process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));
