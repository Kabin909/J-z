import express, { type NextFunction, type Request, type Response } from "express";
import cors from "cors";
import pg from "pg";
import jwt, { type JwtPayload } from "jsonwebtoken";
import crypto from "node:crypto";

const { Pool } = pg;
const app = express();
app.disable("x-powered-by");

const port = Number(process.env.PORT || process.env.API_PORT || 4000);
const jwtSecret = process.env.JWT_SECRET;
const corsOrigin = process.env.CORS_ORIGIN || process.env.PANEL_ORIGIN || undefined;

if (process.env.NODE_ENV === "production" && (!jwtSecret || jwtSecret.length < 32)) {
  throw new Error("JWT_SECRET must be set to at least 32 characters in production");
}

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  max: Number(process.env.DB_POOL_MAX || 20),
  connectionTimeoutMillis: 5000,
  idleTimeoutMillis: 30000,
});

app.use(cors({ origin: corsOrigin || true, credentials: true }));
app.use(express.json({ limit: "2mb" }));

const hashPassword = (password: string): string => {
  const iterations = 210_000;
  const salt = crypto.randomBytes(16).toString("hex");
  const hash = crypto.pbkdf2Sync(password, salt, iterations, 32, "sha256").toString("hex");
  return `pbkdf2$${iterations}$${salt}$${hash}`;
};

const verifyPassword = (password: string, stored: string): boolean => {
  const [scheme, iterationsRaw, salt, expected] = String(stored || "").split("$");
  const iterations = Number(iterationsRaw);
  if (scheme !== "pbkdf2" || !Number.isInteger(iterations) || iterations < 100_000 || !salt || !expected) return false;
  const actual = crypto.pbkdf2Sync(password, salt, iterations, 32, "sha256").toString("hex");
  const expectedBuffer = Buffer.from(expected, "hex");
  const actualBuffer = Buffer.from(actual, "hex");
  return expectedBuffer.length === actualBuffer.length && crypto.timingSafeEqual(actualBuffer, expectedBuffer);
};

const sign = (user: { id: number; username: string; role: string }): string =>
  jwt.sign(user, jwtSecret || "development-only-change-me", { expiresIn: "12h" });

type AuthRequest = Request & { user?: JwtPayload & { id?: number } };

async function dbReady(): Promise<void> {
  await pool.query("SELECT 1");
}

function auth(req: AuthRequest, res: Response, next: NextFunction): void {
  const token = req.headers.authorization?.replace(/^Bearer\s+/i, "");
  if (!token) {
    res.status(401).json({ error: "Authentication required" });
    return;
  }
  try {
    req.user = jwt.verify(token, jwtSecret || "development-only-change-me") as JwtPayload & { id?: number };
    next();
  } catch {
    res.status(401).json({ error: "Invalid or expired token" });
  }
}

app.get("/api/health", (_req: Request, res: Response) => {
  res.json({ ok: true, service: "jz-api", version: "1.2.0" });
});

app.get("/api/ready", async (_req: Request, res: Response) => {
  try {
    await dbReady();
    res.json({ ready: true, database: true });
  } catch {
    res.status(503).json({ ready: false, database: false });
  }
});

app.post("/api/auth/register", async (req: Request, res: Response) => {
  const username = String(req.body?.username ?? "").trim();
  const email = String(req.body?.email ?? "").trim().toLowerCase();
  const password = String(req.body?.password ?? "");

  if (!/^[a-zA-Z0-9_.-]{3,32}$/.test(username)) {
    res.status(400).json({ error: "Username must be 3-32 characters and use letters, numbers, _, ., or -" });
    return;
  }
  if (!/^\S+@\S+\.\S+$/.test(email)) {
    res.status(400).json({ error: "A valid email address is required" });
    return;
  }
  if (password.length < 12 || password.length > 256) {
    res.status(400).json({ error: "Password must be 12-256 characters" });
    return;
  }

  try {
    const result = await pool.query(
      "INSERT INTO users(username,email,password_hash) VALUES($1,$2,$3) RETURNING id,username,email,role",
      [username, email, hashPassword(password)]
    );
    const user = result.rows[0] as { id: number; username: string; email: string; role: string };
    res.status(201).json({ user, token: sign(user) });
  } catch (error: unknown) {
    const message = error instanceof Error && /unique/i.test(error.message)
      ? "Username or email already exists"
      : "Registration failed";
    res.status(400).json({ error: message });
  }
});

app.post("/api/auth/login", async (req: Request, res: Response) => {
  const email = String(req.body?.email ?? "").trim().toLowerCase();
  const password = String(req.body?.password ?? "");
  if (!email || !password) {
    res.status(400).json({ error: "Email and password are required" });
    return;
  }

  try {
    const result = await pool.query(
      "SELECT id,username,email,role,password_hash FROM users WHERE email=$1",
      [email]
    );
    const user = result.rows[0] as { id: number; username: string; email: string; role: string; password_hash: string } | undefined;
    if (!user || !verifyPassword(password, user.password_hash)) {
      res.status(401).json({ error: "Invalid credentials" });
      return;
    }
    const publicUser = { id: user.id, username: user.username, email: user.email, role: user.role };
    res.json({ user: publicUser, token: sign(publicUser) });
  } catch {
    res.status(503).json({ error: "Authentication service temporarily unavailable" });
  }
});

app.get("/api/me", auth, async (req: AuthRequest, res: Response) => {
  const id = Number(req.user?.id);
  if (!Number.isSafeInteger(id) || id <= 0) {
    res.status(401).json({ error: "Invalid authentication subject" });
    return;
  }
  try {
    const result = await pool.query("SELECT id,username,email,role,created_at FROM users WHERE id=$1", [id]);
    if (!result.rows[0]) {
      res.status(404).json({ error: "User not found" });
      return;
    }
    res.json({ user: result.rows[0] });
  } catch {
    res.status(503).json({ error: "Database temporarily unavailable" });
  }
});

app.get("/api/servers", auth, async (req: AuthRequest, res: Response) => {
  const id = Number(req.user?.id);
  if (!Number.isSafeInteger(id) || id <= 0) {
    res.status(401).json({ error: "Invalid authentication subject" });
    return;
  }
  try {
    const result = await pool.query(
      "SELECT s.id,s.name,s.status,n.name AS node FROM servers s LEFT JOIN nodes n ON n.id=s.node_id WHERE s.owner_id=$1 ORDER BY s.id DESC",
      [id]
    );
    res.json({ servers: result.rows });
  } catch {
    res.status(503).json({ error: "Server list temporarily unavailable" });
  }
});

const server = app.listen(port, "0.0.0.0", () => console.log(`J&Z API listening on ${port}`));

const shutdown = async (signal: string): Promise<void> => {
  console.log(`Received ${signal}; shutting down`);
  server.close(async () => {
    await pool.end().catch(() => undefined);
    process.exit(0);
  });
  setTimeout(() => process.exit(1), 10_000).unref();
};
process.on("SIGTERM", () => void shutdown("SIGTERM"));
process.on("SIGINT", () => void shutdown("SIGINT"));
