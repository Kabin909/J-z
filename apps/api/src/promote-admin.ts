import { Pool } from 'pg';
const email=process.argv[2]?.toLowerCase();
if(!email){console.error('Usage: npm --workspace @jz/api run promote-admin -- user@example.com');process.exit(1)}
const db=new Pool({connectionString:process.env.DATABASE_URL});
try{
 const u=await db.query('select id,username from users where email=$1',[email]);
 if(!u.rows[0]) throw new Error('User not found');
 const r=await db.query("select id from roles where name='Administrator'");
 await db.query('insert into user_roles(user_id,role_id) values($1,$2) on conflict do nothing',[u.rows[0].id,r.rows[0].id]);
 console.log(`J&Z: ${u.rows[0].username} is now Administrator.`);
}finally{await db.end()}
