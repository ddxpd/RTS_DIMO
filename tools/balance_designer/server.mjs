import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {randomUUID,createHash} from 'node:crypto';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {buildBaseline,createProfile,setValue,rebase,resolveConflict,csv} from './model.mjs';
const directory=path.dirname(fileURLToPath(import.meta.url));
export const project=path.resolve(directory,'../..');
const exec=promisify(execFile), hash=text=>createHash('sha256').update(text).digest('hex');
const error=(message,status=400)=>Object.assign(Error(message),{status});
export async function sourceHashes(root=project) {
    const files=JSON.parse(await fs.readFile(path.join(root,'tools/balance_designer/sources.json'),'utf8'));
    return Object.fromEntries(await Promise.all(files.map(async p=>[p,hash(await fs.readFile(path.join(root,p)))])));
}
async function exportGame() {
    const before=await sourceHashes();
    await exec('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',path.join(project,'tools/codex/run-balance-designer.ps1'),'-Action','export'],{cwd:project,windowsHide:true,timeout:150000});
    const raw=JSON.parse(await fs.readFile(path.join(project,'.local/balance_designer/raw.json'),'utf8'));
    const after=await sourceHashes();
    if(JSON.stringify(before)!==JSON.stringify(after)||Object.entries(after).some(([p,h])=>raw.sources[p]?.sha256!==h)) throw error('导出期间游戏代码发生变化，请再次刷新',409);
    return buildBaseline(raw);
}
export async function startServer({store=path.join(project,'.local/balance_designer'),port=8811,initial,refresh=exportGame,checkSources=sourceHashes}={}) {
    await fs.mkdir(store,{recursive:true});
    const filename=path.join(store,'state.json'), backup=filename+'.bak', lock=path.join(store,'server.lock');
    try {
        const old=JSON.parse(await fs.readFile(lock,'utf8'));
        let live=true;try{process.kill(old.pid,0);}catch(e){if(e.code==='ESRCH')live=false;else throw e;}
        if(live) throw error('草案目录正在被另一个服务使用');
        await fs.unlink(lock);
    } catch(e) {if(e.code!=='ENOENT') throw e;}
    const lockHandle=await fs.open(lock,'wx');await lockHandle.writeFile(JSON.stringify({pid:process.pid}));await lockHandle.close();
    let state, recovery='', queue=Promise.resolve(), actualPort, closed=false;
    async function atomic(next) {
        const temporary=filename+'.pending';
        const handle=await fs.open(temporary,'w');try {await handle.writeFile(JSON.stringify(next,null,2)+'\n');await handle.sync();}finally{await handle.close();}
        if(state) await fs.copyFile(filename,backup);
        await fs.rename(temporary,filename); state=next;
    }
    function valid(s) {
        if(s.schema!==1||!Number.isInteger(s.revision)||!s.baseline?.fields||!Array.isArray(s.profiles))throw error('不支持或损坏的草案格式');
        for(const p of s.profiles) if(!p.id||!p.base?.fields||!p.overrides||!p.conflicts||!Array.isArray(p.history))throw error('损坏的方案');
        return s;
    }
    try {
        try {state=valid(JSON.parse(await fs.readFile(filename,'utf8')));}
        catch(e) {
            if(e.code==='ENOENT') {
                const base=initial||buildBaseline(JSON.parse(await fs.readFile(path.join(store,'raw.json'),'utf8')));
                await atomic({schema:1,revision:1,baseline:base,profiles:[createProfile(base,'方案 A',randomUUID())]});
            } else {
                const restored=valid(JSON.parse(await fs.readFile(backup,'utf8')));
                await fs.copyFile(filename,filename+'.corrupt-'+Date.now());await fs.copyFile(backup,filename);state=restored;
                recovery='主存档损坏，已恢复上一次原子保存的备份。损坏文件已保留。';
            }
        }
    } catch(e) {await fs.unlink(lock);throw e;}
    const token=randomUUID();
    async function snapshot() {
        let stale=true;try{const now=await checkSources();stale=Object.entries(state.baseline.sources).some(([p,h])=>now[p]!==h);}catch{}
        return {...state,token,stale,recovery,localOnly:true};
    }
    async function body(req) {
        let text=''; for await(const chunk of req) {text+=chunk; if(text.length>1000000)throw error('请求过大',413);}
        try{return JSON.parse(text);}catch{throw error('无效 JSON');}
    }
    function named(value) {if(typeof value!=='string'||!value.trim()||value.trim().length>60)throw error('方案名称需要 1–60 个字符');return value.trim();}
    const server=http.createServer(async(req,res)=>{
        const send=(status,data,type='application/json; charset=utf-8')=>{res.writeHead(status,{'Content-Type':type,'Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Content-Security-Policy':"default-src 'self'; style-src 'self'; img-src 'self'; script-src 'self'; connect-src 'self'; object-src 'none'; frame-ancestors 'none'"});res.end(typeof data==='string'||Buffer.isBuffer(data)?data:JSON.stringify(data));};
        try {
            if(![`127.0.0.1:${actualPort}`,`localhost:${actualPort}`].includes(req.headers.host))throw error('仅允许本机访问',403);
            if(req.headers['sec-fetch-site']==='cross-site')throw error('拒绝跨站请求',403);
            if(req.headers.origin&&!['http://127.0.0.1:'+actualPort,'http://localhost:'+actualPort].includes(req.headers.origin))throw error('拒绝跨站请求',403);
            const url=new URL(req.url,'http://127.0.0.1');
            if(req.method==='GET'&&url.pathname==='/api/state')return send(200,await snapshot());
            if(req.method==='GET'&&url.pathname==='/api/export') {
                const p=state.profiles.find(p=>p.id===url.searchParams.get('id'));if(!p)throw error('方案不存在',404);
                const format=url.searchParams.get('format');
                res.setHeader('Content-Disposition',`attachment; filename="balance-${p.id}.${format==='json'?'json':'csv'}"`);
                return send(200,format==='json'?JSON.stringify({schema:1,exportedAt:new Date().toISOString(),profile:p},null,2):csv(p,format==='diff'),'text/plain; charset=utf-8');
            }
            if(req.method==='POST'&&url.pathname==='/api/mutate') {
                if(req.headers['x-local-token']!==token)throw error('会话已失效，请重新加载',403);
                const action=await body(req);
                const operation=queue.then(async()=>{
                    if(action.revision!==state.revision)throw error('另一窗口已更新草案。请重新加载后再提交修改。',409);
                    const next=structuredClone(state), p=next.profiles.find(p=>p.id===action.id);
                    if(['set','rename','copy','delete','resolve'].includes(action.op)&&!p)throw error('方案不存在',404);
                    switch(action.op) {
                        case 'create':next.profiles.push(createProfile(next.baseline,named(action.name),randomUUID()));break;
                        case 'copy':next.profiles.push({...structuredClone(p),id:randomUUID(),name:named(action.name)});break;
                        case 'rename':p.name=named(action.name);break;
                        case 'delete':next.profiles=next.profiles.filter(x=>x.id!==p.id);break;
                        case 'set':setValue(p,action.field,action.value);break;
                        case 'resolve':resolveConflict(p,action.field,action.choice);break;
                        case 'refresh': {
                            const base=await refresh();
                            if(!base.fields||!base.entities||!base.sources)throw error('资料导出无效');
                            next.baseline=base;next.profiles.forEach(profile=>rebase(profile,base));break;
                        }
                        default:throw error('未知操作');
                    }
                    next.revision++;await atomic(next);return snapshot();
                });
                queue=operation.catch(()=>{});return send(200,await operation);
            }
            const staticFiles={'/':'public/index.html','/app.mjs':'public/app.mjs','/style.css':'public/style.css','/model.mjs':'model.mjs'};
            if(req.method==='GET'&&staticFiles[url.pathname]) {
                const file=staticFiles[url.pathname], ext=path.extname(file);
                return send(200,await fs.readFile(path.join(directory,file)),{'.html':'text/html; charset=utf-8','.mjs':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8'}[ext]);
            }
            const portrait=url.pathname.match(/^\/portraits\/([a-z_]+)\.png$/);
            if(req.method==='GET'&&portrait&&state.baseline.entities[portrait[1]])return send(200,await fs.readFile(path.join(project,'assets/concept_art/balance_designer',portrait[1]+'.png')),'image/png');
            throw error('未找到',404);
        } catch(e){send(e.status|| (e.code==='ENOENT'?404:400),{error:e.message});}
    });
    try {await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(port,'127.0.0.1',()=>{actualPort=server.address().port;resolve();});});}
    catch(e){await fs.unlink(lock);throw e;}
    return {server,url:'http://127.0.0.1:'+actualPort,close:async()=>{if(closed)return;closed=true;await new Promise(r=>server.close(r));await queue;await fs.unlink(lock);}};
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
    try {
        const app=await startServer();console.log('BALANCE_DESIGNER READY '+app.url);
        for(const signal of ['SIGINT','SIGTERM'])process.on(signal,()=>app.close().then(()=>process.exit(0)));
    } catch(e) {console.error(e.code==='EADDRINUSE'?'端口 8811 已占用，请先关闭占用程序。':e.message);process.exitCode=1;}
}
