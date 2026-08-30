import http from "node:http";
import { WebSocketServer } from "ws";

const port = Number(process.env.PORT || process.env.WS_PORT || 4001);
const server = http.createServer((req, res) => {
  if (req.url === "/health") {
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify({ ok: true, service: "jz-ws" }));
    return;
  }
  res.writeHead(404);
  res.end();
});
const wss = new WebSocketServer({ server });
wss.on("connection", socket => socket.send(JSON.stringify({ type: "welcome", service: "jz-ws" })));
server.listen(port, "0.0.0.0", () => console.log(`J&Z WebSocket listening on ${port}`));
