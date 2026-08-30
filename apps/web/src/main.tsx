import React, { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import "./style.css";

type User = { id: number; username: string; email: string; role: string };
type Server = { id: number; name: string; status: string; node?: string };

const API = "";

async function api<T>(path: string, options: RequestInit = {}): Promise<T> {
  const token = localStorage.getItem("jz_token");
  const headers = new Headers(options.headers);
  headers.set("Content-Type", "application/json");
  if (token) headers.set("Authorization", `Bearer ${token}`);
  const r = await fetch(`${API}${path}`, { ...options, headers });
  const data = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(data.error || `Request failed (${r.status})`);
  return data;
}

function Login({ onLogin }: { onLogin: (user: User) => void }) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const submit = async (e: React.FormEvent) => {
    e.preventDefault(); setError("");
    try { const data = await api<{ user: User; token: string }>("/api/auth/login", { method: "POST", body: JSON.stringify({ email, password }) }); localStorage.setItem("jz_token", data.token); onLogin(data.user); }
    catch (err) { setError(err instanceof Error ? err.message : "Login failed"); }
  };
  return <main className="auth"><div className="auth-card"><div className="logo">J&Z</div><small>CONTROL PLANE</small><h1>Sign in</h1><p>Manage your infrastructure from one secure console.</p><form onSubmit={submit}><label>Email<input type="email" value={email} onChange={e=>setEmail(e.target.value)} required /></label><label>Password<input type="password" value={password} onChange={e=>setPassword(e.target.value)} required /></label>{error&&<div className="error">{error}</div>}<button className="primary full">Sign in</button></form></div></main>;
}

function App() {
  const [user, setUser] = useState<User | null>(null);
  const [servers, setServers] = useState<Server[]>([]);
  const [error, setError] = useState("");
  useEffect(() => { if (localStorage.getItem("jz_token")) api<{user:User}>("/api/me").then(x=>setUser(x.user)).catch(()=>localStorage.removeItem("jz_token")); }, []);
  useEffect(() => { if (user) api<{servers:Server[]}>("/api/servers").then(x=>setServers(x.servers)).catch(e=>setError(e.message)); }, [user]);
  if (!user) return <Login onLogin={setUser} />;
  const logout = () => { localStorage.removeItem("jz_token"); setUser(null); };
  return <main className="shell"><aside><div className="brand"><div className="mark">JZ</div><div><strong>J&Z Panel</strong><small>INFRASTRUCTURE</small></div></div><nav>{["Dashboard","Servers","Console","Files","Backups","Databases","Nodes","Plugins","Users","Settings"].map((x,i)=><a key={x} className={i===0?"active":""}>{x}</a>)}</nav><button className="logout" onClick={logout}>Sign out</button></aside><section className="content"><header><div><small>OVERVIEW</small><h2>Good to see you, {user.username}</h2></div><div className="profile"><span>{user.role}</span><button onClick={logout}>Sign out</button></div></header>{error&&<div className="error">{error}</div>}<div className="grid">{[["Servers",String(servers.length)],["Online",String(servers.filter(s=>s.status==='online').length)],["CPU Usage","—"],["Memory","—"]].map(([x,v])=><article key={x}><span>{x}</span><strong>{v}</strong></article>)}</div><div className="section-head"><div><small>YOUR INFRASTRUCTURE</small><h3>Servers</h3></div><button className="primary">Create server</button></div><div className="server-list">{servers.length?servers.map(s=><article className="server" key={s.id}><div><strong>{s.name}</strong><span>{s.node||"Unassigned node"}</span></div><b className={s.status==='online'?"online":"offline"}>{s.status}</b></article>):<article className="empty"><strong>No servers yet</strong><span>Create your first server from the panel.</span></article>}</div></section></main>
}
createRoot(document.getElementById("root")!).render(<App />);
