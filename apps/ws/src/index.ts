import Fastify from 'fastify';
import websocket from '@fastify/websocket';
import cookie from '@fastify/cookie';
import crypto from 'node:crypto';
import {Pool} from 'pg';
const app=Fastify({logger:true});
const cookieSecret=process.env.COOKIE_SECRET;
const databaseUrl=process.env.DATABASE_URL;
if(!cookieSecret||cookieSecret.length<32) throw new Error('COOKIE_SECRET must be configured with at least 32 characters');
if(!databaseUrl) throw new Error('DATABASE_URL must be configured');
const db=new Pool({connectionString:databaseUrl});
const hash=(s:string)=>crypto.createHash('sha256').update(s).digest('hex');
await app.register(cookie,{secret:cookieSecret}); await app.register(websocket);
app.get('/health',async()=>({ok:true,service:'jz-websocket',version:'0.8.0',time:new Date().toISOString()}));
async function sessionUser(raw:string|undefined){if(!raw)return null;const q=await db.query('select u.id,u.username from sessions s join users u on u.id=s.user_id where s.token_hash=$1 and s.expires_at>now() and u.disabled_at is null limit 1',[hash(raw)]);return q.rows[0]||null;}
app.get('/api/ws/console',{websocket:true},async(socket,req)=>{
  const user=await sessionUser((req.cookies as any)?.jz_session);
  if(!user){socket.close(1008,'Authentication required');return;}
  const connectionId=crypto.randomUUID();
  socket.send(JSON.stringify({type:'connection',state:'authenticated',connection_id:connectionId,user_id:user.id}));
  socket.on('message',async raw=>{try{const m=JSON.parse(raw.toString());if(!['attach','command','resize','ping','detach'].includes(m.type)){socket.send(JSON.stringify({type:'error',code:'UNSUPPORTED_MESSAGE'}));return}if(m.type==='ping'){socket.send(JSON.stringify({type:'pong',at:Date.now()}));return}if(m.type==='attach'){socket.send(JSON.stringify({type:'attached',server_id:m.server_id,state:'authorization-boundary'}));return}if(m.type==='command'){socket.send(JSON.stringify({type:'command.accepted',command_id:crypto.randomUUID(),state:'queued'}));return}if(m.type==='detach'){socket.send(JSON.stringify({type:'detached'}));}}catch{socket.close(1003,'Invalid message')}});
});
await app.listen({port:Number(process.env.WS_PORT||4001),host:'0.0.0.0'});
