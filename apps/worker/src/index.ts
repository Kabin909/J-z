import Redis from 'ioredis';
import { Pool } from 'pg';
import crypto from 'node:crypto';

const redisUrl=process.env.REDIS_URL||'redis://localhost:6379';
const redis = new Redis(redisUrl);
const db=new Pool({connectionString:process.env.DATABASE_URL});
const key=crypto.createHash('sha256').update(process.env.NODE_ENCRYPTION_KEY||'jz-development-node-encryption-key-32').digest();
function decrypt(value:string){const [iv,tag,data]=value.split('.');const d=crypto.createDecipheriv('aes-256-gcm',key,Buffer.from(iv,'base64url'));d.setAuthTag(Buffer.from(tag,'base64url'));return Buffer.concat([d.update(Buffer.from(data,'base64url')),d.final()]).toString('utf8');}
function sign(secret:string,method:string,path:string,body:string){const ts=Math.floor(Date.now()/1000).toString();const material=`${ts}\n${method}\n${path}\n${crypto.createHash('sha256').update(body).digest('hex')}`;const sig=crypto.createHmac('sha256',secret).update(material).digest('hex');return {ts,sig};}
async function nodeRequest(nodeId:string,path:string,method:string='GET',payload:any=undefined){const q=await db.query('select n.address,nc.secret_encrypted from nodes n join node_credentials nc on nc.node_id=n.id where n.id=$1',[nodeId]);if(!q.rows[0])throw new Error('node_not_found');const base=q.rows[0].address.replace(/\/$/,'');const body=payload===undefined?'':JSON.stringify(payload);const {ts,sig}=sign(decrypt(q.rows[0].secret_encrypted),method,path,body);const r=await fetch(`${base}${path}`,{method,headers:{'content-type':'application/json','x-jz-timestamp':ts,'x-jz-signature':sig,'x-jz-node-id':nodeId},body:body||undefined});const text=await r.text();let data:any;try{data=JSON.parse(text)}catch{data={raw:text}}if(!r.ok)throw new Error(`wings_${r.status}:${data.error||data.raw||'request failed'}`);return data;}
async function setStatus(serverId:string,status:string,containerId?:string){await db.query('update servers set status=$1,container_id=coalesce($2,container_id),updated_at=now() where id=$3',[status,containerId||null,serverId]);await db.query('insert into server_events(server_id,type,payload) values($1,$2,$3)',[serverId,'worker.status',JSON.stringify({status,container_id:containerId||null})]);}
async function handle(job:any){const q=await db.query(`select s.*,n.address from servers s join nodes n on n.id=s.node_id where s.id=$1`,[job.server_id]);if(!q.rows[0])throw new Error('server_not_found');const s=q.rows[0];
  if(job.type==='server.install'||job.type==='server.reinstall'){
    if(job.type==='server.reinstall'&&s.container_id){try{await nodeRequest(s.node_id,`/v1/servers/${s.container_id}/delete`,'POST',{});}catch{}}
    await setStatus(s.id,'INSTALLING');
    const created=await nodeRequest(s.node_id,'/v1/servers','POST',{container_id:s.id,image:s.image||'ubuntu:24.04',name:`jz-${s.id}`,memory:s.memory_limit,nano_cpus:Math.max(100000,Math.floor((s.cpu_limit||100)*100000)),command:s.startup_command?["/bin/sh","-lc",s.startup_command]:["/bin/sh","-lc","sleep infinity"]});
    await db.query('update servers set container_id=$1,status=$2,updated_at=now() where id=$3',[created.container_id,s.auto_start?'STARTING':'STOPPED',s.id]);
    if(s.auto_start){await nodeRequest(s.node_id,`/v1/servers/${created.container_id}/start`,'POST',{});await setStatus(s.id,'RUNNING',created.container_id);}else await setStatus(s.id,'STOPPED',created.container_id);
    return;
  }
  const containerId=s.container_id;if(job.type==='server.delete'){if(containerId){try{await nodeRequest(s.node_id,`/v1/servers/${containerId}/delete`,'POST',{});}catch{}}await db.query('delete from servers where id=$1',[s.id]);return;}if(!containerId)throw new Error('container_not_ready');
  const map:any={start:'STARTING',stop:'STOPPING',restart:'RESTARTING',kill:'STOPPING'};await setStatus(s.id,map[job.type.replace('server.','')]||'INSTALLING',containerId);
  await nodeRequest(s.node_id,`/v1/servers/${containerId}/${job.type.replace('server.','')}`,'POST',{});
  await setStatus(s.id,job.type==='server.start'||job.type==='server.restart'?'RUNNING':'STOPPED',containerId);
}
async function main(){console.log(JSON.stringify({service:'jz-worker',state:'online'}));for(;;){const item=await redis.brpop('jz:jobs',0);if(!item)continue;let job:any;try{job=JSON.parse(item[1]);await handle(job);console.log(JSON.stringify({service:'jz-worker',event:'job.completed',job_id:job.id,type:job.type}));}catch(error:any){console.error(JSON.stringify({service:'jz-worker',event:'job.failed',job_id:job?.id,error:error?.message||String(error)}));if(job?.server_id)await db.query('update servers set status=case when status in (\'STARTING\',\'STOPPING\',\'RESTARTING\',\'INSTALLING\') then \'ERROR\' else status end,updated_at=now() where id=$1',[job.server_id]).catch(()=>{});}}}
main().catch(error=>{console.error(error);process.exit(1)});
