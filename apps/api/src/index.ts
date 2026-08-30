import express from "express";
import cors from "cors";

const app = express();
app.disable("x-powered-by");
app.use(cors({ origin: process.env.PANEL_ORIGIN || true }));
app.use(express.json({ limit: "2mb" }));

app.get("/api/health", (_req, res) => res.json({ ok: true, service: "jz-api", version: "1.0.0" }));
app.get("/api/ready", (_req, res) => res.json({ ready: true }));
app.get("/api", (_req, res) => res.json({ name: "J&Z Panel", version: "1.0.0" }));

const port = Number(process.env.PORT || 4000);
app.listen(port, "0.0.0.0", () => console.log(`J&Z API listening on ${port}`));
