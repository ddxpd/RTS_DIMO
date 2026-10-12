const $ = id => document.getElementById(id);
const imageFormats = new Set(['png', 'jpg', 'jpeg', 'webp', 'gif', 'svg']);
const scopeLabels = { all: '全部资源', readonly: '原文件仅查看', runtime: '正式游戏资源', source: '制作源文件', editable: '文件可改动', concept: '概念与效果图', imported: '个人导入' };
const state = { assets: [], categories: [], scope: 'all', category: 'all', token: '', selected: null, checked: new Set(), limit: 48, parent: null, uploading: false, xhr: null, detailRequest: 0 };
const RECENT = 'recent-day';
state.temporaryRecent = new Set();
const inCategory = (a, id) => id === 'all' || (id === RECENT ? a.isRecent || state.temporaryRecent.has(a.id) : a.categoryIds.includes(id));
state.imageQueue = []; state.metaBaseline = null; state.detailBusy = false;
const inScope = (asset, scope = state.scope) => scope === 'all' || asset.scope === scope || asset.access === scope;
const bytes = n => n >= 1073741824 ? (n / 1073741824).toFixed(2) + ' GB' : n >= 1048576 ? (n / 1048576).toFixed(1) + ' MB' : n >= 1024 ? (n / 1024).toFixed(0) + ' KB' : n + ' B';
const date = n => new Date(n).toLocaleString('zh-CN', { hour12: false });
const fileURL = (id, mode = 'file') => `/api/assets/${encodeURIComponent(id)}/${mode}`;
const node = (tag, className, text) => { const el = document.createElement(tag); if (className) el.className = className; if (text !== undefined) el.textContent = text; return el; };
let toastTimer;
function toast(text, error = false) { $('toast').textContent = text; $('toast').classList.toggle('error', error); $('toast').hidden = false; clearTimeout(toastTimer); toastTimer = setTimeout(() => $('toast').hidden = true, 4500); }
async function api(url, options = {}) {
    const response = await fetch(url, { ...options, headers: { 'X-Library-Token': state.token, ...(options.body ? { 'Content-Type': 'application/json' } : {}), ...options.headers } });
    const value = await response.json();
    if (!response.ok) throw Error(value.error || `请求失败 ${response.status}`);
    return value;
}
async function refresh({ resetRecent = false } = {}) {
    try {
        const result = await api('/api/catalog');
        if (!resetRecent) { const old = new Map(state.assets.map(a => [a.id, a.isRecent])); for (const a of result.assets) if (old.has(a.id)) a.isRecent = old.get(a.id); }
        else state.temporaryRecent.clear();
        state.assets = result.assets; state.categories = result.categories; state.automaticCategories = result.automaticCategories; state.token = result.token;
        state.checked = new Set([...state.checked].filter(id => state.assets.some(a => a.id === id)));
        $('load-error').hidden = true;
        for (const scope of Object.keys(scopeLabels)) $('count-' + scope).textContent = state.assets.filter(a => inScope(a, scope)).length;
        categoryOptions($('edit-category')); categoryOptions($('import-category'), true);
        categoryOptions($('quick-category')); categoryOptions($('batch-category-select'));
        $('total-size').textContent = bytes(state.assets.reduce((sum, a) => sum + a.size, 0));
        $('total-count').textContent = `${state.assets.length} 个资源 · 本地索引`;
        render();
    } catch (error) { $('load-error').textContent = '无法连接资源库：' + error.message + '。请启动服务后刷新页面。'; $('load-error').hidden = false; }
}
function filtered() {
    const search = $('search').value.trim().toLowerCase();
    const format = $('format').value;
    const found = state.assets.filter(a => inScope(a) && inCategory(a, state.category)
        && (!search || `${a.title} ${a.name} ${a.relativePath} ${a.tags.join(' ')}`.toLowerCase().includes(search))
        && (format === 'all' || (format === 'image' && imageFormats.has(a.format)) || (format === 'document' && !imageFormats.has(a.format) && !['glb', 'blend'].includes(a.format)) || a.format === format));
    const sort = $('sort').value;
    const rank = a => a.scope === 'runtime' && a.format === 'glb' ? 0 : a.scope === 'concept' && imageFormats.has(a.format) ? 1 : imageFormats.has(a.format) ? 2 : 3;
    return found.sort(sort === 'name' ? (a, b) => a.title.localeCompare(b.title, 'zh-CN') : sort === 'size' ? (a, b) => b.size - a.size : sort === 'curated' ? (a, b) => rank(a) - rank(b) || b.modified - a.modified : (a, b) => b.modified - a.modified);
}
function fallback(record) {
    const mark = node('div', 'card-symbol', record.format === 'glb' ? '⬡' : record.format === 'blend' ? '◉' : '▤');
    mark.append(node('small', '', record.format === 'glb' ? '点击交互预览' : record.format === 'blend' ? 'BLENDER SOURCE' : record.format.toUpperCase() + ' FILE'));
    return mark;
}
function render() {
    renderCategories();
    const found = filtered();
    $('gallery').replaceChildren();
    $('result-count').textContent = `${found.length} 个资源`;
    $('empty').hidden = found.length !== 0;
    $('more').hidden = found.length <= state.limit;
    for (const a of found.slice(0, state.limit)) {
        const card = node('article', 'card'); card.dataset.id = a.id;
        const open = node('button', 'card-main'); open.title = a.relativePath; open.setAttribute('aria-label', '查看 ' + a.title);
        const preview = node('div', 'card-preview' + (a.scope === 'concept' && a.format !== 'svg' ? ' photo' : ''));
        if (imageFormats.has(a.format) || a.hasPoster) {
            const image = node('img'); image.src = fileURL(a.id, 'thumb'); image.alt = a.title; image.loading = 'lazy';
            image.onerror = () => { image.replaceWith(fallback(a)); };
            preview.append(image);
        } else preview.append(fallback(a));
        preview.append(node('span', 'card-format', a.format.toUpperCase()));
        const info = node('div', 'card-info'); info.append(node('h2', 'card-title', a.title));
        const sub = node('div', 'card-sub'); sub.append(node('span', '', `${a.categoryIds.map(id => state.categories.find(c => c.id === id)?.name).join(' / ')} · ${scopeLabels[a.scope]}`), node('span', '', bytes(a.size))); info.append(sub);
        info.append(node('small', 'access-badge ' + a.access, a.access === 'editable' ? '文件可改动 · 删除前检查引用' : '原文件仅查看'));
        if (a.tags.length || a.version > 1) { const tags = node('div', 'card-tags'); for (const tag of [...(a.version > 1 ? ['v' + a.version] : []), ...a.tags].slice(0, 3)) tags.append(node('span', 'tag', tag)); info.append(tags); }
        open.append(preview, info); open.onclick = () => openDetail(a.id); card.append(open);
        const select = node('input', 'asset-check'); select.type = 'checkbox'; select.checked = state.checked.has(a.id);
        select.setAttribute('aria-label', '选择资源 ' + a.title); select.title = '选择后可删除、归类；两项可比较';
        select.onchange = () => {
            if (!select.checked) state.checked.delete(a.id);
            else if (state.checked.size < 1000) state.checked.add(a.id);
            else toast('每次最多选择 1000 个资源', true);
            render();
        };
        card.append(select);
        $('gallery').append(card);
    }
    $('batch-count').textContent = `已选 ${state.checked.size} 个`;
    $('batch-delete').disabled = state.checked.size === 0;
    $('batch-category').disabled = !state.assets.some(a => state.checked.has(a.id) && imageFormats.has(a.format));
    $('batch-recent').disabled = !state.assets.some(a => state.checked.has(a.id) && imageFormats.has(a.format));
    $('compare-open').disabled = state.checked.size !== 2;
    $('compare-open').title = state.checked.size === 2 ? '比较所选两个资源' : '恰好选择两个资源时可比较';
}
function openDialog(id) { if (!$(id).open) $(id).showModal(); }
let deletionTicket = null, deleting = false;
$('batch-all').onclick = () => { for (const asset of filtered().slice(0, state.limit)) { if (state.checked.size >= 1000) { toast('每次最多选择 1000 个资源', true); break; } state.checked.add(asset.id); } render(); };
$('batch-clear').onclick = () => { state.checked.clear(); render(); };
$('batch-delete').onclick = () => previewDeletion([...state.checked]);
function addTemporaryRecent(ids) {
    for (const id of ids) if (state.assets.some(a => a.id === id && imageFormats.has(a.format))) state.temporaryRecent.add(id);
    render(); toast('已临时加入最近一天新增；刷新后重新按入库时间归类');
}
$('batch-recent').onclick = () => addTemporaryRecent([...state.checked]);
$('detail-recent').onclick = () => addTemporaryRecent([state.selected.id]);
$('delete-file').onclick = async () => { if (await allowDetailLeave()) previewDeletion([state.selected.id]); };
$('delete-close').onclick = () => { if (!deleting) $('delete-dialog').close(); };
$('delete-dialog').addEventListener('cancel', e => { if (deleting) e.preventDefault(); });
function deletionRows(entries) {
    $('delete-list').replaceChildren();
    for (const entry of entries) {
        const row = node('div', 'delete-row');
        row.append(node('strong', '', entry.name), node('small', '', entry.path || ''), node('span', '', entry.reason));
        if (entry.files?.length > 1) for (const file of entry.files) row.append(node('small', file.status === 'failed' ? 'form-error' : '', `${file.name} · ${bytes(file.size)}${file.reason ? ' · ' + file.reason : ''}\n${file.path}`));
        if (['failed', 'partial'].includes(entry.status) || entry.allowed === false) row.classList.add('blocked');
        $('delete-list').append(row);
    }
}
async function previewDeletion(ids) {
    deletionTicket = null; $('delete-error').hidden = true; $('delete-confirm').hidden = false; $('delete-confirm').disabled = true;
    $('delete-confirm').textContent = '确认移入回收站'; $('delete-summary').textContent = '正在检查文件、引用和权限…'; $('delete-list').replaceChildren();
    openDialog('delete-dialog');
    try {
        const result = await api('/api/deletions/preview', { method: 'POST', body: JSON.stringify({ ids }) });
        deletionTicket = result.ticket; deletionRows(result.entries);
        const allowed = result.entries.filter(e => e.allowed).length;
        $('delete-summary').textContent = `已选 ${result.entries.length} 个，可删除 ${allowed} 个（${bytes(result.bytes)}），其余项目将跳过。`;
        $('delete-confirm').disabled = allowed === 0;
    } catch (error) { $('delete-error').textContent = error.message; $('delete-error').hidden = false; }
}
$('delete-confirm').onclick = async () => {
    if (!deletionTicket || deleting) return;
    deleting = true; $('delete-confirm').disabled = true; $('delete-close').disabled = true; $('delete-confirm').textContent = '正在移入回收站…';
    // Release preview handles before asking Windows to move any selected files.
    if ($('detail-dialog').open) $('detail-dialog').close();
    if ($('compare-dialog').open) $('compare-dialog').close();
    try {
        const result = await api('/api/deletions/execute', { method: 'POST', body: JSON.stringify({ ticket: deletionTicket }) });
        const done = result.results.filter(r => ['deleted', 'removed'].includes(r.status));
        state.checked = new Set(result.results.filter(r => r.status === 'failed').map(r => r.id));
        deletionRows(result.results); $('delete-summary').textContent = `已移除 ${done.length} 个，部分完成 ${result.results.filter(r => r.status === 'partial').length} 个，失败 ${result.results.filter(r => r.status === 'failed').length} 个，跳过 ${result.results.filter(r => r.status === 'skipped').length} 个。`;
        $('delete-confirm').hidden = true; deletionTicket = null;
    } catch (error) { $('delete-error').textContent = error.message + '；请关闭此窗口，刷新索引后重新检查。'; $('delete-error').hidden = false; }
    finally { deleting = false; $('delete-close').disabled = false; await refresh(); }
};
function chosenCategories(element) { return [...element.querySelectorAll('input:checked')].map(input => input.value); }
function setCategories(element, ids) { for (const input of element.querySelectorAll('input')) input.checked = ids.includes(input.value); }
function categoryOptions(element, automatic = false) {
    const values = chosenCategories(element); element.replaceChildren();
    for (const category of state.categories) {
        const label = node('label', 'category-choice'); const input = node('input'); input.type = 'checkbox'; input.value = category.id;
        label.append(input, document.createTextNode(category.name)); element.append(label);
    }
    setCategories(element, values);
}
let batchCategoryIds = [], categorizing = false;
$('batch-category').onclick = () => {
    batchCategoryIds = state.assets.filter(a => state.checked.has(a.id) && imageFormats.has(a.format)).map(a => a.id);
    $('category-summary').textContent = `将修改 ${batchCategoryIds.length} 张图片的分类，跳过 ${state.checked.size - batchCategoryIds.length} 个非图片资源。`;
    categoryOptions($('batch-category-select')); setCategories($('batch-category-select'), []); $('batch-category-mode').value = 'add';
    $('category-error').hidden = true; $('category-confirm').disabled = !batchCategoryIds.length;
    openDialog('category-dialog');
};
$('category-close').onclick = () => { if (!categorizing) $('category-dialog').close(); };
$('category-dialog').addEventListener('cancel', e => { if (categorizing) e.preventDefault(); });
$('category-confirm').onclick = async () => {
    if (categorizing) return;
    categorizing = true; $('category-confirm').disabled = true; $('category-close').disabled = true;
    $('batch-category-select').disabled = true; $('category-error').hidden = true;
    try {
        await setImageCategory(batchCategoryIds, chosenCategories($('batch-category-select')), $('batch-category-mode').value);
        for (const id of batchCategoryIds) state.checked.delete(id);
        await refresh(); $('category-dialog').close(); toast(`已设置 ${batchCategoryIds.length} 张图片的分类`);
    } catch (error) { $('category-error').textContent = error.message; $('category-error').hidden = false; }
    finally { categorizing = false; $('category-confirm').disabled = false; $('category-close').disabled = false; $('batch-category-select').disabled = false; }
};
function setImageCategory(ids, categoryIds, mode = 'replace') {
    return api('/api/assets/category', { method: 'POST', body: JSON.stringify({ ids, categoryIds, mode }) });
}
function metaForm() {
    return { title: $('edit-title').value, categoryIds: chosenCategories($('edit-category')), tags: $('edit-tags').value.split(/[,，]/).map(x => x.trim()).filter(Boolean), notes: $('edit-notes').value, relatedIds: [...$('related-select').selectedOptions].map(x => x.value) };
}
function setMetaDisabled(disabled) {
    for (const id of ['edit-title', 'edit-category', 'edit-tags', 'edit-notes', 'related-select', 'save-meta']) $(id).disabled = disabled;
}
function renderImageNavigation() {
    const isImage = imageFormats.has(state.selected?.format);
    const index = state.imageQueue.indexOf(state.selected?.id);
    for (const id of ['image-prev', 'image-next', 'image-position', 'image-organizer']) $(id).hidden = !isImage;
    $('image-prev').disabled = state.detailBusy || index <= 0;
    $('image-next').disabled = state.detailBusy || index < 0 || index >= state.imageQueue.length - 1;
    $('image-position').textContent = `第 ${index + 1} 张 / 共 ${state.imageQueue.length} 张`;
    $('edit-category').closest('.field').hidden = isImage;
}
async function navigateImage(step) {
    const index = state.imageQueue.indexOf(state.selected?.id);
    const id = state.imageQueue[index + step];
    if (index >= 0 && id) await openDetail(id, { keepQueue: true });
}
$('image-prev').onclick = () => navigateImage(-1);
$('image-next').onclick = () => navigateImage(1);
document.addEventListener('keydown', e => {
    if (!['ArrowLeft', 'ArrowRight'].includes(e.key) || e.altKey || e.ctrlKey || e.metaKey || !imageFormats.has(state.selected?.format)) return;
    if (!$('detail-dialog').open || [...document.querySelectorAll('dialog[open]')].some(d => d.id !== 'detail-dialog')) return;
    if (document.activeElement.closest('input, textarea, select, [contenteditable="true"]')) return;
    e.preventDefault(); navigateImage(e.key === 'ArrowLeft' ? -1 : 1);
});
$('quick-category').onchange = async () => {
    if (state.detailBusy) return;
    const detail = state.selected, previous = [...detail.categoryIds], categoryIds = chosenCategories($('quick-category'));
    state.detailBusy = true; setMetaDisabled(true); $('quick-category').disabled = true; renderImageNavigation();
    $('category-status').textContent = '正在保存…';
    try {
        await setImageCategory([detail.id], categoryIds);
        detail.categoryIds = categoryIds.length ? categoryIds : ['type-4']; setCategories($('edit-category'), detail.categoryIds); setCategories($('quick-category'), detail.categoryIds);
        if (state.metaBaseline) { const baseline = JSON.parse(state.metaBaseline); baseline.categoryIds = detail.categoryIds; state.metaBaseline = JSON.stringify(baseline); }
        await refresh(); $('category-status').textContent = '分类已保存';
    } catch (error) { setCategories($('quick-category'), previous); $('category-status').textContent = '保存失败，请重试'; toast(error.message, true); }
    finally { state.detailBusy = false; setMetaDisabled(false); $('quick-category').disabled = false; renderImageNavigation(); }
};
let leaveResolver = null;
function finishLeave(leave) {
    const resolve = leaveResolver; leaveResolver = null; $('unsaved-dialog').close(); resolve?.(leave);
}
async function allowDetailLeave() {
    if (state.detailBusy || leaveResolver) return false;
    if (!$('detail-dialog').open || !state.metaBaseline || state.metaBaseline === JSON.stringify(metaForm())) return true;
    $('unsaved-error').hidden = true; openDialog('unsaved-dialog');
    return new Promise(resolve => { leaveResolver = resolve; });
}
$('unsaved-discard').onclick = () => finishLeave(true);
$('unsaved-cancel').onclick = () => finishLeave(false);
$('unsaved-dialog').addEventListener('cancel', e => { e.preventDefault(); if (!state.detailBusy) finishLeave(false); });
$('unsaved-save').onclick = async () => {
    for (const id of ['unsaved-save', 'unsaved-discard', 'unsaved-cancel']) $(id).disabled = true;
    const saved = await saveMetadata();
    for (const id of ['unsaved-save', 'unsaved-discard', 'unsaved-cancel']) $(id).disabled = false;
    if (saved) finishLeave(true);
    else { $('unsaved-error').textContent = '保存失败，修改仍保留。请重试或取消。'; $('unsaved-error').hidden = false; }
};
function renderCategories() {
    $('categories').replaceChildren();
    for (const category of [{ id: 'all', name: '全部分类' }, ...(state.automaticCategories || []), ...state.categories]) {
        const row = node('div', 'category-row');
        const button = node('button', 'nav-item' + (state.category === category.id ? ' active' : ''));
        button.dataset.category = category.id;
        button.append(node('span', '', category.name), node('b', '', state.assets.filter(a => inScope(a) && inCategory(a, category.id)).length));
        row.append(button);
        if (category.id !== 'all' && !category.automatic) {
            const edit = node('button', 'category-edit', '✎'); edit.title = '重命名分类：' + category.name; edit.setAttribute('aria-label', edit.title);
            edit.onclick = () => editName('category', category); row.append(edit);
        }
        $('categories').append(row);
    }
    $('active-category').textContent = [...state.categories, ...(state.automaticCategories || [])].find(c => c.id === state.category)?.name || '全部分类';
}
let nameTask = null;
function editName(kind, item = null) {
    nameTask = { kind, item };
    const file = kind === 'file';
    const dot = file ? item.name.lastIndexOf('.') : -1;
    $('name-title').textContent = file ? '重命名文件' : item ? '重命名分类' : '新增分类';
    $('name-label').textContent = file ? '实际文件名' : '分类名称';
    $('name-input').maxLength = file ? 180 - (item.name.length - dot) : 32;
    $('name-input').value = file ? item.name.slice(0, dot) : item?.name || '';
    $('name-extension').textContent = file ? item.name.slice(dot) : '';
    $('name-help').textContent = file ? '只修改当前文件名，保持目录和扩展名。已设置的显示名称、分类、关联和版本不变。' : '单层分类只整理资源库记录，不改变原文件。';
    $('name-error').hidden = true; $('name-save').disabled = false;
    openDialog('name-dialog'); $('name-input').focus(); $('name-input').select();
}
$('add-category').onclick = () => editName('category');
$('rename-file').onclick = async () => { if (await allowDetailLeave()) editName('file', state.selected); };
$('name-form').onsubmit = async e => {
    e.preventDefault(); if ($('name-save').disabled) return;
    $('name-save').disabled = true; $('name-error').hidden = true;
    const { kind, item } = nameTask;
    try {
        if (kind === 'file') await api(`/api/assets/${item.id}/rename`, { method: 'POST', body: JSON.stringify({ stem: $('name-input').value }) });
        else {
            const result = await api('/api/categories' + (item ? '/' + item.id : ''), { method: item ? 'PATCH' : 'POST', body: JSON.stringify({ name: $('name-input').value }) });
            if (!item) { state.checked.clear(); state.category = result.id; }
        }
        await refresh();
        if (kind === 'file') await openDetail(item.id, { keepQueue: true, force: true });
        $('name-dialog').close(); toast(kind === 'file' ? '文件已重命名，关联与版本已保留' : '分类已保存');
    } catch (error) { $('name-error').textContent = error.message; $('name-error').hidden = false; }
    finally { $('name-save').disabled = false; }
};
function stopModels(container) { for (const model of container.querySelectorAll('model-viewer')) { model.pause(); model.removeAttribute('src'); } }
for (const el of document.querySelectorAll('[data-close]')) el.onclick = () => $(el.dataset.close).close();
async function closeDetail() { if (await allowDetailLeave()) $('detail-dialog').close(); }
document.querySelector('[data-close="detail-dialog"]').onclick = closeDetail;
$('detail-dialog').addEventListener('cancel', e => { e.preventDefault(); closeDetail(); });
$('detail-dialog').addEventListener('close', () => { state.detailRequest++; state.metaBaseline = null; state.imageQueue = []; stopModels($('viewer')); $('viewer').replaceChildren(); });
$('compare-dialog').addEventListener('close', () => { stopModels($('compare-content')); $('compare-content').replaceChildren(); });
$('import-dialog').addEventListener('cancel', e => { if (state.uploading) { e.preventDefault(); toast('请先等待上传完成，或取消当前上传'); } });
$('import-dialog').addEventListener('close', () => { if (state.parent && $('detail-dialog').open) openDetail(state.parent.id); });
document.querySelector('[data-close="import-dialog"]').onclick = () => { if (state.uploading) toast('请先等待上传完成，或取消当前上传'); else $('import-dialog').close(); };

function makeModel(asset, onLoad) {
    const model = document.createElement('model-viewer');
    model.setAttribute('camera-controls', ''); model.setAttribute('shadow-intensity', '0.7'); model.setAttribute('exposure', '0.8');
    model.setAttribute('camera-orbit', '145deg 65deg 115%');
    model.setAttribute('interaction-prompt', 'none'); model.setAttribute('loading', 'eager');
    model.setAttribute('alt', asset.title); model.setAttribute('src', fileURL(asset.id));
    model.addEventListener('load', () => onLoad?.(model));
    model.addEventListener('error', () => { toast('模型无法预览，请确认 GLB 内嵌资源且使用受支持的压缩格式', true); if (model.parentElement) model.replaceWith(node('div', 'viewer-message', '模型预览失败，可下载原文件检查。')); });
    return model;
}
async function savePoster(asset, model) {
    const original = state.assets.find(a => a.id === asset.id);
    if (original?.hasPoster) return;
    const blob = await model.toBlob({ mimeType: 'image/png', idealAspect: true });
    const response = await fetch(fileURL(asset.id, 'poster'), { method: 'POST', headers: { 'X-Library-Token': state.token, 'Content-Type': 'image/png' }, body: blob });
    if (!response.ok) throw Error('模型封面保存失败');
    if (original) original.hasPoster = true;
}
$('generate-posters').onclick = async () => {
    const queue = filtered().filter(a => a.format === 'glb' && !a.hasPoster);
    if (!queue.length) { toast('当前筛选中的模型封面已齐全'); return; }
    const button = $('generate-posters'); button.disabled = true;
    let finished = 0, failed = 0, unsupported = 0;
    try {
        await customElements.whenDefined('model-viewer');
        for (const asset of queue) {
            button.textContent = `生成封面 ${finished + failed + unsupported + 1} / ${queue.length}`;
            const detailResponse = await fetch(`/api/assets/${encodeURIComponent(asset.id)}`);
            if (!detailResponse.ok) { failed++; continue; }
            const detail = await detailResponse.json();
            if (detail.model?.external) { unsupported++; continue; }
            const model = document.createElement('model-viewer');
            model.setAttribute('camera-orbit', '145deg 65deg 115%'); model.setAttribute('exposure', '0.8');
            model.setAttribute('loading', 'eager'); model.setAttribute('interaction-prompt', 'none');
            model.style.cssText = 'position:fixed;left:0;bottom:0;width:400px;height:300px;opacity:0;pointer-events:none;z-index:-1';
            document.body.append(model);
            try {
                await new Promise((resolve, reject) => {
                    const timer = setTimeout(() => reject(Error('模型加载超时')), 25000);
                    model.addEventListener('load', () => { clearTimeout(timer); resolve(); }, { once: true });
                    model.addEventListener('error', () => { clearTimeout(timer); reject(Error('模型加载失败')); }, { once: true });
                    model.src = fileURL(asset.id);
                });
                await savePoster(asset, model); finished++;
            } catch { failed++; } finally { model.removeAttribute('src'); model.remove(); }
        }
        render(); toast(`已生成 ${finished} 张模型封面${unsupported ? `，${unsupported} 个外部资源模型需内嵌版本` : ''}${failed ? `，${failed} 个模型未能生成` : ''}`, failed > 0);
    } finally { button.disabled = false; button.textContent = '生成模型封面'; }
};
let resetImage = () => {};
function makeImage(asset, interactive = false) {
    const image = node('img'); image.src = fileURL(asset.id); image.alt = asset.title; image.draggable = false;
    image.onerror = () => image.replaceWith(node('div', 'viewer-message', '图片加载失败，请刷新索引或下载原文件检查。'));
    if (interactive) {
        let scale = 1, x = 0, y = 0, drag = null;
        const update = () => image.style.transform = `translate(${x}px,${y}px) scale(${scale})`;
        resetImage = () => { scale = 1; x = 0; y = 0; update(); };
        image.addEventListener('wheel', e => { e.preventDefault(); scale = Math.max(0.2, Math.min(8, scale * (e.deltaY > 0 ? 0.9 : 1.1))); update(); }, { passive: false });
        image.onpointerdown = e => { drag = { x: e.clientX - x, y: e.clientY - y }; image.setPointerCapture(e.pointerId); image.classList.add('dragging'); };
        image.onpointermove = e => { if (drag) { x = e.clientX - drag.x; y = e.clientY - drag.y; update(); } };
        const release = () => { drag = null; image.classList.remove('dragging'); };
        image.onpointerup = release; image.onpointercancel = release;
    }
    return image;
}
async function openDetail(id, { keepQueue = false, force = false } = {}) {
    if (!force && !(await allowDetailLeave())) return;
    const request = ++state.detailRequest;
    const basic = state.assets.find(a => a.id === id); if (!basic) return;
    if (!keepQueue) state.imageQueue = filtered().filter(a => imageFormats.has(a.format)).map(a => a.id);
    if (imageFormats.has(basic.format) && !state.imageQueue.includes(id)) state.imageQueue = [id];
    state.metaBaseline = null; setMetaDisabled(true); $('quick-category').disabled = true;
    state.selected = basic;
    renderImageNavigation(); $('category-status').textContent = '选择后自动保存';
    $('detail-dialog').scrollTop = 0;
    document.querySelector('.inspector').scrollTop = 0;
    $('detail-title').textContent = basic.title; $('detail-type').textContent = 'RESOURCE / ' + basic.format.toUpperCase();
    stopModels($('viewer')); $('viewer').replaceChildren(node('div', 'viewer-message', '正在读取资源…'));
    $('metadata').replaceChildren(); $('detail-path').value = ''; $('checksum').textContent = '';
    $('versions').replaceChildren(); $('related-list').replaceChildren(); $('animation-bar').hidden = true;
    $('save-meta').disabled = true; $('new-version').disabled = true;
    $('rename-file').disabled = true; $('actual-name').value = ''; $('file-access').textContent = ''; $('rename-reason').textContent = '';
    $('detail-recent').disabled = true;
    $('delete-file').disabled = true;
    $('delete-reason').textContent = '正在检查删除权限…';
    $('viewer-hint').textContent = '首次查看时计算文件校验值，原文件不会被修改。';
    openDialog('detail-dialog');
    try {
        const detail = await api('/api/assets/' + id);
        if (request !== state.detailRequest) return;
        state.selected = detail;
        $('detail-badges').replaceChildren(node('span', '', scopeLabels[detail.scope]), node('span', '', detail.format.toUpperCase()), node('span', '', 'v' + detail.version));
        const fields = [['文件大小', bytes(detail.size)], ['更新时间', date(detail.modified)]];
        if (detail.image) fields.push(['图片尺寸', `${detail.image.width} × ${detail.image.height}`]);
        if (detail.model) fields.push(['三角形 / 网格', `${detail.model.triangles.toLocaleString()} / ${detail.model.meshes}`], ['材质 / 动画', `${detail.model.materials} / ${detail.model.animations.length}`]);
        for (const [label, value] of fields) { const row = node('div'); row.append(node('dt', '', label), node('dd', '', value)); $('metadata').append(row); }
        $('detail-path').value = detail.absolutePath; $('checksum').textContent = detail.sha256;
        $('download').href = fileURL(id, 'download');
        $('edit-title').value = detail.customTitle; $('edit-title').placeholder = detail.title; $('edit-tags').value = detail.tags.join(', '); setCategories($('edit-category'), detail.categoryIds); $('edit-notes').value = detail.notes;
        setCategories($('quick-category'), detail.categoryIds); $('quick-category').disabled = false;
        $('actual-name').value = detail.name; $('file-access').textContent = scopeLabels[detail.access];
        $('rename-reason').textContent = detail.rename.reason; $('rename-file').disabled = !detail.rename.canRename;
        $('detail-recent').disabled = !imageFormats.has(detail.format);
        $('delete-file').disabled = !detail.deletion.canDelete; $('delete-file').title = detail.deletion.reason;
        $('delete-reason').textContent = detail.deletion.reason;
        if (detail.access === 'editable' && !detail.deletion.canDelete) $('file-access').textContent = '文件可改动 · 删除受保护';
        $('related-select').replaceChildren();
        for (const asset of state.assets.filter(a => a.id !== id).sort((a, b) => a.title.localeCompare(b.title, 'zh-CN'))) {
            const option = node('option', '', `[${asset.format}] ${asset.title}`); option.value = asset.id; option.selected = detail.relatedIds.includes(asset.id); $('related-select').append(option);
        }
        for (const version of detail.versions) {
            const button = node('button', 'version' + (version.id === id ? ' current' : ''), `v${version.version} · ${version.id === id ? '当前查看' : version.name}`);
            button.append(node('span', '', bytes(version.size))); button.onclick = () => openDetail(version.id); $('versions').append(button);
        }
        for (const related of detail.related) { const button = node('button', 'related-item', `${related.format.toUpperCase()} / ${related.title}`); button.onclick = () => openDetail(related.id); $('related-list').append(button); }
        if (!detail.related.length) $('related-list').append(node('p', 'muted', '尚未关联，可在上方选择对应的概念图、源文件或截图。'));
        setMetaDisabled(false); state.metaBaseline = JSON.stringify(metaForm()); $('new-version').disabled = false;
        $('viewer').replaceChildren();
        if (imageFormats.has(detail.format)) {
            $('viewer').append(makeImage(detail, true)); $('viewer-hint').textContent = '滚轮缩放 · 拖动平移 · 重置视图恢复全图。透明格仅用于查看，不会写入图片。';
        } else if (detail.format === 'glb' && !detail.model?.external) {
            const loading = node('span', 'model-loading', '正在加载 3D 模型…');
            const model = makeModel(detail, current => {
                if (request !== state.detailRequest) return;
                loading.remove(); $('animation-select').replaceChildren();
                for (const animation of current.availableAnimations) { const option = node('option', '', animation); option.value = animation; $('animation-select').append(option); }
                $('animation-bar').hidden = !current.availableAnimations.length;
                $('animation-speed').value = '1'; $('play-animation').textContent = '播放';
                if (current.availableAnimations.length) {
                    const initial = current.availableAnimations.find(name => /takeoff/i.test(name)) || current.availableAnimations[0];
                    current.animationName = initial; current.currentTime = 0; current.pause(); $('animation-select').value = initial;
                }
                savePoster(detail, current).then(render).catch(() => {});
            });
            $('viewer').append(model, loading); $('viewer-hint').textContent = '拖动旋转 · 滚轮缩放 · 右键平移。这里只播放 GLB 内置动画；Godot 程序步态、施工和实机光照请查看关联截图。';
        } else {
            const message = node('div', 'viewer-message'); message.append(node('strong', '', detail.format.toUpperCase()), node('p', '', detail.format === 'blend' ? 'Blender 制作源文件。浏览器不直接执行或渲染源文件，请关联导出的 GLB 与实机截图，或下载后在 Blender 中打开。' : detail.model?.external ? '此 GLB 引用了外部贴图或缓冲区，请使用内嵌资源版本。' : '该文件仅提供信息查看与下载。HTML 和脚本不会在资源库中执行。'));
            $('viewer').append(message); $('viewer-hint').textContent = '可在右侧管理备注、版本和关联资源。';
        }
    } catch (error) { if (request === state.detailRequest) { $('viewer').replaceChildren(node('div', 'viewer-message', error.message)); toast(error.message, true); } }
}
$('backgrounds').onclick = e => { const button = e.target.closest('[data-bg]'); if (!button) return; $('viewer').className = 'viewer ' + button.dataset.bg; for (const item of $('backgrounds').children) item.classList.toggle('active', item === button); };
$('reset-view').onclick = () => { resetImage(); const model = $('viewer').querySelector('model-viewer'); if (model) { model.cameraOrbit = '145deg 65deg 115%'; model.cameraTarget = 'auto auto auto'; model.fieldOfView = 'auto'; model.jumpCameraToGoal(); } };
$('play-animation').onclick = () => { const model = $('viewer').querySelector('model-viewer'); if (!model) return; if (model.paused) { model.play(); $('play-animation').textContent = '暂停'; } else { model.pause(); $('play-animation').textContent = '播放'; } };
$('animation-select').onchange = () => { const model = $('viewer').querySelector('model-viewer'); if (model) { model.animationName = $('animation-select').value; model.play(); $('play-animation').textContent = '暂停'; } };
$('animation-speed').onchange = () => { const model = $('viewer').querySelector('model-viewer'); if (model) model.timeScale = Number($('animation-speed').value); };
$('copy-path').onclick = async () => { try { await navigator.clipboard.writeText($('detail-path').value); toast('路径已复制'); } catch { $('detail-path').select(); toast('请按 Ctrl+C 复制选中的路径'); } };
async function saveMetadata() {
    if (state.detailBusy || !state.metaBaseline) return false;
    state.detailBusy = true; setMetaDisabled(true); $('quick-category').disabled = true; renderImageNavigation();
    try {
        const id = state.selected.id;
        await api('/api/assets/' + id, { method: 'PATCH', body: JSON.stringify(metaForm()) });
        await refresh(); await openDetail(id, { keepQueue: true, force: true }); toast('资源信息已保存，原文件未修改');
        return true;
    } catch (error) { toast(error.message, true); return false; }
    finally { state.detailBusy = false; setMetaDisabled(!state.metaBaseline); $('quick-category').disabled = !state.metaBaseline; renderImageNavigation(); }
}
$('save-meta').onclick = saveMetadata;
function showImport(parent = null) {
    state.parent = parent; $('upload-list').replaceChildren(); $('import-title').textContent = parent ? `导入新版本 · ${parent.title}` : '导入资源';
    setCategories($('import-category'), parent?.categoryIds || (['all', RECENT].includes(state.category) ? [] : [state.category])); $('import-category').disabled = !!parent;
    $('file-input').multiple = !parent; $('file-input').value = ''; openDialog('import-dialog');
}
$('import').onclick = () => showImport(); $('new-version').onclick = () => showImport(state.selected);
$('dropzone').onclick = () => { if (!state.uploading) $('file-input').click(); };
$('dropzone').onkeydown = e => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); $('dropzone').click(); } };
for (const event of ['dragenter', 'dragover']) $('dropzone').addEventListener(event, e => { e.preventDefault(); $('dropzone').classList.add('over'); });
for (const event of ['dragleave', 'drop']) $('dropzone').addEventListener(event, e => { e.preventDefault(); $('dropzone').classList.remove('over'); });
$('dropzone').addEventListener('drop', e => uploadFiles([...e.dataTransfer.files]));
$('file-input').onchange = () => uploadFiles([...$('file-input').files]);
$('cancel-upload').onclick = () => { state.cancelled = true; state.xhr?.abort(); };
async function uploadFiles(files) {
    if (state.uploading || !files.length) return;
    if (state.parent && files.length !== 1) { toast('每次只能为一个资源导入一个新版本', true); return; }
    state.uploading = true; state.cancelled = false; $('cancel-upload').hidden = false;
    const importCategories = chosenCategories($('import-category')); $('import-category').disabled = true;
    let succeeded = 0;
    try {
        for (const file of files) {
            if (state.cancelled) break;
            const row = node('div', 'upload-row', file.name); const progress = node('progress'); progress.max = 100; progress.value = 0; const status = node('small', '', '准备上传…'); row.append(progress, status); $('upload-list').append(row);
            try {
                if (file.size > 512 * 1024 * 1024) throw Error('单文件最大 512 MB');
                await new Promise((resolve, reject) => {
                    const xhr = new XMLHttpRequest(); state.xhr = xhr;
                    xhr.open('POST', '/api/import' + (state.parent ? '?parent=' + encodeURIComponent(state.parent.id) : importCategories.length ? '?' + new URLSearchParams(importCategories.map(id => ['categoryIds', id])).toString() : ''));
                    xhr.setRequestHeader('X-Library-Token', state.token); xhr.setRequestHeader('X-File-Name', encodeURIComponent(file.name)); xhr.setRequestHeader('Content-Type', 'application/octet-stream');
                    xhr.upload.onprogress = e => { if (e.lengthComputable) { progress.value = Math.round(e.loaded / e.total * 100); status.textContent = progress.value === 100 ? '正在校验并保存…' : `上传中 ${progress.value}%`; } };
                    xhr.onerror = () => reject(Error('上传连接中断，请重试')); xhr.onabort = () => reject(Error('上传已取消'));
                    xhr.onload = () => { let result; try { result = JSON.parse(xhr.responseText); } catch { reject(Error('服务器响应异常')); return; } if (xhr.status < 200 || xhr.status >= 300) reject(Error(result.error || '上传失败')); else resolve(result); };
                    xhr.send(file);
                });
                progress.value = 100; status.textContent = '已导入 · 原文件未覆盖'; succeeded++;
            } catch (error) { row.classList.add('failed'); status.textContent = error.message; }
        }
    } finally { state.uploading = false; state.xhr = null; $('cancel-upload').hidden = true; $('import-category').disabled = !!state.parent; await refresh(); if (succeeded) toast(`已导入 ${succeeded} 个资源`); }
}
$('compare-open').onclick = () => {
    if (state.checked.size !== 2) return;
    $('compare-content').replaceChildren();
    for (const id of state.checked) {
        const asset = state.assets.find(a => a.id === id); if (!asset) continue;
        const side = node('section', 'compare-side'); const view = node('div', 'compare-view checker');
        view.append(asset.format === 'glb' ? makeModel(asset) : imageFormats.has(asset.format) ? makeImage(asset) : fallback(asset));
        side.append(node('h3', '', `${asset.title} · v${asset.version}`), view); $('compare-content').append(side);
    }
    openDialog('compare-dialog');
};
$('scope-nav').onclick = e => { const button = e.target.closest('[data-scope]'); if (!button) return; state.checked.clear(); state.scope = button.dataset.scope; state.limit = 48; for (const b of $('scope-nav').children) b.classList.toggle('active', b === button); $('page-title').replaceChildren(document.createTextNode(scopeLabels[state.scope]), node('span', 'title-dot', '.')); render(); };
$('categories').onclick = e => { const button = e.target.closest('[data-category]'); if (!button) return; state.checked.clear(); state.category = button.dataset.category; state.limit = 48; render(); };
for (const id of ['search', 'format', 'sort']) $(id).addEventListener(id === 'search' ? 'input' : 'change', () => { state.checked.clear(); state.limit = 48; render(); });
$('more').onclick = () => { state.limit += 48; render(); };
$('rescan').onclick = async () => { $('rescan').disabled = true; try { const result = await api('/api/rescan', { method: 'POST' }); await refresh({ resetRecent: true }); toast(`索引已更新，共 ${result.count} 个资源`); } catch (error) { toast(error.message, true); } finally { $('rescan').disabled = false; } };
document.addEventListener('keydown', e => { if (e.key === '/' && !document.querySelector('dialog[open]') && !['INPUT', 'TEXTAREA', 'SELECT'].includes(document.activeElement.tagName)) { e.preventDefault(); $('search').focus(); } });
await refresh();
