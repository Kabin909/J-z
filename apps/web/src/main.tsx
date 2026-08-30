import React from "react";
import {createRoot} from "react-dom/client";
import "./style.css";

function App(){
 return <main className="shell">
  <aside><div className="mark">JZ</div><h1>J&Z Panel</h1>
   <nav><a className="active">Dashboard</a><a>Servers</a><a>Console</a><a>Files</a><a>Plugins</a><a>Nodes</a><a>Settings</a></nav>
  </aside>
  <section className="content"><header><div><small>CONTROL CENTER</small><h2>Welcome back</h2></div><button>Admin</button></header>
   <div className="grid">{["Servers","Online","CPU Usage","Memory"].map((x,i)=><article key={x}><span>{x}</span><strong>{["0","0","0%","0 GB"][i]}</strong></article>)}</div>
   <article className="hero"><small>J&Z PANEL</small><h3>Manage your infrastructure.</h3><p>Servers, nodes, console, files and plugins from one clean dashboard.</p><button className="primary">Create Server</button></article>
  </section>
 </main>
}
createRoot(document.getElementById("root")!).render(<App/>);
