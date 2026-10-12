import fs from 'node:fs/promises';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { createLibrary } from './server.mjs';
import { createRenamer } from './management.mjs';

export async function testManagement(parent, png, check) {
    const root = path.join(parent, 'management');
    const concept = path.join(root, 'assets/concept_art');
    const dataRoot = path.join(root, '.local/art-library');
    for (const dir of [concept, dataRoot, path.join(root, 'assets/models/source'), path.join(root, 'scripts')]) await fs.mkdir(dir, { recursive: true });
    const relative = 'assets/concept_art/original.png';
    const id = createHash('sha256').update('project:' + relative).digest('hex').slice(0, 24);
    await fs.writeFile(path.join(root, relative), png);
    await fs.writeFile(path.join(root, 'assets/models/runtime.png'), png);
    await fs.writeFile(path.join(root, 'assets/models/source/model.blend'), 'BLENDER-v300fixture');
    await fs.writeFile(path.join(concept, '制作源.blend'), 'BLENDER-v300fixture');
    const legacy = { schema: 1, imports: [], fingerprints: {}, metadata: { [id]: { title: '旧显示名称', category: '建筑', tags: ['保留'], notes: '迁移记录', relatedIds: [] } } };
    const stateFile = path.join(dataRoot, 'catalog.json');
    await fs.writeFile(stateFile, JSON.stringify(legacy));
    let app;
    let token;
    async function request(route, method = 'GET', body) {
        const response = await fetch(app.url + route, { method, headers: { 'X-Library-Token': token || '', 'Content-Type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body) });
        return { status: response.status, data: await response.json() };
    }
    async function start() { app = await createLibrary({ projectRoot: root, port: 0 }); const result = await request('/api/catalog'); token = result.data.token; return result.data; }
    const rename = (assetId, stem) => request(`/api/assets/${assetId}/rename`, 'POST', { stem });
    const rescan = () => request('/api/rescan', 'POST');
    try {
        let catalog = await start();
        check(catalog.assets.find(a => a.id === id).customTitle === '旧显示名称' && catalog.categories.length === 5, 'schema1 migrates metadata and built-in categories without changing ID');
        const backups = (await fs.readdir(dataRoot)).filter(n => n.includes('.schema1-') && n.endsWith('.bak'));
        check(backups.length === 1 && JSON.stringify(JSON.parse(await fs.readFile(path.join(dataRoot, backups[0])))) === JSON.stringify(legacy), 'migration preserves exact legacy backup data');
        const created = await request('/api/categories', 'POST', { name: '  待修改  ' });
        const categoryId = created.data.id;
        check(created.status === 201 && created.data.name === '待修改', 'create trimmed custom category');
        check((await request('/api/categories', 'POST', { name: '待修改' })).status === 409, 'duplicate category rejected');
        check((await request('/api/categories', 'POST', { name: '  ' })).status === 400 && (await request('/api/categories', 'POST', { name: '长'.repeat(33) })).status === 400, 'blank and long categories rejected');
        await request('/api/categories/type-0', 'PATCH', { name: '建筑设计' });
        check((await request('/api/assets/' + id)).data.category === '建筑设计', 'renaming built-in category preserves assignments');
        const meta = { title: '独立显示名', categoryId, tags: ['定稿'], notes: '不变', relatedIds: [] };
        await request('/api/assets/' + id, 'PATCH', meta);
        await request(`/api/categories/${categoryId}`, 'PATCH', { name: '已定稿' });
        check((await request('/api/assets/' + id)).data.category === '已定稿', 'custom category rename follows stable category ID');
        const runtime = catalog.assets.find(a => a.scope === 'runtime');
        check((await rename(runtime.id, '不可改')).status === 403 && (await rename(catalog.assets.find(a => a.format === 'blend').id, '不可改')).status === 403, 'server blocks runtime and source file rename');
        check(catalog.assets.find(a => a.name === '制作源.blend').access === 'readonly', 'source file inside concept directory stays protected');
        check((await request('/api/assets/' + runtime.id, 'PATCH', { ...meta, relatedIds: [id] })).status === 200, 'readonly-original resources still allow metadata editing');
        await fs.writeFile(path.join(concept, 'original.png.import'), 'fixture');
        check((await rename(id, '不能改')).status === 403, 'Godot import sidecar blocks rename');
        await fs.unlink(path.join(concept, 'original.png.import'));
        await fs.writeFile(path.join(concept, 'original.png.uid'), 'fixture');
        check((await rename(id, '不能改')).status === 403, 'Godot UID sidecar blocks rename');
        await fs.unlink(path.join(concept, 'original.png.uid'));
        await fs.writeFile(path.join(root, 'scripts/reference.gd'), 'var p = "res://assets/concept_art/original.png"');
        const referenced = await rename(id, '不能改');
        check(referenced.status === 403 && referenced.data.error.includes('scripts/reference.gd'), 'explicit game reference blocks rename with location');
        await fs.unlink(path.join(root, 'scripts/reference.gd'));
        for (const bad of ['../bad', 'CON', 'bad.', 'bad ', '.hidden', 'a:b', '']) check((await rename(id, bad)).status === 400, 'invalid rename rejected: ' + JSON.stringify(bad));
        await fs.writeFile(path.join(concept, 'collision.png'), png);
        check((await rename(id, 'COLLISION')).status === 409, 'case-insensitive filename conflict rejected without overwrite');
        const headers = { 'X-Library-Token': token, 'X-File-Name': encodeURIComponent('新版本.png') };
        const upload = await fetch(app.url + '/api/import?parent=' + id, { method: 'POST', headers, body: png });
        const imported = await upload.json();
        check(upload.status === 201 && imported.categoryId === categoryId, 'new version inherits custom category');
        const newImport = await fetch(app.url + '/api/import?categoryId=' + categoryId, { method: 'POST', headers, body: png });
        check(newImport.status === 201 && (await newImport.json()).categoryId === categoryId, 'new import accepts selected category');
        const before = (await request('/api/assets/' + id)).data;
        await fetch(app.url + `/api/assets/${id}/thumb`);
        const renamed = await rename(id, '兵营完成图');
        check(renamed.status === 200 && renamed.data.id === id && renamed.data.title === '独立显示名' && renamed.data.sha256 === before.sha256 && renamed.data.versions.length === 2 && renamed.data.categoryId === categoryId, 'Chinese rename preserves content, custom title, category, ID and versions');
        check((await request('/api/assets/' + runtime.id)).data.related[0].id === id && (await fetch(app.url + `/api/assets/${id}/thumb`)).ok, 'relations and thumbnail remain available after rename');
        const download = await fetch(app.url + `/api/assets/${id}/download`);
        check(decodeURIComponent(download.headers.get('content-disposition')).includes('兵营完成图.png') && Buffer.from(await download.arrayBuffer()).equals(png), 'download uses new name and unchanged bytes');
        check((await rename(imported.id, 'Version')).status === 200 && (await rename(imported.id, 'version')).status === 200, 'imported file rename and case-only rename work');
        await fs.writeFile(path.join(concept, 'auto.png'), png); await rescan();
        catalog = (await request('/api/catalog')).data;
        const automatic = catalog.assets.find(a => a.name === 'auto.png');
        check((await rename(automatic.id, '自动名称')).data.title === '自动名称', 'default display title follows filename');
        await fs.writeFile(path.join(root, relative), png); await rescan();
        check((await request('/api/catalog')).data.assets.find(a => a.name === 'original.png').id !== id, 'reusing old path does not steal renamed resource ID');
        await app.close(); app = null; catalog = await start();
        check(catalog.categories.some(c => c.id === categoryId && c.name === '已定稿') && catalog.assets.find(a => a.id === id).name === '兵营完成图.png', 'categories and renamed ID survive restart and rescan');
        check((await request('/api/assets/' + imported.id)).data.groupId === id, 'version parent and group survive restart');
        await app.close(); app = null;

        // Exercise failure recovery with real files and an injected metadata-save error.
        const state = JSON.parse(await fs.readFile(stateFile));
        const asset = catalog.assets.find(a => a.id === id);
        const file = path.join(root, asset.relativePath);
        const beforeState = JSON.stringify(state);
        let saves = 0;
        const renamer = createRenamer({ state, stateFile, projectRoot: root, importRoot: path.join(dataRoot, 'imports'), dataRoot,
            atomic: async (p, value) => fs.writeFile(p, JSON.stringify(value)), save: async () => { if (++saves === 2) throw Error('injected save failure'); },
            safeFile: async () => file, scan: async () => {}, get: () => asset });
        let failed = false;
        try { await renamer.rename({ ...asset, file }, '失败恢复'); } catch (e) { failed = e.message === 'injected save failure'; }
        check(failed && (await fs.readFile(file)).equals(png) && JSON.stringify(state) === beforeState, 'failed index save rolls filename and state back');
        const foreign = Buffer.from('concurrently created destination');
        let firstSave = true;
        const racer = createRenamer({ state, stateFile, projectRoot: root, importRoot: path.join(dataRoot, 'imports'), dataRoot,
            atomic: async (p, value) => fs.writeFile(p, JSON.stringify(value)), save: async () => { if (firstSave) { firstSave = false; await fs.writeFile(path.join(concept, '竞态目标.png'), foreign); } },
            safeFile: async () => file, scan: async () => {}, get: () => asset });
        let conflict = false;
        try { await racer.rename({ ...asset, file }, '竞态目标'); } catch (e) { conflict = e.status === 409; }
        check(conflict && (await fs.readFile(file)).equals(png) && (await fs.readFile(path.join(concept, '竞态目标.png'))).equals(foreign), 'destination appearing during rename is preserved and original restored');
        await fs.unlink(path.join(concept, '竞态目标.png'));

        // Simulate a crash after the file move, before and after index commit.
        for (const committed of [false, true]) {
            const oldName = path.basename(file), newName = '恢复目标.png', tempName = '.rename-recovery';
            const target = path.join(concept, newName);
            const stat = await fs.lstat(file, { bigint: true });
            await fs.link(file, target); await fs.unlink(file);
            const newRelative = 'assets/concept_art/' + newName;
            if (committed) { delete state.projectIds[asset.relativePath]; state.projectIds[newRelative] = id; await fs.writeFile(stateFile, JSON.stringify(state)); }
            await fs.writeFile(path.join(dataRoot, 'rename-pending.json'), JSON.stringify({ id, source: 'project', directory: concept, oldName, newName, tempName, oldRelative: asset.relativePath, newRelative, identity: `${stat.dev}:${stat.ino}` }));
            catalog = await start();
            const expected = committed ? newName : oldName;
            check(catalog.assets.find(a => a.id === id).name === expected && (await fs.readFile(path.join(concept, expected))).equals(png), `startup recovers ${committed ? 'committed' : 'uncommitted'} file rename`);
            await app.close(); app = null;
        }
    } finally { await app?.close(); }
}
