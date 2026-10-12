import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { createLibrary } from './server.mjs';
import { recycleFiles } from './deletion.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const local = path.join(root, '.local');
const mode = process.argv[2];
const patterns = [
    [/^art-library\/library-(overview|models|barracks|mobile|rename)\.png$/, 'tools/art_library/test.mjs (historical output)'],
    [/^heavy-soldier-(before|after|curve|front|highland|quarry|return|turn-stop)-\d{3}\.png$/, 'tests/previews/soldier_motion_preview.gd'],
    [/^soldier-heading-(highland|quarry)-(ramp|turn)-v1\.png$/, 'tests/helpers/soldier_heading_checks.gd'],
    [/^highland-edge-(arrived|approach)\.png$/, 'tests/previews/arrival_preview.gd'],
    [/^ramp-boundary-(default|far|highland|quarry)-(before|after)-v2\.png$/, 'tests/previews/terrain_sample_view.gd'],
    [/^sample-(cliff|gameplay|highland|materials|menu|overview|quarry)-v1\.png$/, 'tests/previews/terrain_sample_view.gd'],
    [/^desert-quarry-(overview|highland|pit|gameplay)\.png$/, 'tests/visual/terrain_presentation.gd'],
    [/^barracks-v4-game-(desert_quarry|desert_sample|prototype)-(airborne(-red)?|deploy-blocked|deploy-valid|landed(-red)?)\.png$/, 'tests/visual/barracks_integration.gd'],
    [/^barracks-v4-godot-(landed|transition|airborne)\.png$/, 'tests/previews/barracks_underbody_preview.gd'],
    [/^兵营模型-轻度写实-Godot(近景|俯视|荒漠俯视|升级前)-v3\.png$/, 'tests/previews/barracks_realistic_preview.gd'],
    [/^兵营模型-方案一-荒漠实机-v1\.png$/, 'tests/previews/barracks_preview.gd'],
    [/^base_animation\/((build|scan)-\d{2}|red)\.png$/, 'tests/previews/base_preview.gd'],
    [/^cursor_runtime\/(cursor-assets|destination-(\d{3}|camera))\.png$/, 'tests/previews/cursor_preview.gd'],
    [/^barracks_rts\/(lod[012]-blue|damaged-blocked|airborne-(blue|red)|chassis-underside-lod[012]|silhouette-(64|128|256)-red|comparison-(baseline|near|medium|far))\.png$/, 'tests/visual/barracks_rts.gd'],
    [/^barracks_weathering\/(before|after|compare)-(airborne-(blue|red)|close-blue|far-blue|medium-blue|normal-(blue|red))\.png$/, 'tests/visual/barracks_weathering.gd']
];

async function history() {
    const app = await createLibrary({ port: 0 });
    try {
        const catalog = await (await fetch(app.url + '/api/catalog')).json();
        const candidates = catalog.assets.flatMap(a => {
            const relative = a.relativePath.replace(/^assets\/concept_art\//, '');
            const rule = patterns.find(([pattern]) => pattern.test(relative));
            return rule ? [{ id: a.id, name: a.name, relativePath: a.relativePath, evidence: rule[1] }] : [];
        });
        if (!candidates.length) { console.log('No historical verification screenshots remain eligible for review.'); return; }
        const headers = { 'X-Library-Token': catalog.token, 'Content-Type': 'application/json' };
        const previewResponse = await fetch(app.url + '/api/deletions/preview', { method: 'POST', headers, body: JSON.stringify({ ids: candidates.map(c => c.id) }) });
        const preview = await previewResponse.json(); if (!previewResponse.ok) throw Error(preview.error);
        const report = { createdAt: new Date().toISOString(), candidates, preview };
        await fs.writeFile(path.join(local, 'verification-history-cleanup.json'), JSON.stringify(report, null, 2));
        console.log(`HISTORY_CANDIDATES ${candidates.length} allowed=${preview.entries.filter(e => e.allowed).length} bytes=${preview.bytes}`);
        for (const entry of preview.entries.filter(e => !e.allowed)) console.log(`SKIP ${entry.name}: ${entry.reason}`);
        if (mode === 'cleanup-history') {
            const response = await fetch(app.url + '/api/deletions/execute', { method: 'POST', headers, body: JSON.stringify({ ticket: preview.ticket }) });
            const result = await response.json(); if (!response.ok) throw Error(result.error);
            report.result = result; await fs.writeFile(path.join(local, 'verification-history-cleanup.json'), JSON.stringify(report, null, 2));
            console.log(`HISTORY_CLEANUP removed=${result.results.filter(r => r.status === 'deleted').length} failed=${result.results.filter(r => r.status === 'failed').length} skipped=${result.results.filter(r => r.status === 'skipped').length}`);
            if (result.results.some(r => r.status === 'failed' || r.status === 'removed')) throw Error('Some recycle operations need review; see cleanup report.');
        }
    } finally { await app.close(); }
}

async function cleanupReviewed() {
    const last = JSON.parse(await fs.readFile(path.join(local, 'art-library-last-verification.json')));
    const manifestPath = path.resolve(process.argv[3] || last.manifest);
    if (!manifestPath.startsWith(local + path.sep + 'art-library-test-') || path.basename(manifestPath) !== 'screenshots.json') throw Error('Invalid verification manifest');
    const manifest = JSON.parse(await fs.readFile(manifestPath));
    const allowedRoot = await fs.realpath(path.join(root, 'assets/concept_art/_verification'));
    const items = [];
    for (const entry of manifest.files) {
        try {
            const real = await fs.realpath(entry.path), stat = await fs.lstat(entry.path);
            if (!real.startsWith(allowedRoot + path.sep) || !stat.isFile() || stat.isSymbolicLink() || !real.endsWith('.png')) throw Error('Verification path is not a regular temporary screenshot');
            const actual = createHash('sha256').update(await fs.readFile(real)).digest('hex');
            if (actual !== entry.sha256) throw Error('Verification screenshot changed since test: ' + real);
            items.push({ id: String(items.length), path: real, sha256: actual });
        } catch (error) { if (error.code !== 'ENOENT') throw error; }
    }
    const results = items.length ? await recycleFiles(items) : [];
    manifest.reviewed = true; manifest.cleanedAt = new Date().toISOString(); manifest.results = results;
    await fs.writeFile(manifestPath, JSON.stringify(manifest, null, 2));
    console.log(`VERIFICATION_CLEANUP recycled=${results.filter(r => r.success).length} failed=${results.filter(r => !r.success).length}`);
    if (results.some(r => !r.success)) throw Error(JSON.stringify(results.filter(r => !r.success)));
}
try {
    if (mode === 'inventory-history' || mode === 'cleanup-history') await history();
    else if (mode === 'cleanup-reviewed') await cleanupReviewed();
    else throw Error('Unknown maintenance action');
} catch (error) { console.error(error); process.exitCode = 1; }
