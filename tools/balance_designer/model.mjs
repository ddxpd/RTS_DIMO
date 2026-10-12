// Shared, side-effect-free catalogue and draft operations. Values stay in simulation units.
const metadata = {
    hp:['生命值','基本','点',1], cost:['造价','基本','矿石',0], time:['生产 / 建造时间','基本','秒',1],
    speed:['移动速度','移动','逻辑单位/秒',0], radius:['碰撞半径','移动','逻辑单位',1],
    range:['攻击距离','战斗','逻辑单位',0], damage:['单次伤害','战斗','点',0], cooldown:['攻击间隔','战斗','秒',1],
    'size.x':['占地宽度','占地','逻辑单位',1], 'size.y':['占地深度','占地','逻辑单位',1], eye:['视线高度','视野','逻辑单位',0],
    flight_duration:['起飞 / 降落时长','飞行','秒',1], flight_speed:['飞行速度','飞行','逻辑单位/秒',0], flight_turn:['飞行转向速度','飞行','度/秒',0]
};
export const equal = (a,b) => JSON.stringify(a) === JSON.stringify(b);
const copy = v => structuredClone(v);
export function buildBaseline(raw) {
    const fields = {}, entities = {}, source = 'scripts/definitions/entity_catalog.gd';
    const {names={},descriptions={},producers={}}=raw.catalog||{};
    const location = (path, needle) => {
        const text=raw.sources[path]?.text||'', index=text.indexOf(needle);
        return {path,line:index<0?null:(text.slice(0,index).match(/\n/g)||[]).length+1};
    };
    function add(entity,key,value,type,meta,origin,status='verified',note='') {
        const [label,group,unit,min] = meta || [key,'新增属性','',0];
        const id = `${entity}.${key}`, ticks = ['time','cooldown','flight_duration','mining_interval','dock_retry'].includes(key);
        fields[id] = {id,entity,key,label,group,unit,min:min??0,max:1000000,type,value,origin,status,note,
            ticks, editable:status==='verified' && ['integer','number','boolean'].includes(type)};
        entities[entity].fields.push(id);
    }
    for (const [category,table] of [['unit',raw.units],['building',raw.buildings]]) {
        for (const [id,props] of Object.entries(table)) {
            entities[id] = {id,name:names[id]||id,category,description:descriptions[id]||'游戏中新加入的对象，属性自动导出。',fields:[], targets:raw.targets[id]||[],
                produces:Object.keys(raw.units).filter(kind=>producers[kind]===id), producer:producers[id]||null,dockPads:raw.dockPads?.[id]||[],internalDockPads:raw.internalDockPads?.includes(id)||false};
            const origin = location(source,`"${id}": {`);
            for (const [key,item] of Object.entries(props)) {
                if (item.type==='vector2') ['x','y'].forEach((axis,i)=>add(id,`${key}.${axis}`,item.value[i],'number',metadata[`${key}.${axis}`],origin));
                else add(id,key,item.value,item.type,metadata[key],origin, item.type==='unknown'?'unsupported':'verified');
            }
            if (id in raw.eyes) add(id,'eye',raw.eyes[id],'number',metadata.eye,location(source,'const EYE_HEIGHTS'));
        }
    }
    if (entities.barracks) for (const [key,value] of Object.entries(raw.flight)) {
        const id = {duration:'flight_duration',speed:'flight_speed',turn:'flight_turn'}[key];
        if(id) add('barracks',id,value,key==='duration'?'integer':'number',metadata[id],location('scripts/barracks_flight.gd',`const ${key==='turn'?'TURN_SPEED':key.toUpperCase()}`));
    }
    entities.shared={id:'shared',name:names.shared,category:'shared',description:descriptions.shared,fields:[],targets:[],produces:[]};
    const mappings = [
    [
        "capacity",
        "矿车容量",
        "矿业",
        "矿石",
        1,
        "容量也受快照校验限制；未来同步需同时核对 snapshot_validator.gd。"
    ],
    [
        "mining_interval",
        "采矿周期",
        "矿业",
        "秒",
        1,
        "每次采矿需达到此工作 tick 数。"
    ],
    [
        "mining_amount",
        "每次采集量",
        "矿业",
        "矿石",
        1,
        "不足时采完剩余矿石。"
    ],
    [
        "mining_reach",
        "采集中心距离",
        "矿业",
        "逻辑单位",
        0,
        "矿车中心到晶矿中心的最大采集距离，不额外叠加单位半径。"
    ],
    [
        "build_reach",
        "建筑部署距离",
        "经济",
        "逻辑单位",
        1,
        "从已完成的友方地面建筑中心计算。"
    ],
    [
        "queue_limit",
        "生产队列上限",
        "经济",
        "个",
        1,
        "同时受 snapshot_validator.gd 的队列快照校验限制。"
    ],
    [
        "dock_retry",
        "泊位拥堵重试",
        "卸矿",
        "秒",
        1,
        "达到阈值后尝试重新安排泊位。"
    ],
    [
        "dock_offset",
        "泊位左右偏移",
        "卸矿",
        "逻辑单位",
        1,
        "左右对称偏移；未来同步必须同时调整入口、模型通道与碰撞几何。"
    ],
    [
        "dock_depth",
        "泊位纵向偏移",
        "卸矿",
        "逻辑单位",
        -1000000,
        "相对于卸载站中心的逻辑 Y 轴偏移。"
    ],
    [
        "dock_entrance",
        "入口纵向偏移",
        "卸矿",
        "逻辑单位",
        -1000000,
        "相对于卸载站中心的逻辑 Y 轴偏移。"
    ],
    [
        "vision",
        "共享视野距离",
        "视野",
        "逻辑单位",
        1,
        "视线仍受高度和遮挡影响。"
    ]
];
    for (const [key,label,group,unit,min,note] of mappings) {
        const path='scripts/definitions/gameplay_rules.gd', origin=location(path,`const ${key.toUpperCase()} :=`);
        const item=raw.shared?.[key], verified=item && ['number','integer'].includes(item.type) && Number.isFinite(item.value) && origin.line!==null;
        add('shared',key,verified?item.value:null,item?.type||'integer',[label,group,unit,min],origin,verified?'verified':'unverified',note);
    }
    return {schema:1,exportedAt:raw.exportedAt,protocol:raw.protocol,tick:raw.tick,gridCell:raw.gridCell,entities,fields,sources:Object.fromEntries(Object.entries(raw.sources).map(([p,s])=>[p,s.sha256]))};
}
export function gridCells(base,value) {
    return Number.isFinite(base.gridCell)&&base.gridCell>0&&Number.isFinite(value)?value/base.gridCell:null;
}
export function gridAligned(value) {return Math.abs(value-Math.round(value))<0.00001;}
export function footprintSummary(profile,entity) {
    if(profile.base.entities[entity]?.category!=='building')return '';
    const width=gridCells(profile.base,valueOf(profile,entity+'.size.x'));
    const depth=gridCells(profile.base,valueOf(profile,entity+'.size.y'));
    if(width===null||depth===null)return '格数待核对，请刷新游戏资料';
    const pads=profile.base.entities[entity].dockPads||[];
    if(pads.length){
        const dims=pads.map(([x,y])=>[gridCells(profile.base,x),gridCells(profile.base,y)]);
        if(profile.base.entities[entity].internalDockPads){
            const originalWidth=gridCells(profile.base,profile.base.fields[entity+'.size.x']?.value);
            const originalDepth=gridCells(profile.base,profile.base.fields[entity+'.size.y']?.value);
            const area=width*depth;
            const collision=width===originalWidth&&depth===originalDepth?`阻挡区 ${area-dims.reduce((sum,[x,y])=>sum+x*y,0)} 格`:'草案尺寸已改变，阻挡布局待调整';
            return `占地 ${width} × ${depth} 格，共 ${area} 格；${collision}；卸载通道 ${dims.length} 处，各 ${dims[0][0]} × ${dims[0][1]} 格${gridAligned(width)&&gridAligned(depth)?'':'（未对齐整格）'}`;
        }
        const area=width*depth+dims.reduce((sum,[x,y])=>sum+x*y,0);
        return `主体 ${width} × ${depth} 格；卸载区 ${dims.map(([x,y])=>`${x} × ${y} 格`).join(' + ')}；共 ${area} 格；外接 ${width} × ${depth+Math.max(...dims.map(p=>p[1]))} 格${gridAligned(width)&&gridAligned(depth)?'':'（未对齐整格）'}`;
    }
    return `${width} × ${depth} 格，共 ${width*depth} 格${gridAligned(width)&&gridAligned(depth)?'':'（未对齐整格）'}`;
}
export function valueOf(profile, id) { return Object.hasOwn(profile.overrides,id)?profile.overrides[id]:profile.base.fields[id]?.value; }
export function validate(field,value) {
    if(!field?.editable) throw Error('此属性只读或待核对');
    if(field.type==='boolean') { if(typeof value!=='boolean') throw Error('需要布尔值'); return; }
    if(typeof value!=='number'||!Number.isFinite(value)||value<field.min||value>field.max) throw Error(`数值须在 ${field.min}–${field.max} 之间`);
    if((field.type==='integer'||field.ticks)&&!Number.isInteger(value)) throw Error(field.ticks?'时间必须是完整 tick（当前 0.05 秒）':'此属性必须为整数');
}
export function createProfile(base,name,id) {return {id,name,base:copy(base),overrides:{},conflicts:{},history:[],updatedAt:new Date().toISOString()};}
export function setValue(profile,id,value) {
    const field=profile.base.fields[id]; validate(field,value);
    if(equal(value,field.value)) delete profile.overrides[id]; else profile.overrides[id]=value;
    delete profile.conflicts[id];
    profile.updatedAt=new Date().toISOString();
}
export function rebase(profile,next) {
    for(const [id,old] of Object.entries(profile.base.fields)) {
        const fresh=next.fields[id], mine=valueOf(profile,id), changed=Object.hasOwn(profile.overrides,id), prior=profile.conflicts[id];
        if(!fresh) {
            profile.history.push({id,label:old.label,entity:old.entity,baseline:old.value,draft:mine,reason:'游戏已移除此字段',at:next.exportedAt});
            delete profile.overrides[id]; delete profile.conflicts[id]; continue;
        }
        if(!changed) { delete profile.conflicts[id]; continue; }
        if(equal(mine,fresh.value)) {delete profile.overrides[id];delete profile.conflicts[id];continue;}
        let invalid=false; try {validate(fresh,mine);} catch {invalid=true;}
        if(prior || !equal(old.value,fresh.value) || invalid) profile.conflicts[id]={old:prior?.old??old.value,game:fresh.value,draft:mine,invalid};
    }
    profile.base=copy(next); profile.updatedAt=new Date().toISOString(); return profile;
}
export function resolveConflict(profile,id,choice) {
    if(!profile.conflicts[id]) throw Error('冲突已不存在');
    if(choice==='game') {delete profile.overrides[id];delete profile.conflicts[id];}
    else if(choice==='draft') {validate(profile.base.fields[id],profile.overrides[id]);delete profile.conflicts[id];}
    else throw Error('未知冲突处理方式');
}
export function displayed(field,value,tick) {return field.ticks&&typeof value==='number'?Number((value/tick).toFixed(6)):value;}
export function dps(profile,entity) {
    const damage=valueOf(profile,entity+'.damage'), cooldown=valueOf(profile,entity+'.cooldown');
    return damage>0&&cooldown>0?damage*profile.base.tick/cooldown:null;
}
export function csv(profile,diffOnly=false) {
    const rows=[['对象','字段','游戏基线','草案','单位','原始基线','原始草案','状态','来源']];
    for(const f of Object.values(profile.base.fields)) {
        const v=valueOf(profile,f.id); if(diffOnly&&equal(v,f.value)&&!profile.conflicts[f.id]) continue;
        rows.push([profile.base.entities[f.entity].name,f.label,displayed(f,f.value,profile.base.tick),displayed(f,v,profile.base.tick),f.unit,f.value,v,profile.conflicts[f.id]?'冲突':f.status,`${f.origin.path}:${f.origin.line??'?'}`]);
    }
    for(const h of profile.history) rows.push([profile.base.entities[h.entity]?.name||h.entity,h.label,h.baseline,h.draft,'',h.baseline,h.draft,h.reason,'历史字段']);
    const cell = x => '"'+String(x??'').replace(/^[=+@-]/,"'$&").replaceAll('"','""')+'"';
    return '\uFEFF'+rows.map(r=>r.map(cell).join(',')).join('\r\n');
}
