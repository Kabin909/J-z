import { WebSocketServer } from "ws";

const port = Number(process.env.PORT || 4001);
const wss = new WebSocketServer({ host: "0.0.0.0", port });
wss.on("connection", socket => socket.send(JSON.stringify({ type: "welcome", service: "jz-ws" })));
console.log(`J&Z WebSocket listening on ${port}`);
