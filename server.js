import express from "express";
import mysql from "mysql2/promise";
import OpenAI from "openai";
import dotenv from "dotenv";
import path from "node:path";
import fs from "node:fs/promises";
import {fileURLToPath} from "node:url";
import {safeRoot,listFiles,readFile,writeFile} from "./lib/workspace.js";

dotenv.config({path:process.env.ENV_FILE || "/etc/webhosting-admin/admin.env"});
const __dirname=path.dirname(fileURLToPath(import.meta.url));
const HOST=process.env.HOST || "127.0.0.1";
const PORT=Number(process.env.PORT || 3200);
const WEB_ROOT=process.env.WEB_ROOT || "/srv/webhosting/www";
const MODEL=process.env.OPENAI_MODEL || "gpt-5.5";
const client=process.env.OPENAI_API_KEY ? new OpenAI({apiKey:process.env.OPENAI_API_KEY}) : null;
const db=mysql.createPool({
 host:process.env.DB_HOST||"127.0.0.1",port:Number(process.env.DB_PORT||3306),
 user:process.env.DB_USER||"webhosting_admin",password:process.env.DB_PASSWORD||"",
 database:process.env.DB_NAME||"webhosting_admin",connectionLimit:5
});

const app=express(); app.disable("x-powered-by"); app.use(express.json({limit:"2mb"}));

async function projectById(id){
 const [rows]=await db.query("SELECT id,name,slug,status FROM projects WHERE id=? LIMIT 1",[id]);
 if(!rows.length) throw new Error("Project niet gevonden");
 return rows[0];
}
async function ensureDemoProject(){
 const [r]=await db.query("SELECT id FROM projects ORDER BY id LIMIT 1");
 if(r.length) return;
 await db.query("INSERT INTO projects(name,slug,status) VALUES('Demo website','demo-website','active')");
 const root=safeRoot(WEB_ROOT,"demo-website"); await fs.mkdir(root,{recursive:true});
 await fs.writeFile(path.join(root,"index.html"),`<!doctype html><html lang="nl"><head><meta charset="utf-8"><title>Demo website</title><link rel="stylesheet" href="style.css"></head><body><main><h1>Mijn website</h1><p>Deze website kan via de AI-workspace worden aangepast.</p></main></body></html>`);
 await fs.writeFile(path.join(root,"style.css"),`body{font-family:system-ui;margin:0;background:#f5f7fa;color:#17202a}main{max-width:900px;margin:80px auto;padding:32px}`);
}

app.get("/health",async(_q,r)=>{try{await db.query("SELECT 1");r.json({ok:true,database:"ok",openai:!!client})}catch{r.status(503).json({ok:false})}});
app.get("/admin/api/projects",async(_q,r)=>{try{await ensureDemoProject();const [rows]=await db.query("SELECT id,name,slug,status FROM projects ORDER BY id DESC");r.json(rows)}catch(e){r.status(500).json({error:e.message})}});
function customerInput(body){
 const name=String(body?.name||"").trim();
 const email=String(body?.email||"").trim();
 const address=String(body?.address||"").trim();
 const postcode=String(body?.postcode||"").trim();
 const city=String(body?.city||"").trim();
 const phone=String(body?.phone||"").trim();
 if(!name || name.length>190) throw new Error("Vul een geldige klantnaam in");
 if(email && (email.length>190 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))) throw new Error("Vul een geldig e-mailadres in");
 if(address.length>255) throw new Error("Adres is te lang");
 if(postcode.length>20) throw new Error("Postcode is te lang");
 if(city.length>120) throw new Error("Plaats is te lang");
 if(phone.length>50) throw new Error("Telefoonnummer is te lang");
 return {name,email:email||null,address:address||null,postcode:postcode||null,city:city||null,phone:phone||null};
}
app.get("/admin/api/customers",async(_q,r)=>{try{
 const [rows]=await db.query(`SELECT c.id,c.name,c.email,c.address,c.postcode,c.city,c.phone,c.status,c.created_at,COUNT(DISTINCT p.id) projects,COUNT(DISTINCT d.id) domains
 FROM customers c LEFT JOIN projects p ON p.customer_id=c.id LEFT JOIN domains d ON d.project_id=p.id
 GROUP BY c.id ORDER BY c.id DESC`); r.json(rows);
}catch(e){r.status(500).json({error:e.message})}});
app.post("/admin/api/customers",async(q,r)=>{try{
 const v=customerInput(q.body); const [x]=await db.query("INSERT INTO customers(name,email,address,postcode,city,phone,status) VALUES(?,?,?,?,?,?,'active')",[v.name,v.email,v.address,v.postcode,v.city,v.phone]);
 const [rows]=await db.query("SELECT id,name,email,address,postcode,city,phone,status,created_at FROM customers WHERE id=?",[x.insertId]); r.status(201).json(rows[0]);
}catch(e){r.status(400).json({error:e.message})}});
app.put("/admin/api/customers/:id",async(q,r)=>{try{
 const v=customerInput(q.body); const [x]=await db.query("UPDATE customers SET name=?,email=?,address=?,postcode=?,city=?,phone=? WHERE id=?",[v.name,v.email,v.address,v.postcode,v.city,v.phone,q.params.id]);
 if(!x.affectedRows) return r.status(404).json({error:"Klant niet gevonden"}); r.json({ok:true});
}catch(e){r.status(400).json({error:e.message})}});
app.patch("/admin/api/customers/:id/status",async(q,r)=>{try{
 const status=String(q.body?.status||""); if(!["active","blocked"].includes(status)) throw new Error("Ongeldige status");
 const [x]=await db.query("UPDATE customers SET status=? WHERE id=?",[status,q.params.id]);
 if(!x.affectedRows) return r.status(404).json({error:"Klant niet gevonden"}); r.json({ok:true,status});
}catch(e){r.status(400).json({error:e.message})}});
app.delete("/admin/api/customers/:id",async(q,r)=>{try{
 const [p]=await db.query("SELECT COUNT(*) total FROM projects WHERE customer_id=?",[q.params.id]);
 if(Number(p[0].total)>0) return r.status(409).json({error:"Klant heeft nog projecten. Verwijder of verplaats die eerst."});
 const [x]=await db.query("DELETE FROM customers WHERE id=?",[q.params.id]); if(!x.affectedRows) return r.status(404).json({error:"Klant niet gevonden"});
 r.json({ok:true});
}catch(e){r.status(500).json({error:e.message})}});
app.get("/admin/api/projects/:id/files",async(q,r)=>{try{const p=await projectById(q.params.id);r.json(await listFiles(safeRoot(WEB_ROOT,p.slug)))}catch(e){r.status(400).json({error:e.message})}});
app.get("/admin/api/projects/:id/file",async(q,r)=>{try{const p=await projectById(q.params.id);r.json({path:q.query.path,content:await readFile(safeRoot(WEB_ROOT,p.slug),String(q.query.path||""))})}catch(e){r.status(400).json({error:e.message})}});

const tools=[
 {type:"function",name:"list_project_files",description:"Bekijk de bestanden binnen het huidige websiteproject.",strict:true,parameters:{type:"object",properties:{},required:[],additionalProperties:false}},
 {type:"function",name:"read_project_file",description:"Lees een tekst/codebestand binnen het huidige websiteproject.",strict:true,parameters:{type:"object",properties:{path:{type:"string"}},required:["path"],additionalProperties:false}},
 {type:"function",name:"write_project_file",description:"Maak of overschrijf een bestand binnen het huidige websiteproject. Gebruik voor HTML, CSS, JS, PHP, JSON en andere toegestane tekstbestanden.",strict:true,parameters:{type:"object",properties:{path:{type:"string"},content:{type:"string"}},required:["path","content"],additionalProperties:false}}
];

app.post("/admin/api/projects/:id/ai",async(q,r)=>{
 try{
  if(!client) return r.status(503).json({error:"OPENAI_API_KEY is nog niet ingesteld"});
  const prompt=String(q.body?.message||"").trim(); if(!prompt) return r.status(400).json({error:"Geen opdracht opgegeven"});
  const p=await projectById(q.params.id); const root=safeRoot(WEB_ROOT,p.slug);
  const instructions=`Je bent de websitebouwer binnen één afgeschermd hostingproject: ${p.name}. Werk uitsluitend via de aangeboden projecttools. Je mag nooit paden buiten dit project gebruiken. Je bouwt en onderhoudt websites met HTML, CSS, JavaScript en PHP. Node.js kan onderdeel zijn van een project, maar beheer nooit de hostserver. MySQL-wijzigingen zijn in deze stap nog niet als AI-tool beschikbaar. Lees bestaande bestanden voordat je ze wijzigt. Voer gevraagde bestandswijzigingen daadwerkelijk uit en meld daarna kort wat je hebt gedaan.`;
  let response=await client.responses.create({model:MODEL,instructions,input:prompt,tools});
  let changed=[];
  for(let round=0;round<12;round++){
   const calls=response.output.filter(x=>x.type==="function_call");
   if(!calls.length) return r.json({reply:response.output_text||"Uitgevoerd.",changed,responseId:response.id});
   const outputs=[];
   for(const call of calls){
    let result;
    try{
     const a=JSON.parse(call.arguments||"{}");
     if(call.name==="list_project_files") result=await listFiles(root);
     else if(call.name==="read_project_file") result={path:a.path,content:await readFile(root,a.path)};
     else if(call.name==="write_project_file"){result=await writeFile(root,a.path,a.content);changed.push(a.path);}
     else throw new Error("Onbekende tool");
    }catch(e){result={ok:false,error:e.message};}
    outputs.push({type:"function_call_output",call_id:call.call_id,output:JSON.stringify(result)});
   }
   response=await client.responses.create({model:MODEL,instructions,previous_response_id:response.id,input:outputs,tools});
  }
  throw new Error("Te veel AI-actiestappen");
 }catch(e){r.status(500).json({error:e.message})}
});

app.use("/admin/assets",express.static(path.join(__dirname,"public"),{etag:true,maxAge:"1h"}));
app.get(["/admin","/admin/","/admin/ai","/admin/customers"],(_q,r)=>r.sendFile(path.join(__dirname,"public","index.html")));
app.use((_q,r)=>r.status(404).json({error:"Niet gevonden"}));
app.listen(PORT,HOST,()=>console.log(`Webhosting admin: http://${HOST}:${PORT}/admin`));
