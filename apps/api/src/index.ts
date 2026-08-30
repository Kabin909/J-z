import express from "express";
import cors from "cors";
import jwt from "jsonwebtoken";
import { Pool } from "pg";
import crypto from "node:crypto";

const app = express();
const port = Number(process.env.PORT || 4000);
const origin = process.env.PANEL_ORIGIN || true;
const jwtSecret = process.env.JWT_SECRET || "development-only-change-me";
const pool = new Pool({ connectionString: process.env.DATABASE_URL || "postgresql://jz:CHANGE_ME@postgres:5432/jz" });

app.disable("x-powered-by");
app.use(cors({ origin, credentials: true }));
app.use(express.json({ limit: "2mb" }));

async function initDb() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS users (
      id uuid PRIMARY KEY,
      username text UNIQUE NOT NULL,
      email text UNIQUE NOT NULL,
      password_hash text NOT NULL,
      role text NOT NULL DEFAULT 'user',
      created_at timestamptz NOT NULL DEFAULT now()
    );
    CREATE TABLE IF NOT EXISTS servers (
      id uuid PRIMARY KEY,
      owner_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      name text NOT NULL,
      status text NOT NULL DEFAULT 'offline',
      cpu_limit integer NOT NULL DEFAULT 100,
      memory_limit integer NOT NULL DEFAULT 1024,
      disk_limit integer NOT NULL DEFAULT 10240,
      created_at timestamptz NOT NULL DEFAULT now()
    );
  `);
  const adminUser = process.env.ADMIN_USERNAME;
  const adminEmail = process.env.ADMIN_EMAIL;
  const adminPassword = process.env.ADMIN_PASSWORD;
  if (adminUser && adminEmail && adminPassword) {
    const hash = crypto.createHash("sha256").update(adminPassword).digest("hex");
    await pool.query(`INSERT INTO users(id,username,email,password_hash,role) VALUES($1,$2,$3,$4,'admin') ON CONFLICT(email) DO NOTHING`, [crypto.randomUUID(), adminUser, adminEmail, hash]);
  }
}

function auth(req: express.Request, res: express.Response, next: express.NextFunction) {
  const h = req.headers.authorization || "";
  const token = h.startsWith("Bearer ") ? h.slice(7) : "";
  if (!token) return res.status(401).json({ error: "Authentication required" });
  try { (req as any).user = jwt.verify(token, jwtSecret); next(); } catch { return res.status(401).json({ error: "Invalid or expired token" }); }
}
function hash(p: string) { return crypto.createHash("sha256").update(p).digest("hex"); }
function token(u: any) { return jwt.sign({ id: u.id, username: u.username, role: u.role }, jwtSecret, { expiresIn: "7d" }); }

app.get("/api/health", async (_req, res) => { try { await pool.query("SELECT 1"); res.json({ ok: true, service: "jz-api", database: "ok", version: "1.1.0" }); } catch { res.status(503).json({ ok: false, service: "jz-api", database: "down" }); } });
app.get("/api/ready", async (_req, res) => { try { await pool.query("SELECT 1"); res.json({ ready: true }); } catch { res.status(503).json({ ready: false }); } });
app.get("/api", (_req, res) => res.json({ name: "J&Z Panel", version: "1.1.0" }));

app.post("/api/auth/register", async (req, res) => {
  const { username, email, password } = req.body || {};
  if (!/^[A-Za-z0-9_.-]{3,32}$/.test(username || "") || !/^\S+@\S+\.\S+$/.test(email || "") || String(password || "").length < 12) return res.status(400).json({ error: "Username, valid email and 12+ character password are required" });
  try { const r = await pool.query(`INSERT INTO users(id,username,email,password_hash) VALUES($1,$2,$3,$4) RETURNING id,username,email,role`, [crypto.randomUUID(), username, email.toLowerCase(), hash(password)]); const u=r.rows[0]; res.status(201).json({ user:u, token:token(u) }); } catch { res.status(409).json({ error:"Username or email already exists" }); }
});
app.post("/api/auth/login", async (req,res)=>{ const {email,password}=req.body||{}; const r=await pool.query("SELECT id,username,email,password_hash,role FROM users WHERE email=$1",[String(email||"").toLowerCase()]); const u=r.rows[0]; if(!u||u.password_hash!==hash(String(password||""))) return res.status(401).json({error:"Invalid credentials"}); delete u.password_hash; res.json({user:u,token:token(u)}); });
app.get("/api/auth/me",auth,async(req,res)=>{ const r=await pool.query("SELECT id,username,email,role,created_at FROM users WHERE id=$1",[(req as any).user.id]); res.json({user:r.rows[0]||null}); });
app.get("/api/servers",auth,async(req,res)=>{ const u=(req as any).user; const r=await pool.query("SELECT id,name,status,cpu_limit,memory_limit,disk_limit,created_at FROM servers WHERE owner_id=$1 ORDER BY created_at DESC",[u.id]); res.json({servers:r.rows}); });
app.post("/api/servers",auth,async(req,res)=>{ const {name,cpu_limit=100,memory_limit=1024,disk_limit=10240}=req.body||{}; if(!name) return res.status(400).json({error:"Server name is required"}); const id=crypto.randomUUID(); const r=await pool.query("INSERT INTO servers(id,owner_id,name,cpu_limit,memory_limit,disk_limit) VALUES($1,$2,$3,$4,$5,$6) RETURNING *",[id,(req as any).user.id,name,Number(cpu_limit),Number(memory_limit),Number(disk_limit)]); res.status(201).json({server:r.rows[0]}); });
app.delete("/api/servers/:id",auth,async(req,res)=>{ await pool.query("DELETE FROM servers WHERE id=$1 AND owner_id=$2",[req.params.id,(req as any).user.id]); res.status(204).end(); });

initDb().then(()=>app.listen(port,"0.0.0.0",()=>console.log(`J&Z API listening on ${port}`))).catch(err=>{console.error("Database initialization failed",err);process.exit(1)});
