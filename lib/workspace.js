import fs from "node:fs/promises";
import path from "node:path";

const ALLOWED_EXT = new Set([".html",".htm",".css",".js",".mjs",".json",".php",".md",".txt",".xml",".svg"]);
const MAX_FILE = 1024 * 1024;

export function safeRoot(baseRoot, projectSlug) {
  if (!/^[a-z0-9][a-z0-9_-]{0,62}$/i.test(projectSlug)) throw new Error("Ongeldige projectnaam");
  return path.resolve(baseRoot, projectSlug);
}

export function safePath(root, rel) {
  if (typeof rel !== "string" || rel.includes("\0")) throw new Error("Ongeldig pad");
  const cleaned=rel.replaceAll("\\","/").replace(/^\/+/,"");
  const resolved=path.resolve(root, cleaned);
  if (resolved !== root && !resolved.startsWith(root + path.sep)) throw new Error("Pad buiten project geweigerd");
  return resolved;
}

export async function listFiles(root) {
  const out=[];
  async function walk(dir, prefix="") {
    for (const ent of await fs.readdir(dir,{withFileTypes:true})) {
      if (["node_modules",".git",".env"].includes(ent.name)) continue;
      const rel=prefix ? `${prefix}/${ent.name}` : ent.name;
      if (ent.isDirectory()) await walk(path.join(dir,ent.name),rel);
      else if (ALLOWED_EXT.has(path.extname(ent.name).toLowerCase())) out.push(rel);
      if (out.length >= 500) return;
    }
  }
  await fs.mkdir(root,{recursive:true});
  await walk(root);
  return out.sort();
}

export async function readFile(root, rel) {
  const file=safePath(root,rel);
  const ext=path.extname(file).toLowerCase();
  if (!ALLOWED_EXT.has(ext)) throw new Error("Bestandstype niet toegestaan");
  const st=await fs.stat(file);
  if (st.size > MAX_FILE) throw new Error("Bestand te groot");
  return await fs.readFile(file,"utf8");
}

export async function writeFile(root, rel, content) {
  const file=safePath(root,rel);
  const ext=path.extname(file).toLowerCase();
  if (!ALLOWED_EXT.has(ext)) throw new Error("Bestandstype niet toegestaan");
  if (typeof content !== "string" || Buffer.byteLength(content,"utf8") > MAX_FILE) throw new Error("Inhoud te groot");
  await fs.mkdir(path.dirname(file),{recursive:true});
  const tmp=file+".ai-tmp";
  await fs.writeFile(tmp,content,"utf8");
  await fs.rename(tmp,file);
  return {ok:true,path:rel,bytes:Buffer.byteLength(content,"utf8")};
}
