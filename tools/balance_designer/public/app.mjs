import {valueOf,displayed,validate,equal,dps,gridCells,gridAligned,footprintSummary} from '/model.mjs';
const $=s=>document.querySelector(s), escape=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
let state, selected, entity='mobile_infantry', tab='detail', compared=new Set(), queue=Promise.resolve(), pending=0, blocked=false, saveError='';
const timers=new Map(), invalid=new Set();
const profile=()=>state?.profiles.find(p=>p.id===selected);
const format=(field,value)=>value==null?'待核对':typeof value==='object'?JSON.stringify(value):String(displayed(field,value,state.baseline.tick));
function gridNote(field,value,base) {
    if(base.entities[field.entity]?.category!=='building'||!['size.x','size.y'].includes(field.key))return '';
    const cells=gridCells(base,value);
    return cells===null?'格数待核对，请刷新游戏资料':`${cells} 格${gridAligned(cells)?'':'（未对齐整格）'}`;
}
function gridHint(field,value,base,draft=false) {
    const text=gridNote(field,value,base);
    return text?`<small${draft?' data-grid-field="'+field.id+'"':''}>${escape(text)}</small>`:'';
}
function footprintText(p) {
    return footprintSummary(p,entity)+ (gridCells(p.base,1)===null?'':` · 1 格 = ${p.base.gridCell} 逻辑单位`);
}
function status(text,bad=false){$('#save-status').textContent=text;$('#save-status').classList.toggle('difference',bad);}
async function getState(){const response=await fetch('/api/state');if(!response.ok)throw Error('服务不可用');return response.json();}
async function load(){state=await getState();if(!profile())selected=state.profiles[0]?.id;blocked=false;saveError='';$('#reload').hidden=true;render();status('已保存到本机');}
function save(action,{redraw=true}={}) {
    pending++;status('保存中…');
    let failed=false;
    const run=queue.then(async()=>{
        if(blocked)throw Error('请先重新加载。尚未提交的输入仍保留在页面上。');
        const response=await fetch('/api/mutate',{method:'POST',headers:{'Content-Type':'application/json','X-Local-Token':state.token},body:JSON.stringify({...action,revision:state.revision})});
        const data=await response.json();
        if(!response.ok){if(response.status===409||response.status===403){blocked=true;$('#reload').hidden=false;}throw Error(data.error);}
        state=data;
        saveError='';
        if(action.op==='create'||action.op==='copy')selected=state.profiles.at(-1).id;
        if(!profile())selected=state.profiles[0]?.id;
        if(redraw)render();
    });
    queue=run.catch(e=>{failed=true;if(action.op==='set')saveError=e.message;status(e.message,true);$('#notice').textContent=e.message;}).finally(()=>{
        pending--;if(!failed&&!pending&&!blocked&&!invalid.size&&!saveError)status('已保存到本机 · '+new Date().toLocaleTimeString());
    });
    return run;
}
function render(){
    const p=profile(), base=state.baseline;
    if(!base.entities[entity])entity=Object.keys(base.entities)[0];
    $('#profiles').innerHTML=state.profiles.map(p=>`<option value="${p.id}" ${p.id===selected?'selected':''}>${escape(p.name)}</option>`).join('');
    $('#catalog').innerHTML=Object.values(base.entities).map(e=>`<button data-entity="${e.id}" class="${entity===e.id?'active':''}">${escape(e.name)}<small>${escape(e.id)}</small></button>`).join('');
    const conflicts=p?Object.keys(p.conflicts).length:0;
    $('#notice').textContent=[state.recovery,gridCells(base,1)===null?'缺少网格资料，请点击“刷新游戏资料”以显示占地格数。':'',state.stale?'游戏源文件已变化，当前显示的是上次导出的资料。请点击“刷新游戏资料”。':'',conflicts?`${conflicts} 项刷新冲突待处理。草案值已保留；在对应字段选择保留草案或采用游戏值。`:''].filter(Boolean).join(' ');
    $('#version').textContent=`游戏版本 ${base.protocol} · ${base.tick} tick/s · 资料导出 ${new Date(base.exportedAt).toLocaleString()} · 保存版本 ${state.revision}`;
    $('#fingerprints').innerHTML=Object.entries(base.sources).map(([file,sha])=>`<p>${escape(file)}<br><code>${escape(sha)}</code></p>`).join('');
    for(const kind of ['json','csv','diff']){const a=$('#export-'+kind);if(p)a.href=`/api/export?id=${p.id}&format=${kind}`;else a.removeAttribute('href');}
    document.querySelectorAll('[data-op]').forEach(b=>b.disabled=b.dataset.op!=='create'&&!p);
    document.querySelectorAll('[data-tab]').forEach(b=>{b.classList.toggle('active',b.dataset.tab===tab);b.setAttribute('aria-selected',String(b.dataset.tab===tab));});
    renderContent();
}
function fieldsFor(ids){
    const p=profile(), query=$('#search').value.trim().toLowerCase(), category=$('#category').value, diff=$('#diff-only').checked;
    const list=ids.map(id=>state.baseline.fields[id]).filter(f=>f&&(!category||state.baseline.entities[f.entity].category===category)&&(!query||[f.label,f.id,f.origin.path,state.baseline.entities[f.entity].name].join(' ').toLowerCase().includes(query))&&(!diff||Object.hasOwn(p.overrides,f.id)||p.conflicts[f.id]));
    const sort=$('#sort').value;
    return list.sort((a,b)=>sort==='changed'?(Number(Object.hasOwn(p.overrides,b.id))-Number(Object.hasOwn(p.overrides,a.id))||a.id.localeCompare(b.id)):sort==='label'?a.label.localeCompare(b.label,'zh'):a.entity.localeCompare(b.entity)||a.group.localeCompare(b.group,'zh'));
}
function input(f,p){
    const v=valueOf(p,f.id), changed=!equal(v,f.value);
    if(!f.editable)return `<span class="muted">${escape(format(f,v))} · ${f.status==='unsupported'?'待适配':'待核对'}</span>`;
    if(f.type==='boolean')return `<select class="value-input" data-field="${f.id}" aria-label="${escape(f.label)}"><option value="true" ${v?'selected':''}>是</option><option value="false" ${!v?'selected':''}>否</option></select>`;
    return `<input class="value-input ${changed?'changed':''}" data-field="${f.id}" aria-label="${escape(f.label)}" type="number" min="${f.ticks?f.min/state.baseline.tick:f.min}" max="${f.ticks?f.max/state.baseline.tick:f.max}" step="${f.ticks?1/state.baseline.tick:f.type==='integer'?1:'any'}" value="${escape(format(f,v))}">`;
}
function rows(fields,p){return fields.map(f=>{
    const v=valueOf(p,f.id), c=p.conflicts[f.id];
    return `<tr class="${c?'conflict':''}"><td>${escape(state.baseline.entities[f.entity].name)}<small>${escape(f.group)}</small></td><td>${escape(f.label)}<small>${escape(f.key)}</small></td><td>${escape(format(f,f.value))}${gridHint(f,f.value,state.baseline)}</td><td>${input(f,p)}${gridHint(f,v,p.base,true)}${f.ticks?`<small>${escape(v)} tick</small>`:''}${c?`<div class="help">刷新前 ${escape(format(f,c.old))} → 游戏 ${escape(format(f,c.game))}<br>${c.invalid?'草案不符合新字段规则，请采用游戏值或重新输入。':''}<button data-resolve="${f.id}" data-choice="draft" ${c.invalid?'disabled':''}>保留草案</button><button data-resolve="${f.id}" data-choice="game">采用游戏</button></div>`:''}</td><td>${escape(f.unit)}</td><td><small>${escape(f.origin.path)}:${f.origin.line??'?'}</small>${f.note?`<details><summary>规则说明</summary><span class="help">${escape(f.note)}</span></details>`:''}</td></tr>`;
}).join('');}
function table(fields,p){return fields.length?`<div class="table-wrap"><table><thead><tr><th>对象</th><th>属性</th><th>游戏基线</th><th>当前草案</th><th>单位</th><th>来源</th></tr></thead><tbody>${rows(fields,p)}</tbody></table></div>`:'<div class="empty">没有符合筛选条件的属性</div>';}
function renderContent(){
    const p=profile(), root=$('#content');
    if(!p){root.innerHTML='<div class="card empty">暂无方案。点击“新建”，从当前游戏资料开始。</div>';return;}
    if(tab==='compare'){renderCompare();return;}
    if(tab==='table'){root.innerHTML=`<section class="card"><h3>属性总表</h3><p class="help">输入有效值后自动保存。金色边框表示已偏离游戏基线。时间以 ${1/state.baseline.tick} 秒为步长。</p>${table(fieldsFor(Object.keys(state.baseline.fields)),p)}</section>`;return;}
    const e=state.baseline.entities[entity], damage=dps(p,entity), hp=valueOf(p,entity+'.hp'), cost=valueOf(p,entity+'.cost');
    root.innerHTML=`<article class="hero">${entity==='shared'?'<div class="summary"><span class="badge">共享设置</span><h2>公共规则</h2><p>在这里修改已实现的跨单位规则。所有改动都保存在当前方案中。</p></div>':`<img src="/portraits/${e.id}.png" alt="${escape(e.name)} · 当前游戏模型截图">`}<div class="summary"><span class="badge">${{unit:'地面单位',building:'建筑',shared:'系统规则'}[e.category]}</span><h2>${escape(e.name)}</h2><div class="muted">${escape(e.id)}</div><p>${escape(e.description)}</p>${entity!=='shared'?`<div class="stats"><div class="stat"><strong>${hp??'—'}</strong><small>生命值</small></div><div class="stat"><strong>${cost??'—'}</strong><small>矿石造价</small></div><div class="stat"><strong>${damage==null?'不适用':damage.toFixed(2)}</strong><small>理论 DPS</small></div></div>`:''}${e.category==='building'?`<p>建筑占地（当前草案，宽 × 深）：<span id="footprint-summary">${escape(footprintText(p))}</span></p>`:''}<div class="relations">${e.producer?'生产建筑：'+linkEntity(e.producer):''}${e.produces.length?'可生产：'+e.produces.map(linkEntity).join(''):''}${e.targets.length?'<span class="badge">攻击目标：地面</span>':''}</div></div></article><section class="card"><h3>数值与规则</h3>${table(fieldsFor(e.fields),p)}<p class="help">理论 DPS = 单次伤害 × ${state.baseline.tick} ÷ 攻击间隔 tick。假设持续射击、目标始终在射程内；不包含移动、寻敌与首次开火延迟。非战斗单位保留代码字段，但 DPS 显示不适用。</p></section>${p.history.length?`<section class="card"><h3>历史字段（游戏已移除）</h3>${p.history.map(h=>`<p>${escape(h.id)}：基线 ${escape(JSON.stringify(h.baseline))} / 草案 ${escape(JSON.stringify(h.draft))}</p>`).join('')}</section>`:''}`;
    root.querySelectorAll('img').forEach(img=>img.addEventListener('error',()=>{const replacement=document.createElement('div');replacement.className='empty';replacement.textContent='模型截图尚未生成。运行截图入口后刷新页面。';img.replaceWith(replacement);}));
}
function linkEntity(id){return `<button data-entity="${id}">${escape(state.baseline.entities[id]?.name||id)}</button>`;}
function renderCompare(){
    for(const id of [...compared])if(!state.profiles.some(p=>p.id===id))compared.delete(id);
    if(!compared.size)state.profiles.slice(0,3).forEach(p=>compared.add(p.id));
    const profiles=state.profiles.filter(p=>compared.has(p.id)), query=$('#search').value.toLowerCase(), category=$('#category').value;
    let fields=Object.values(state.baseline.fields).filter(f=>(!category||state.baseline.entities[f.entity].category===category)&&[f.label,f.id,state.baseline.entities[f.entity].name].join(' ').toLowerCase().includes(query)&&(!$('#diff-only').checked||profiles.some(p=>!equal(valueOf(p,f.id),f.value))));
    if($('#sort').value==='label')fields.sort((a,b)=>a.label.localeCompare(b.label,'zh'));
    if($('#sort').value==='changed')fields.sort((a,b)=>Number(profiles.some(p=>!equal(valueOf(p,b.id),b.value)))-Number(profiles.some(p=>!equal(valueOf(p,a.id),a.value))));
    $('#content').innerHTML=`<section class="card"><h3>多方案对比</h3><div class="compare-controls">${state.profiles.map(p=>`<label><input type="checkbox" data-compare="${p.id}" ${compared.has(p.id)?'checked':''}> ${escape(p.name)}</label>`).join('')}</div><table><thead><tr><th>对象 / 属性</th><th>游戏基线</th>${profiles.map(p=>`<th>${escape(p.name)}</th>`).join('')}<th>单位</th></tr></thead><tbody>${fields.map(f=>`<tr><td>${escape(state.baseline.entities[f.entity].name)} · ${escape(f.label)}</td><td>${escape(format(f,f.value))}${gridHint(f,f.value,state.baseline)}</td>${profiles.map(p=>`<td class="${equal(valueOf(p,f.id),f.value)?'':'difference'}">${escape(format(f,valueOf(p,f.id)))}${gridHint(f,valueOf(p,f.id),p.base)}${p.conflicts[f.id]?' ⚠ 待处理':''}</td>`).join('')}<td>${escape(f.unit)}</td></tr>`).join('')}</tbody></table></section>`;
}
function commitInput(input){
    const id=input.dataset.field, p=profile(), f=state.baseline.fields[id];
    clearTimeout(timers.get(id));timers.delete(id);
    let value=f.type==='boolean'?input.value==='true':input.value.trim()===''?NaN:Number(input.value);
    if(f.ticks){value*=state.baseline.tick;if(Math.abs(value-Math.round(value))<1e-7)value=Math.round(value);}
    try{validate(f,value);input.setCustomValidity('');invalid.delete(id);}catch(e){input.setCustomValidity(e.message);invalid.add(id);status(e.message+'；未保存',true);return;}
    if(equal(value,valueOf(p,id)))return;
    const profileId=selected;
    save({op:'set',id:profileId,field:id,value},{redraw:false}).then(()=>{
        input.classList.toggle('changed',!equal(value,state.baseline.fields[id].value));
        const stats=document.querySelectorAll('.stat strong');
        if(tab==='detail'&&profileId===selected&&stats.length===3){
            stats[0].textContent=valueOf(profile(),entity+'.hp')??'—';
            stats[1].textContent=valueOf(profile(),entity+'.cost')??'—';
            const damage=dps(profile(),entity);stats[2].textContent=damage==null?'不适用':damage.toFixed(2);
        }
        if(profileId===selected){
            const hint=document.querySelector(`[data-grid-field="${id}"]`);
            if(hint)hint.textContent=gridNote(f,valueOf(profile(),id),profile().base);
            const summary=$('#footprint-summary');
            if(summary)summary.textContent=footprintText(profile());
        }
        if(f.ticks&&input.nextElementSibling?.tagName==='SMALL')input.nextElementSibling.textContent=value+' tick';
        $('#version').textContent=$('#version').textContent.replace(/保存版本 \d+/,`保存版本 ${state.revision}`);
        if(!timers.size&&!pending&&!invalid.size&&document.activeElement!==input)render();
    }).catch(()=>{});
}
function flushInputs(){for(const id of timers.keys()){const el=document.querySelector(`[data-field="${id}"]`);if(el)commitInput(el);}return queue;}
document.addEventListener('input',async event=>{const input=event.target;if(input.dataset.field){input.setCustomValidity('');clearTimeout(timers.get(input.dataset.field));timers.set(input.dataset.field,setTimeout(()=>commitInput(input),450));status('等待保存…');}else if(input.id==='search'){await flushInputs();if(!invalid.size&&!blocked&&!saveError)renderContent();else status('请先处理未保存的输入，再筛选',true);}});
document.addEventListener('change',async event=>{
    const el=event.target;
    if(el.dataset.field)commitInput(el);
    else if(el.id==='profiles'){const next=el.value;await flushInputs();if(blocked||invalid.size||saveError){el.value=selected;status('请先处理未保存的输入',true);return;}selected=next;render();}
    else if(el.dataset.compare){el.checked?compared.add(el.dataset.compare):compared.delete(el.dataset.compare);renderCompare();}
    else if(['category','sort','diff-only'].includes(el.id)){await flushInputs();if(!invalid.size&&!blocked&&!saveError)renderContent();}
});
document.addEventListener('click',async event=>{
    const exportLink=event.target.closest('.exports a');
    if(exportLink){
        event.preventDefault();await flushInputs();
        if(invalid.size||blocked||saveError){status('请先处理未保存的输入再导出',true);return;}
        const download=document.createElement('a');download.href=exportLink.href;download.download='';document.body.append(download);download.click();download.remove();return;
    }
    const b=event.target.closest('button');if(!b)return;
    if(b.id==='reload'){if(confirm('重新加载会丢弃页面中尚未保存的输入，继续？')){timers.forEach(clearTimeout);timers.clear();invalid.clear();await load();}return;}
    if(b.dataset.entity||b.dataset.tab){await flushInputs();if(blocked||invalid.size||saveError){status('请先处理未保存的输入',true);return;}if(b.dataset.entity){entity=b.dataset.entity;tab='detail';$('#category').value='';$('#search').value='';}else tab=b.dataset.tab;render();return;}
    try {
        if(b.dataset.resolve){await save({op:'resolve',id:selected,field:b.dataset.resolve,choice:b.dataset.choice});return;}
        if(b.id==='refresh'){await flushInputs();if(blocked||invalid.size)return;b.disabled=true;status('正在只读导出游戏资料…');try{await save({op:'refresh'});}finally{b.disabled=false;}return;}
        const op=b.dataset.op;if(!op)return;
        await flushInputs();if(blocked||invalid.size)return;
        if(op==='delete'){if(confirm(`删除“${profile().name}”？上一版本会保留在本机备份文件。`))await save({op,id:selected});}
        else {const name=prompt({create:'新方案名称',copy:'复制为',rename:'修改方案名称'}[op],op==='create'?'新方案':profile().name+(op==='copy'?' 副本':''));if(name!==null)await save({op,id:selected,name});}
    }catch(e){status(e.message,true);}
});
window.addEventListener('beforeunload',event=>{if(pending||timers.size||invalid.size||blocked||saveError){event.preventDefault();event.returnValue='';}});
load().catch(e=>{$('#notice').textContent='无法加载：'+e.message;status('加载失败',true);});
