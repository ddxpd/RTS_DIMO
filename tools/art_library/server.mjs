import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createReadStream, createWriteStream } from 'node:fs';
import fs from 'node:fs/promises';
import { createHash, randomUUID, randomBytes, timingSafeEqual } from 'node:crypto';
import { pipeline } from 'node:stream/promises';
import { Transform } from 'node:stream';
import sharp from 'sharp';
import { migrateCatalog, categoryName, renamePermission, createRenamer, validFilename } from './management.mjs';
import { createDeletion } from './deletion.mjs';
import { RECENT_CATEGORY, isRecent, readCategoryIds, combineCategories } from './categories.mjs';
import { migrateProjectPaths } from './project-layout.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const defaultRoot = path.resolve(here, '../..');
const formats = new Set(['png', 'jpg', 'jpeg', 'webp', 'gif', 'svg', 'glb', 'blend', 'txt', 'json', 'html', 'tres', 'gdshader']);
const images = new Set(['png', 'jpg', 'jpeg', 'webp', 'gif', 'svg']);
const types = { png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg', webp: 'image/webp', gif: 'image/gif', svg: 'image/svg+xml', glb: 'model/gltf-binary' };
const hash = value => createHash('sha256').update(value).digest('hex');
const failure = (status, message) => Object.assign(new Error(message), { status });
const within = (root, value) => value === root || value.startsWith(root + path.sep);
const categoryOf = name => /cursor|ui[\/]|command|光标/i.test(name) ? '界面' : /barracks|兵营|base|基地|bunker|地堡|refinery|矿场/i.test(name) ? '建筑' : /soldier|士兵|harvester|矿车|bullet/i.test(name) ? '单位' : /terrain|地形|desert|quarry|sample|ramp|ore|rock|maps[\/]/i.test(name) ? '地形' : '其他';

async function exists(file) { try { await fs.access(file); return true; } catch { return false; } }
async function atomic(file, value) {
    const temp = file + '.' + randomUUID() + '.tmp';
    await fs.writeFile(temp, JSON.stringify(value, null, 2), { flag: 'wx' });
    await fs.rename(temp, file);
}
async function checksum(file) {
    const digest = createHash('sha256');
    for await (const chunk of createReadStream(file)) digest.update(chunk);
    return digest.digest('hex');
}

// Read only the JSON chunk. Embedded geometry/texture buffers stay on disk.
async function glbInfo(file) {
    const handle = await fs.open(file, 'r');
    try {
        const head = Buffer.alloc(20);
        await handle.read(head, 0, 20, 0);
        const size = (await handle.stat()).size;
        if (head.toString('ascii', 0, 4) !== 'glTF' || head.readUInt32LE(4) !== 2 || head.readUInt32LE(8) !== size || head.readUInt32LE(16) !== 0x4E4F534A) throw failure(400, '不是有效的 GLB 2.0 文件');
        const length = head.readUInt32LE(12);
        if (length > 16 * 1024 * 1024 || length + 20 > size) throw failure(400, 'GLB 索引过大或不完整');
        const json = Buffer.alloc(length);
        await handle.read(json, 0, length, 20);
        const doc = JSON.parse(json.toString('utf8').trim());
        const external = [...(doc.buffers || []), ...(doc.images || [])].some(x => x.uri && !x.uri.startsWith('data:'));
        let triangles = 0;
        for (const mesh of doc.meshes || []) for (const p of mesh.primitives || []) {
            const count = doc.accessors?.[p.indices ?? p.attributes?.POSITION]?.count || 0;
            if ((p.mode ?? 4) === 4) triangles += Math.floor(count / 3);
            else if ([5, 6].includes(p.mode)) triangles += Math.max(0, count - 2);
        }
        return { triangles, meshes: doc.meshes?.length || 0, materials: doc.materials?.length || 0,
            animations: (doc.animations || []).map((a, i) => a.name || `动画 ${i + 1}`), external };
    } finally { await handle.close(); }
}

export async function createLibrary({ projectRoot = defaultRoot, dataRoot = path.join(projectRoot, '.local/art-library'), port = 8810, maxUpload = 512 * 1024 * 1024, recycle, now = Date.now } = {}) {
    projectRoot = await fs.realpath(projectRoot);
    await fs.mkdir(dataRoot, { recursive: true });
    dataRoot = await fs.realpath(dataRoot);
    const assetRoot = path.join(projectRoot, 'assets');
    const stateFile = path.join(dataRoot, 'catalog.json');
    const cacheRoot = path.join(dataRoot, 'cache');
    const importRoot = path.join(dataRoot, 'imports');
    const tempRoot = path.join(dataRoot, 'incoming');
    for (const dir of [cacheRoot, importRoot, tempRoot]) await fs.mkdir(dir, { recursive: true });
    // Fail loudly on corrupt metadata; never silently replace a user's catalogue.
    const state = await exists(stateFile) ? JSON.parse(await fs.readFile(stateFile, 'utf8')) : { schema: 1, metadata: {}, imports: [], fingerprints: {} };
    await migrateCatalog(state, stateFile, atomic);
    const layoutFile = path.join(projectRoot, 'tools/codex/structure-migration.json');
    if (await exists(layoutFile)) {
        migrateProjectPaths(state, JSON.parse(await fs.readFile(layoutFile, 'utf8')).paths);
    }
    let records = new Map();
    let saving = Promise.resolve();
    let scanning = null;
    let importing = false;
    const save = () => { const copy = structuredClone(state); saving = saving.catch(() => {}).then(() => atomic(stateFile, copy)); return saving; };
    const token = randomBytes(32).toString('hex');
    const thumbs = new Map();
    const category = id => state.categories.find(c => c.id === id);
    const fallbackCategory = name => `type-${['建筑', '单位', '地形', '界面', '其他'].indexOf(categoryOf(name))}`;
    const renamer = createRenamer({ state, stateFile, projectRoot, importRoot, dataRoot, atomic, save, safeFile, scan, get: id => get(id) });
    await renamer.recover();
    const deletion = createDeletion({ state, projectRoot, dataRoot, safeFile, checksum, save, get: id => get(id), recycle });

    async function safeFile(record) {
        const root = record.source === 'project' ? assetRoot : importRoot;
        const realRoot = await fs.realpath(root);
        const real = await fs.realpath(record.file).catch(() => { throw failure(404, '文件已移动，请刷新资源索引'); });
        if (!within(realRoot, real)) throw failure(403, '不允许访问资源目录以外的文件');
        return real;
    }
    async function scan() {
        if (scanning) return scanning;
        scanning = (async () => {
            await deletion.reconcile();
            const next = new Map();
            async function add(file, source, imported) {
                const stat = await fs.lstat(file);
                if (!stat.isFile() || stat.isSymbolicLink()) return;
                const format = path.extname(file).slice(1).toLowerCase();
                if (!formats.has(format)) return;
                const relativePath = path.relative(source === 'project' ? projectRoot : dataRoot, file).replaceAll('\\', '/');
                let id = imported?.id || state.projectIds[relativePath];
                if (!id) {
                    const legacyId = hash('project:' + relativePath).slice(0, 24);
                    id = Object.values(state.projectIds).includes(legacyId) ? randomUUID() : legacyId;
                    state.projectIds[relativePath] = id;
                }
                if (state.deleted[id]) return;
                const scope = source === 'library' ? 'imported' : format === 'blend' || relativePath.includes('/source/') ? 'source' : relativePath.startsWith('assets/concept_art/') ? 'concept' : 'runtime';
                const metadata = state.metadata[id] ||= {};
                metadata.categoryIds ||= [fallbackCategory(relativePath)];
                const categoryIds = combineCategories([], metadata.categoryIds.filter(id => category(id)));
                metadata.categoryIds = categoryIds;
                if (!Object.hasOwn(state.firstSeenAt, id)) state.firstSeenAt[id] = imported?.importedAt || new Date(now()).toISOString();
                const categoryId = categoryIds[0];
                const access = ['concept', 'imported'].includes(scope) ? 'editable' : 'readonly';
                const hasPoster = format === 'glb' && await exists(path.join(cacheRoot, hash(id + stat.size + ':' + stat.mtimeMs) + '-model.webp'));
                next.set(id, { id, file, source, relativePath, name: path.basename(file), format, scope, size: stat.size, modified: stat.mtimeMs, hasPoster,
                    groupId: imported?.groupId || id, version: imported?.version || 1, importedAt: imported?.importedAt,
                    access, capabilities: { editMetadata: true, renameFile: access === 'editable', deleteFile: access === 'editable' },
                    customTitle: metadata.title || '', title: metadata.title || path.basename(file, path.extname(file)), categoryIds, categoryId, category: category(categoryId).name, firstSeenAt: state.firstSeenAt[id],
                    tags: metadata.tags || [], notes: metadata.notes || '', relatedIds: metadata.relatedIds || [], parentId: imported?.parentId || null });
            }
            async function walk(dir) {
                for (const entry of await fs.readdir(dir, { withFileTypes: true })) {
                    if (entry.isSymbolicLink() || entry.name.startsWith('.') || entry.name === '_verification') continue;
                    const file = path.join(dir, entry.name);
                    if (entry.isDirectory()) await walk(file);
                    else if (formats.has(path.extname(file).slice(1).toLowerCase())) await add(file, 'project');
                }
            }
            if (await exists(assetRoot)) await walk(assetRoot);
            for (const item of state.imports) {
                const file = path.resolve(importRoot, item.file);
                if (within(importRoot, file) && await exists(file)) await add(file, 'library', item);
            }
            records = next;
            await save();
            return records;
        })().finally(() => { scanning = null; });
        return scanning;
    }
    const publicRecord = (r, at = now()) => { const { file, ...publicData } = r; return { ...publicData, isRecent: isRecent(r.firstSeenAt, at) }; };
    const get = id => { const record = records.get(id); if (!record) throw failure(404, '资源不存在，请刷新索引'); return record; };

    async function details(record) {
        const file = await safeFile(record);
        const stat = await fs.stat(file);
        const stamp = `${stat.size}:${stat.mtimeMs}`;
        let fingerprint = state.fingerprints[record.id];
        if (!fingerprint || fingerprint.stamp !== stamp) {
            fingerprint = { stamp, sha256: await checksum(file), inspectedAt: new Date().toISOString() };
            if (record.format === 'glb') fingerprint.model = await glbInfo(file);
            else if (images.has(record.format)) {
                try { const meta = await sharp(file, { limitInputPixels: 64000000 }).metadata(); fingerprint.image = { width: meta.width, height: meta.height, pages: meta.pages || 1 }; }
                catch { fingerprint.previewError = '图片无法解码或超过 6400 万像素，仅支持下载原文件'; }
            }
            state.fingerprints[record.id] = fingerprint;
            await save();
        }
        return { ...publicRecord(record), ...fingerprint, absolutePath: file, rename: await renamePermission(record, projectRoot), deletion: await deletion.permission(record),
            versions: [...records.values()].filter(x => x.groupId === record.groupId).sort((a, b) => b.version - a.version).map(record => publicRecord(record)),
            related: record.relatedIds.filter(id => records.has(id)).map(id => publicRecord(get(id))) };
    }
    async function thumbnail(record) {
        const file = await safeFile(record);
        const stat = await fs.stat(file);
        const key = hash(record.id + stat.size + ':' + stat.mtimeMs);
        if (record.format === 'glb') {
            const poster = path.join(cacheRoot, key + '-model.webp');
            if (!await exists(poster)) throw failure(404, '尚未生成模型缩略图');
            return poster;
        }
        if (!images.has(record.format)) throw failure(404, '此格式没有图片缩略图');
        const destination = path.join(cacheRoot, key + '-v2.webp');
        if (!await exists(destination)) {
            if (!thumbs.has(key)) thumbs.set(key, (async () => {
                const data = await sharp(file, { limitInputPixels: 64000000, animated: false, density: record.format === 'svg' ? 384 : 72 }).rotate().resize(480, 360, { fit: 'inside', withoutEnlargement: true }).webp({ quality: 82 }).toBuffer();
                await fs.writeFile(destination, data);
            })().finally(() => thumbs.delete(key)));
            await thumbs.get(key);
        }
        return destination;
    }

    async function jsonBody(req, max = 65536) {
        const chunks = []; let size = 0;
        for await (const part of req) { size += part.length; if (size > max) throw failure(413, '请求过大'); chunks.push(part); }
        try { return JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch { throw failure(400, 'JSON 格式错误'); }
    }
    async function upload(req, url) {
        let name;
        try { name = decodeURIComponent(req.headers['x-file-name'] || ''); } catch { throw failure(400, '文件名编码错误'); }
        if (!validFilename(name)) throw failure(400, '文件名无效');
        const format = path.extname(name).slice(1).toLowerCase();
        if (!formats.has(format)) throw failure(415, '不支持此文件格式');
        if (Number(req.headers['content-length']) > maxUpload) throw failure(413, '单文件最大 512 MB');
        const parent = url.searchParams.has('parent') ? get(url.searchParams.get('parent')) : null;
        const requestedCategories = url.searchParams.has('categoryIds') ? { categoryIds: url.searchParams.getAll('categoryIds') } : url.searchParams.has('categoryId') ? { categoryId: url.searchParams.get('categoryId') } : null;
        const categoryIds = parent?.categoryIds || (requestedCategories ? combineCategories([], readCategoryIds(requestedCategories, state.categories)) : null);
        if (categoryIds && categoryIds.some(id => !category(id))) throw failure(400, '分类不存在，请刷新页面');
        if (parent && parent.format !== format && !(['jpg', 'jpeg'].includes(parent.format) && ['jpg', 'jpeg'].includes(format))) throw failure(400, '新版本须与原资源格式一致');
        const id = randomUUID();
        const temp = path.join(tempRoot, id + '.' + format);
        let size = 0;
        const digest = createHash('sha256');
        try {
            const limiter = new Transform({ transform(chunk, encoding, callback) {
                size += chunk.length;
                if (size > maxUpload) return callback(failure(413, '单文件超出大小限制'));
                digest.update(chunk); callback(null, chunk);
            } });
            await pipeline(req, limiter, createWriteStream(temp, { flags: 'wx' }));
            if (!size) throw failure(400, '文件为空');
            if (format === 'glb') { const info = await glbInfo(temp); if (info.external) throw failure(400, '请上传内嵌贴图和缓冲区的 GLB'); }
            if (images.has(format)) { try { await sharp(temp, { limitInputPixels: 64000000 }).metadata(); } catch { throw failure(400, '图片无效或尺寸过大'); } }
            if (format === 'blend') {
                const f = await fs.open(temp); const magic = Buffer.alloc(7);
                try { await f.read(magic, 0, 7, 0); } finally { await f.close(); }
                if (magic.toString() !== 'BLENDER') throw failure(400, '请上传未压缩的 Blender 源文件');
            }
            const groupId = parent?.groupId || id;
            const version = Math.max(0, ...state.imports.filter(x => x.groupId === groupId).map(x => x.version), parent?.version || 0) + 1;
            const folder = path.join(importRoot, id);
            await fs.mkdir(folder);
            await fs.rename(temp, path.join(folder, name));
            const item = { id, groupId, version, parentId: parent?.id || null, file: `${id}/${name}`, importedAt: new Date(now()).toISOString(), sha256: digest.digest('hex') };
            state.imports.push(item);
            if (parent) state.metadata[id] = { title: parent.customTitle, categoryIds: [...parent.categoryIds], tags: [...parent.tags], relatedIds: [...parent.relatedIds] };
            else if (categoryIds) state.metadata[id] = { categoryIds };
            await save();
            await scan();
            return publicRecord(get(id));
        } finally { await fs.rm(temp, { force: true }); }
    }
    async function sendFile(req, res, file, mime, downloadName) {
        const stat = await fs.stat(file);
        res.setHeader('Content-Type', mime);
        res.setHeader('Accept-Ranges', 'bytes');
        if (downloadName) res.setHeader('Content-Disposition', `attachment; filename*=UTF-8''${encodeURIComponent(downloadName)}`);
        let start = 0, end = stat.size - 1;
        if (req.headers.range) {
            const match = /^bytes=(\d*)-(\d*)$/.exec(req.headers.range);
            if (!match || !stat.size || (!match[1] && !match[2])) throw failure(416, '无效的文件范围');
            if (!match[1]) start = Math.max(0, stat.size - Number(match[2]));
            else { start = Number(match[1]); if (match[2]) end = Math.min(end, Number(match[2])); }
            if (start > end || start >= stat.size) { res.setHeader('Content-Range', `bytes */${stat.size}`); throw failure(416, '无效的文件范围'); }
            res.statusCode = 206; res.setHeader('Content-Range', `bytes ${start}-${end}/${stat.size}`);
        }
        res.setHeader('Content-Length', Math.max(0, end - start + 1));
        if (req.method === 'HEAD' || !stat.size) { res.end(); return; }
        await pipeline(createReadStream(file, { start, end }), res);
    }

    await scan();
    // A personal library serializes API operations, including scans and metadata
    // reads which may persist fingerprints, so a rename cannot race a state save.
    let operations = Promise.resolve();
    const server = http.createServer(async (req, res) => {
        let release;
        res.setHeader('X-Content-Type-Options', 'nosniff');
        res.setHeader('Referrer-Policy', 'no-referrer');
        res.setHeader('Cache-Control', 'no-store');
        res.setHeader('Content-Security-Policy', "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; connect-src 'self' blob: data:; worker-src 'self' blob:; object-src 'none'; frame-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'");
        const reply = (status, value) => { res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' }); res.end(JSON.stringify(value)); };
        try {
            const actualPort = server.address().port;
            const host = req.headers.host;
            if (![ `127.0.0.1:${actualPort}`, `localhost:${actualPort}` ].includes(host)) throw failure(403, '仅允许本机访问');
            if (req.headers['sec-fetch-site'] === 'cross-site') throw failure(403, '禁止跨站访问');
            const url = new URL(req.url, `http://${host}`);
            if (!['GET', 'HEAD', 'POST', 'PATCH'].includes(req.method)) throw failure(405, '不支持此操作');
            if (['POST', 'PATCH'].includes(req.method)) {
                if (req.headers.origin && req.headers.origin !== `http://${host}`) throw failure(403, '禁止跨站修改');
                const supplied = Buffer.from(String(req.headers['x-library-token'] || ''));
                const expected = Buffer.from(token);
                if (supplied.length !== expected.length || !timingSafeEqual(supplied, expected)) throw failure(403, '页面会话已失效，请刷新页面');
            }
            if (url.pathname.startsWith('/api/')) {
                const previous = operations;
                operations = new Promise(resolve => { release = resolve; });
                await previous;
                if (req.destroyed) return;
            }
            if (url.pathname === '/api/catalog' && req.method === 'GET') {
                const at = now();
                return reply(200, { assets: [...records.values()].map(record => publicRecord(record, at)), categories: state.categories, automaticCategories: [RECENT_CATEGORY], evaluatedAt: new Date(at).toISOString(), localOnly: true, maxUpload, token });
            }
            if (url.pathname === '/api/deletions/preview' && req.method === 'POST') return reply(200, await deletion.preview((await jsonBody(req)).ids));
            if (url.pathname === '/api/deletions/execute' && req.method === 'POST') {
                const result = await deletion.execute((await jsonBody(req)).ticket);
                await scan(); return reply(200, result);
            }
            if (url.pathname === '/api/assets/category' && req.method === 'POST') {
                const body = await jsonBody(req);
                if (!Array.isArray(body.ids) || !body.ids.length || body.ids.length > 1000 || body.ids.some(id => typeof id !== 'string')) throw failure(400, '请选择图片和有效分类（最多 1000 张）');
                const categoryIds = readCategoryIds(body, state.categories);
                const mode = body.mode || (body.categoryIds !== undefined ? 'add' : 'replace');
                if (!['add', 'remove', 'replace'].includes(mode)) throw failure(400, '请选择追加、移除或替换分类');
                const selected = [...new Set(body.ids)].map(get);
                if (selected.some(record => !images.has(record.format))) throw failure(400, '此操作仅支持图片');
                // Validate the entire selection before changing metadata; save once.
                for (const record of selected) await safeFile(record);
                const before = state.metadata;
                state.metadata = { ...before };
                for (const record of selected) state.metadata[record.id] = { ...before[record.id], categoryIds: combineCategories(record.categoryIds, categoryIds, mode) };
                try { await save(); } catch (error) { state.metadata = before; throw error; }
                for (const record of selected) { record.categoryIds = state.metadata[record.id].categoryIds; record.categoryId = record.categoryIds[0]; record.category = category(record.categoryId).name; }
                return reply(200, { ids: selected.map(record => record.id), categoryIds, mode });
            }
            const categoryRoute = /^\/api\/categories(?:\/([\w-]+))?$/.exec(url.pathname);
            if (categoryRoute && ((!categoryRoute[1] && req.method === 'POST') || (categoryRoute[1] && req.method === 'PATCH'))) {
                const body = await jsonBody(req);
                const existing = categoryRoute[1] ? category(categoryRoute[1]) : null;
                if (categoryRoute[1] && !existing) throw failure(404, '分类不存在');
                const name = categoryName(body.name, [...state.categories, RECENT_CATEGORY], existing?.id);
                const before = structuredClone(state.categories);
                const item = existing || { id: randomUUID(), name };
                if (existing) existing.name = name; else state.categories.push(item);
                try { await save(); } catch (error) { state.categories = before; throw error; }
                await scan(); return reply(existing ? 200 : 201, item);
            }
            if (url.pathname === '/api/rescan' && req.method === 'POST') { await scan(); return reply(200, { count: records.size }); }
            if (url.pathname === '/api/import' && req.method === 'POST') {
                if (importing) throw failure(409, '正在保存另一个文件，请稍后重试');
                importing = true;
                try { return reply(201, await upload(req, url)); } finally { importing = false; }
            }
            const route = /^\/api\/assets\/([\w-]+)(?:\/(file|thumb|download|poster|rename))?$/.exec(url.pathname);
            if (route) {
                const record = get(route[1]);
                if (route[2] === 'rename' && req.method === 'POST') {
                    const body = await jsonBody(req);
                    return reply(200, await details(await renamer.rename(record, body.stem)));
                }
                if (route[2] === 'poster' && req.method === 'POST') {
                    if (record.format !== 'glb') throw failure(400, '仅模型可保存预览封面');
                    const chunks = []; let size = 0;
                    for await (const part of req) { size += part.length; if (size > 2 * 1024 * 1024) throw failure(413, '封面过大'); chunks.push(part); }
                    const stat = await fs.stat(await safeFile(record));
                    const key = hash(record.id + stat.size + ':' + stat.mtimeMs);
                    const poster = await sharp(Buffer.concat(chunks), { limitInputPixels: 4000000 }).resize(480, 360, { fit: 'inside' }).webp({ quality: 82 }).toBuffer();
                    await fs.writeFile(path.join(cacheRoot, key + '-model.webp'), poster);
                    record.hasPoster = true;
                    return reply(200, { saved: true });
                }
                if (!route[2] && req.method === 'GET') return reply(200, await details(record));
                if (!route[2] && req.method === 'PATCH') {
                    const body = await jsonBody(req);
                    const categoryIds = combineCategories([], readCategoryIds(body, state.categories));
                    if (typeof body.title !== 'string' || body.title.length > 120 || typeof body.notes !== 'string' || body.notes.length > 4000 || !Array.isArray(body.tags) || body.tags.length > 20 || body.tags.some(x => typeof x !== 'string' || x.length > 32) || !Array.isArray(body.relatedIds) || body.relatedIds.length > 30 || body.relatedIds.some(id => !records.has(id) || id === record.id)) throw failure(400, '资源信息格式不正确');
                    const before = state.metadata[record.id];
                    const archivedRelated = (before?.relatedIds || []).filter(id => state.deleted[id]);
                    state.metadata[record.id] = { title: body.title.trim(), notes: body.notes, tags: [...new Set(body.tags)], categoryIds, relatedIds: [...new Set([...body.relatedIds, ...archivedRelated])] };
                    try { await save(); } catch (error) { state.metadata[record.id] = before; throw error; }
                    await scan(); return reply(200, await details(get(record.id)));
                }
                if (['file', 'thumb', 'download'].includes(route[2]) && ['GET', 'HEAD'].includes(req.method)) {
                    if (route[2] === 'thumb') return await sendFile(req, res, await thumbnail(record), 'image/webp');
                    const inline = route[2] === 'file' && (images.has(record.format) || record.format === 'glb');
                    if (inline && record.format === 'glb' && (await details(record)).model?.external) throw failure(400, '模型引用外部文件，请先导出为内嵌资源的 GLB');
                    return await sendFile(req, res, await safeFile(record), types[record.format] || 'application/octet-stream', inline ? null : record.name);
                }
            }
            if (['GET', 'HEAD'].includes(req.method)) {
                if (url.pathname === '/management.css') return await sendFile(req, res, path.join(here, 'public/management.css'), 'text/css');
                const staticFiles = { '/': ['public/index.html', 'text/html; charset=utf-8'], '/app.js': ['public/app.js', 'text/javascript'], '/style.css': ['public/style.css', 'text/css'], '/model-viewer.js': ['node_modules/@google/model-viewer/dist/model-viewer.min.js', 'text/javascript'] };
                const item = staticFiles[url.pathname];
                if (item) return await sendFile(req, res, path.join(here, item[0]), item[1]);
                if (url.pathname === '/favicon.ico') { res.writeHead(204); return res.end(); }
            }
            throw failure(404, '页面不存在');
        } catch (error) {
            if (res.headersSent || res.destroyed) { res.destroy(); return; }
            if (!error.status) console.error(error);
            reply(error.status || 500, { error: error.status ? error.message : '操作失败，请检查文件是否存在及服务日志' });
        } finally { release?.(); }
    });
    server.requestTimeout = 10 * 60 * 1000;
    await new Promise((resolve, reject) => { server.once('error', reject); server.listen(port, '127.0.0.1', resolve); });
    return { server, url: `http://127.0.0.1:${server.address().port}`, close: async () => { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); await operations; await saving; } };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
    createLibrary().then(app => {
        console.log(`ART_LIBRARY_READY ${app.url}`);
        for (const signal of ['SIGINT', 'SIGTERM']) process.once(signal, async () => { await app.close(); process.exit(0); });
    }).catch(error => { console.error(error); process.exitCode = 1; });
}
