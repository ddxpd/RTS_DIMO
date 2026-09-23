from pathlib import Path

path = Path('tools/effect-gallery/index.html')
source = path.read_text(encoding='utf-8')

css_anchor = '@media(max-width:980px)'
css = '''.generated{margin:0 0 20px;padding:18px;border:1px solid var(--border);border-radius:16px;background:rgba(23,36,38,.62)}
.generated-head{display:flex;justify-content:space-between;align-items:center;gap:18px;margin-bottom:14px}
.generated-head h2{margin:0 0 6px;font-size:21px}.generated-head p{margin:0;color:var(--muted);font-size:13px}
.generated-grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:12px}
.generated-card{overflow:hidden;border:1px solid var(--border);border-radius:12px;background:#0d1516}
.generated-card.wide{grid-column:1/-1}
.generated-card img{display:block;width:100%;aspect-ratio:16/10;object-fit:cover;background:#080d0e}
.generated-card span{display:block;padding:10px 12px;color:var(--muted);font-size:13px}
'''
if css_anchor not in source:
    raise SystemExit('CSS anchor missing')
source = source.replace(css_anchor, css + css_anchor, 1)

html_anchor = '<p class="status" id="status"'
html = '''<section class="generated" aria-label="本地生成概念图">
<div class="generated-head"><div><h2>高科技人类阵营：兵营概念图</h2><p>这些文件来自本地 generated 目录，刷新后仍会在此显示；点右侧按钮可复制进上方 IndexedDB 图库。</p></div><button class="secondary" id="import-generated" type="button">导入这组概念图</button></div>
<div class="generated-grid">
<article class="generated-card wide"><img src="generated/00_contact_sheet.png" alt="高科技人类阵营兵营概念图总览"><span>概念图总览</span></article>
<article class="generated-card"><img src="generated/barracks_tech_blueprint.png" alt="蓝图风格高科技兵营"><span>蓝图 / 制造模块</span></article>
<article class="generated-card"><img src="generated/barracks_tech_night_ops.png" alt="夜间作战高科技兵营"><span>夜间作战 / 全息部署</span></article>
<article class="generated-card"><img src="generated/barracks_tech_modules.png" alt="高科技兵营扩展模块"><span>扩展模块系列</span></article>
<article class="generated-card"><img src="generated/barracks_tech_combat_ready.png" alt="战斗就绪高科技兵营"><span>战斗就绪 / 护盾上线</span></article>
</div>
</section>
'''
if html_anchor not in source:
    raise SystemExit('HTML anchor missing')
source = source.replace(html_anchor, html + html_anchor, 1)

capture_old = '"folder-input","status"'
capture_new = '"folder-input","import-generated","status"'
if capture_old not in source:
    raise SystemExit('capture anchor missing')
source = source.replace(capture_old, capture_new, 1)

bind_anchor = 'el["folder-input"].onchange=async e=>{await importFiles([...e.target.files]);e.target.value=""};'
bind_new = bind_anchor + 'el["import-generated"].onclick=importGeneratedImages;'
if source.count(bind_anchor) != 1:
    raise SystemExit('bind anchor count unexpected')
source = source.replace(bind_anchor, bind_new, 1)

script_anchor = 'function switchTab(tab){'
script = '''const GENERATED_FILES=[
 {file:"generated/00_contact_sheet.png",label:"概念图总览"},
 {file:"generated/barracks_tech_blueprint.png",label:"蓝图 / 制造模块"},
 {file:"generated/barracks_tech_night_ops.png",label:"夜间作战 / 全息部署"},
 {file:"generated/barracks_tech_modules.png",label:"扩展模块系列"},
 {file:"generated/barracks_tech_combat_ready.png",label:"战斗就绪 / 护盾上线"}
];
async function importGeneratedImages(){
 const button=el["import-generated"];button.disabled=true;
 try{
  const files=await Promise.all(GENERATED_FILES.map(async item=>{
   const response=await fetch(item.file,{cache:"no-cache"});
   if(!response.ok)throw new Error(item.file+" HTTP "+response.status);
   const blob=await response.blob();
   return new File([blob],item.file.split("/").pop(),{type:blob.type||"image/png",lastModified:Date.UTC(2026,8,23)});
  }));
  await importFiles(files);
 }catch(error){
  console.error("导入生成概念图失败",error);
  setStatus("导入生成概念图失败："+error.message,true);
 }finally{
  button.disabled=false;
 }
}

'''
if source.count(script_anchor) != 1:
    raise SystemExit('script anchor count unexpected')
source = source.replace(script_anchor, script + script_anchor, 1)

path.write_text(source, encoding='utf-8', newline='\n')
print('updated', path, len(source))
