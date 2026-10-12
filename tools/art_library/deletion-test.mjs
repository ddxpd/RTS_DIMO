import fs from 'node:fs/promises';
import path from 'node:path';
import { createHash, randomUUID } from 'node:crypto';
import { createLibrary } from './server.mjs';
import { recycleFiles } from './deletion.mjs';

export async function testDeletion(parent, png, check) {
    const root = path.join(parent, 'deletion'), concept = path.join(root, 'assets/concept_art');
    const bin = path.join(root, '.local/test-bin');
    for (const dir of [concept, bin, path.join(root, 'assets/models'), path.join(concept, '_verification')]) await fs.mkdir(dir, { recursive: true });
    for (const name of ['single.png', 'batch.png', 'fail.png', 'changed.png', 'group.png', 'partial.png', 'referenced.png', 'race.png']) await fs.writeFile(path.join(concept, name), png);
    for (const name of ['group.png', 'partial.png', 'fail.png', 'race.png']) {
        await fs.writeFile(path.join(concept, name + '.import'), 'import metadata');
        await fs.writeFile(path.join(concept, name + '.uid'), 'uid metadata');
    }
    await fs.mkdir(path.join(root, 'scripts'), { recursive: true });
    await fs.writeFile(path.join(root, 'scripts/reference.gd'), 'preload("res://assets/concept_art/referenced.png")');
    await fs.writeFile(path.join(root, 'assets/models/protected.png'), png);
    await fs.writeFile(path.join(concept, '_verification/hidden.png'), png);
    let app, token;
    const fakeRecycle = async files => {
        const results = [];
        for (const file of files) {
            if (file.path.endsWith('fail.png') || file.path.endsWith('partial.png.import')) results.push({ id: file.id, success: false, error: 'simulated locked file' });
            else { await fs.rename(file.path, path.join(bin, file.id)); results.push({ id: file.id, success: true }); }
        }
        return results;
    };
    const api = async (url, method = 'GET', body) => {
        const response = await fetch(app.url + url, { method, headers: { 'X-Library-Token': token || '', 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
        return { status: response.status, data: await response.json() };
    };
    async function start() { app = await createLibrary({ projectRoot: root, port: 0, recycle: fakeRecycle }); const r = await api('/api/catalog'); token = r.data.token; return r.data; }
    const preview = async ids => (await api('/api/deletions/preview', 'POST', { ids })).data;
    const execute = ticket => api('/api/deletions/execute', 'POST', { ticket });
    try {
        let catalog = await start(); const asset = name => catalog.assets.find(a => a.name === name);
        const single = asset('single.png'), batch = asset('batch.png'), failing = asset('fail.png'), protectedFile = asset('protected.png'), changed = asset('changed.png');
        check(!asset('hidden.png'), 'temporary verification screenshots are not indexed');
        check((await api('/api/deletions/preview', 'POST', { ids: [] })).status === 400, 'empty deletion rejected');
        check((await api('/api/deletions/preview', 'POST', { ids: Array(1001).fill(single.id) })).status === 400, 'oversized deletion rejected');
        const grouped = asset('group.png');
        const detail = (await api('/api/assets/' + grouped.id)).data;
        check(detail.deletion.canDelete && !detail.rename.canRename, 'sidecars allow delete while rename remains protected');
        check(!(await preview([asset('referenced.png').id])).entries[0].allowed, 'project references protect concept resource');
        const groupPreview = await preview([grouped.id]);
        check(groupPreview.entries[0].files.length === 3 && groupPreview.bytes > png.length, 'group preview lists original and both sidecars with total bytes');
        const groupResult = (await execute(groupPreview.ticket)).data.results[0];
        check(groupResult.status === 'deleted' && groupResult.files.every(f => f.status === 'deleted'), 'complete group recycled together');
        const partialGroup = (await execute((await preview([asset('partial.png').id])).ticket)).data.results[0];
        check(partialGroup.status === 'partial' && partialGroup.files[0].status === 'deleted' && partialGroup.files[1].status === 'failed' && partialGroup.files[2].status === 'deleted', 'sidecar failure reports partial group without hiding remaining path');
        check(await fs.readFile(path.join(concept, 'partial.png.import'), 'utf8') === 'import metadata', 'failed companion stays intact');
        const race = asset('race.png'), racePreview = await preview([race.id]);
        await fs.writeFile(path.join(concept, 'race.png.uid'), 'changed');
        check((await execute(racePreview.ticket)).data.results[0].status === 'failed' && (await fs.readFile(path.join(concept, 'race.png'))).equals(png), 'changed companion prevents whole group deletion');
        const referenceRace = await preview([race.id]);
        await fs.writeFile(path.join(root, 'scripts/late.gd'), 'preload("res://assets/concept_art/race.png")');
        check((await execute(referenceRace.ticket)).data.results[0].status === 'failed', 'new reference after preview prevents deletion');
        const prep = await preview([single.id, protectedFile.id, single.id, '../escape']);
        check(prep.entries.length === 3 && prep.entries.filter(e => e.allowed).length === 1 && prep.entries[0].path.endsWith('single.png'), 'deletion preview deduplicates, reports protected and unknown IDs with actual path');
        const versionResponse = await fetch(app.url + '/api/import?parent=' + single.id, { method: 'POST', headers: { 'X-Library-Token': token, 'X-File-Name': 'child.png' }, body: png });
        const version = await versionResponse.json();
        await api('/api/assets/' + batch.id, 'PATCH', { title: '关联保留', categoryId: batch.categoryId, notes: '', tags: [], relatedIds: [single.id] });
        const result = await execute(prep.ticket);
        check(result.data.results.filter(e => e.status === 'deleted').length === 1 && (await api('/api/assets/' + single.id)).status === 404 && (await api('/api/assets/' + version.id)).status === 200, 'single delete removes actual file and only selected version');
        check((await execute(prep.ticket)).status === 409, 'same deletion ticket cannot execute twice');
        check((await api('/api/assets/' + batch.id)).data.related.length === 0, 'deleted associations hidden from live detail');
        await api('/api/assets/' + batch.id, 'PATCH', { title: '删除后更新备注', categoryId: batch.categoryId, notes: '后续修改', tags: [], relatedIds: [] });
        const pendingChanged = await preview([changed.id]);
        await fs.writeFile(path.join(concept, 'changed.png'), 'replaced after confirmation');
        check((await execute(pendingChanged.ticket)).data.results[0].status === 'failed', 'changed file rejected after confirmation');
        const partial = await execute((await preview([batch.id, failing.id])).ticket);
        check(partial.data.results.some(r => r.status === 'deleted') && partial.data.results.some(r => r.status === 'failed') && (await fs.readFile(path.join(concept, 'fail.png'))).equals(png), 'batch partial failure retains failed file');
        check(await fs.readFile(path.join(concept, 'fail.png.import'), 'utf8') === 'import metadata' && partial.data.results.find(r => r.id === failing.id).files.slice(1).every(f => f.status === 'skipped'), 'failed original keeps every companion');
        await app.close(); app = null; await start();
        check((await api('/api/assets/' + single.id)).status === 404, 'deleted state survives restart');
        // Restore bytes to original path, equivalent to a Windows Recycle Bin restore.
        await fs.rename(path.join(bin, single.id), path.join(concept, 'single.png'));
        await fs.rename(path.join(bin, batch.id), path.join(concept, 'batch.png'));
        await api('/api/rescan', 'POST');
        const restored = (await api('/api/assets/' + single.id)).data;
        check(restored.firstSeenAt === single.firstSeenAt && restored.categoryIds.join() === single.categoryIds.join(), 'restoration preserves first-seen clock and categories');
        check(restored.id === single.id && restored.versions.length === 2 && (await api('/api/assets/' + batch.id)).data.related[0].id === single.id, 'restored original path and checksum recover identity, versions and relations');
        // Simulate a process stop after recycle but before final metadata save.
        await app.close(); app = null;
        const stateFile = path.join(root, '.local/art-library/catalog.json');
        const state = JSON.parse(await fs.readFile(stateFile));
        state.deleted[single.id] = { source: 'project', relativePath: single.relativePath, status: 'pending', sha256: createHash('sha256').update(png).digest('hex') };
        await fs.rename(path.join(concept, 'single.png'), path.join(bin, single.id)); await fs.writeFile(stateFile, JSON.stringify(state));
        await start();
        check((await api('/api/assets/' + single.id)).status === 404, 'interrupted recycle reconciles missing file without deleting again');
        await fs.writeFile(path.join(concept, 'single.png'), 'different content'); await api('/api/rescan', 'POST');
        check((await api('/api/assets/' + single.id)).status === 404, 'wrong-content restore never inherits old identity');
        await fs.writeFile(path.join(concept, 'single.png'), png); await api('/api/rescan', 'POST');
        check((await api('/api/assets/' + single.id)).status === 200, 'matching restored content reactivates resource');
        // This dedicated disposable file exercises the real Windows implementation.
        const realFile = path.join(concept, 'recycle-test-' + randomUUID() + '.txt');
        const content = Buffer.from('Disposable Windows recycle verification'); await fs.writeFile(realFile, content);
        const realResult = await recycleFiles([{ id: 'real-bin-test', path: realFile, sha256: createHash('sha256').update(content).digest('hex') }]);
        check(realResult[0].success, 'real Windows recycle succeeds: ' + (realResult[0].error || ''));
        let gone = false; try { await fs.stat(realFile); } catch (error) { gone = error.code === 'ENOENT'; }
        check(gone, 'real recycled fixture is absent from its original path');
    } finally { await app?.close(); }
}
