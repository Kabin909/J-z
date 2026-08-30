import express from "express";
import cors from "cors";
import pg from "pg";
import jwt from "jsonwebtoken";
import crypto from "node:crypto";

const { Pool } = pg;
const app = express();
app.disable("x-powered-by");
app.use(cors({ origin: process.env.PANEL_ORIGIN || true, credentials: true }));
app.use(express.json({ limit: "2mb" }));

const port = Number(process.env.PORT || process.env.API_PORT || 4000);
const jwtSecret = process.env.JWT_SECRET || "development-only-change-me";
const pool = new Pool({ connectionString: process.env.DATABASE_URL });

const hashPassword = (password: string) => {
  const iterations = 210_000;
  const salt = crypto.randomBytes(16).toString("hex");
  const hash = crypto.pbkdf2Sync(password, salt, iterations, 32, "sha256").toString("hex");
  return `pbkdf2$${iterations}$${salt}$${hash}`;
};
const verifyPassword = (password: string, stored: string) => {
  const [scheme, iterationsRaw, salt, expected] = stored.split("$");
  const iterations = Number(iterationsRaw);
  if (scheme !== "pbkdf2" || !Number.isInteger(iterations) || !salt || !expected) return false;
  const actual = crypto.pbkdf2Sync(password, salt, iterations, 32, "sha256").toString("hex");
  const expectedBuffer = Buffer.from(expected, "hex");
  const actualBuffer = Buffer.from(actual, "hex");
  return expectedBuffer.length === actualBuffer.length && crypto.timingSafeEqual(actualBuffer, expectedBuffer);
};
const sign = (user: { id: number; username: string; role: string }) =>
  jwt.sign(user, jwtSecret, { expiresIn: "12h" });

async function dbReady() {
  await pool.query("SELECT 1");
}

function auth(req: express.Request, res: express.Response, next: express.NextFunction) {
  const token = req.headers.authorization?.replace(/^Bearer\s+/i, "");
  if (!token) return res.status(401).json({ error: "Authentication required" });
  try {
    (req as express.Request & { user?: jwt.JwtPayload }).user = jwt.verify(token, jwtSecret) as jwt.JwtPayload;
    next();
  } catch {
    return res.status(401).json({ error: "Invalid or expired token" });
  }
}

app.get("/api/health", (_req, res) => res.json({ ok: true, service: "jz-api", version: "1.1.0" }));
app.get("/api/ready", async (_req, res) => {
  try {
    await dbReady();
    res.json({ ready: true, database: true });
  } catch {
    res.status(503).json({ ready: false, database: false });
  }
});

app.post("/api/auth/register", async (req, res) => {
  const { username, email, password } = req.body ?? {};
  if (!username || !email || !password || String(password).length < 12) {
    return res.status(400).json({ error: "Username, email and a 12+ character password are required" });
  }
  try {
    const result = await pool.query(
      "INSERT INTO users(username,email,password_hash) VALUES($1,$2,$3) RETURNING id,username,email,role",
      [String(username), String(email).toLowerCase(), hashPassword(String(password))]
    );
    const user = result.rows[0];
    res.status(201).json({ user, token: sign(user) });
  } catch (error: unknown) {
    const message = error instanceof Error && /unique/i.test(error.message) ? "Username or email already exists" : "Registration failed";
    res.status(400).json({ error: message });
  }
});

app.post("/api/auth/login", async (req, res) => {
  const { email, password } = req.body ?? {};
  if (!email || !password) return res.status(400).json({ error: "Email and password are required" });
  const result = await pool.query("SELECT id,username,email,role,password_hash FROM users WHERE email=$1", [String(email).toLowerCase()]);
  const user = result.rows[0];
  if (!user || user.!verifyPassword(String(password), user.password_hash)) return res.status(401).json({ error: "Invalid credentials" });
  delete user.password_hash;
  res.json({ user, token: sign(user) });
});

app.get("/api/me", auth, async (req, res) => {
  const id = Number((req as express.Request & { user?: jwt.JwtPayload }).user?.id);
  const result = await pool.query("SELECT id,username,email,role,created_at FROM users WHERE id=$1", [id]);
  if (!result.rows[0]) return res.status(404).json({ error: "User not found" });
  res.json({ user: result.rows[0] });
});

app.get("/api/servers", auth, async (req, res) => {
  const id = Number((req as express.Request & { user?: jwt.JwtPayload }).user?.id);
  const result = await pool.query(
    "SELECT s.id,s.name,s.status,n.name AS node FROM servers s LEFT JOIN nodes n ON n.id=s.node_id WHERE s.owner_id=$1 ORDER BY s.id DESC",
    [id]
  );
  res.json({ servers: result.rows });
});

app.listen(port, "0.0.0.0", () => console.log(`J&Z API listening on ${port}`));
