import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';
import { spawn } from 'node:child_process';
import { scanProjectReferences } from './management.mjs';

const fail = (status, message) => Object.assign(new Error(message), { status });
export function recycleFiles(files) {
    if (process.platform !== 'win32') throw fail(503, '此功能需要 Windows 回收站；不会永久删除文件');
    const wrapper = fileURLToPath(new URL('../codex/recycle-art-files.ps1', import.meta.url));
    return new Promise((resolve, reject) => {
        const child = spawn(path.join(process.env.SystemRoot || 'C:\\Windows', 'System32/WindowsPowerShell/v1.0/powershell.exe'), ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', wrapper], { windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
        let output = '', errors = '';
        child.stdout.setEncoding('utf8'); child.stderr.setEncoding('utf8');
        child.stdout.on('data', chunk => { output += chunk; }); child.stderr.on('data', chunk => { errors += chunk; });
        child.on('error', reject); child.stdin.on('error', () => {});
        child.on('close', code => {
            if (code !== 0) return reject(Error('Windows 回收站调用失败：' + errors.slice(-1000)));
            try { resolve(JSON.parse(output.trim()).results); } catch { reject(Error('回收站响应无效：' + errors.slice(-500))); }
        });
        child.stdin.end(JSON.stringify({ files }));
    });
}

export function createDeletion({ state, projectRoot, dataRoot, safeFile, checksum, save, get, recycle = recycleFiles }) {
    state.deleted ||= {};
    const tickets = new Map();
    async function member(record, file, suffix = '') {
        const stat = await fs.lstat(file);
        const real = await safeFile({ ...record, file });
        const allowed = await fs.realpath(record.source === 'project' ? path.join(projectRoot, 'assets/concept_art') : path.join(dataRoot, 'imports'));
        const relative = path.relative(allowed, real);
        if (!stat.isFile() || stat.isSymbolicLink() || relative.startsWith('..') || path.isAbsolute(relative)) throw Error('文件不在允许回收的普通资源范围内');
        return { id: record.id + suffix, path: real, name: path.basename(file), size: stat.size };
    }
    async function permission(record, findReferences) {
        if (!['concept', 'imported'].includes(record.scope)) return { canDelete: false, reason: '原文件仅查看；正式资源和制作源文件不可删除。' };
        const files = [await member(record, record.file)];
        if (record.source === 'project') {
            for (const suffix of ['.import', '.uid']) {
                try { files.push(await member(record, record.file + suffix, suffix)); }
                catch (error) { if (error.code !== 'ENOENT') throw error; }
            }
            const lookup = findReferences || await scanProjectReferences(projectRoot);
            const referencedBy = [...new Set(files.flatMap(file => lookup(path.relative(projectRoot, file.path).replaceAll('\\', '/'))))];
            if (referencedBy.length) return { canDelete: false, reason: '文件被项目引用：' + referencedBy.join('、'), referencedBy };
        }
        return { canDelete: true, reason: files.length > 1 ? '原文件及同名导入伴随文件一起移入 Windows 回收站。' : '移入 Windows 回收站，只处理当前文件或版本。', files };
    }
    async function preview(ids) {
        if (!Array.isArray(ids) || !ids.length || ids.length > 1000 || ids.some(id => typeof id !== 'string')) throw fail(400, '请选择 1–1000 个资源');
        const entries = [];
        const findReferences = await scanProjectReferences(projectRoot);
        for (const id of new Set(ids)) {
            try {
                const record = get(id), policy = await permission(record, findReferences);
                const entry = { id, name: record.name, path: record.file, size: record.size, allowed: policy.canDelete, reason: policy.reason };
                if (entry.allowed) {
                    entry.files = await Promise.all(policy.files.map(async file => ({ ...file, sha256: await checksum(file.path) })));
                    entry.path = entry.files[0].path; entry.sha256 = entry.files[0].sha256;
                    entry.totalSize = entry.files.reduce((sum, file) => sum + file.size, 0);
                }
                entries.push(entry);
            } catch (error) { entries.push({ id, name: id, size: 0, allowed: false, reason: state.deleted[id] ? '文件已移除，刷新索引后重试' : error.message }); }
        }
        for (const [id, ticket] of tickets) if (ticket.expires < Date.now()) tickets.delete(id);
        if (tickets.size >= 100) tickets.delete(tickets.keys().next().value);
        const ticket = randomUUID(); tickets.set(ticket, { entries, expires: Date.now() + 10 * 60 * 1000 });
        return { ticket, entries, bytes: entries.filter(e => e.allowed).reduce((n, e) => n + e.totalSize, 0) };
    }
    async function execute(ticketId) {
        const ticket = tickets.get(ticketId);
        if (!ticket || ticket.expires < Date.now()) throw fail(409, '删除确认已过期或已执行，请重新选择');
        tickets.delete(ticketId);
        const results = [], ready = [];
        const findReferences = await scanProjectReferences(projectRoot);
        for (const entry of ticket.entries) {
            if (!entry.allowed) { results.push({ ...entry, status: 'skipped' }); continue; }
            try {
                const record = get(entry.id), policy = await permission(record, findReferences);
                if (!policy.canDelete) throw Error(policy.reason);
                if (policy.files.length !== entry.files.length) throw Error('伴随文件在确认后发生变化，请重新检查');
                for (let i = 0; i < entry.files.length; i++) {
                    if (policy.files[i].path !== entry.files[i].path || await checksum(policy.files[i].path) !== entry.files[i].sha256) throw Error('文件在确认后发生变化，请重新检查');
                }
                ready.push(entry);
            } catch (error) { results.push({ ...entry, status: 'failed', reason: error.message }); }
        }
        const before = structuredClone(state.deleted);
        for (const entry of ready) {
            const record = get(entry.id);
            state.deleted[entry.id] = { status: 'pending', source: record.source, relativePath: record.relativePath, sha256: entry.sha256, size: entry.size, requestedAt: new Date().toISOString() };
        }
        try { await save(); } catch (error) { state.deleted = before; throw error; }
        async function recycleChecked(files) {
            let replies;
            try { replies = files.length ? await recycle(files) : []; }
            catch (error) { replies = files.map(e => ({ id: e.id, success: false, error: error.message })); }
            return Promise.all(files.map(async file => {
                const reply = replies.find(r => r.id === file.id);
                let missing = false;
                try { await fs.lstat(file.path); } catch (error) { if (error.code === 'ENOENT') missing = true; else throw error; }
                return { ...file, status: missing ? (reply?.success ? 'deleted' : 'removed') : 'failed', reason: missing ? (reply?.success ? '已移入 Windows 回收站' : '原文件已移除；请检查系统回收站') : (reply?.error || '文件仍在原位置，未完成回收') };
            }));
        }
        // Never remove sidecars while the original is still in place.
        const originals = await recycleChecked(ready.map(entry => entry.files[0]));
        const companions = await recycleChecked(ready.filter(entry => originals.find(r => r.id === entry.id).status !== 'failed').flatMap(entry => entry.files.slice(1)));
        for (const entry of ready) {
            const original = originals.find(r => r.id === entry.id);
            if (original.status !== 'failed') {
                const files = [original, ...companions.filter(file => entry.files.some(e => e.id === file.id))];
                const partial = files.some(file => file.status === 'failed');
                state.deleted[entry.id].status = 'deleted';
                state.deleted[entry.id].deletedAt = new Date().toISOString();
                state.deleted[entry.id].files = files;
                results.push({ ...entry, files, status: partial ? 'partial' : files.some(file => file.status === 'removed') ? 'removed' : 'deleted', reason: partial ? '原文件已回收，但部分伴随文件仍在原位置；请查看下方路径。' : original.reason });
            } else {
                delete state.deleted[entry.id];
                results.push({ ...entry, files: [original, ...entry.files.slice(1).map(file => ({ ...file, status: 'skipped', reason: '原文件未回收，伴随文件保留' }))], status: 'failed', reason: original.reason });
            }
        }
        await save();
        return { results };
    }
    // A restore must match both the original path and bytes. Tombstones retain
    // metadata, version numbers and associations; visible lists use live records.
    async function reconcile() {
        for (const [id, item] of Object.entries(state.deleted)) {
            const root = item.source === 'project' ? projectRoot : dataRoot;
            const file = path.resolve(root, item.relativePath);
            const allowed = item.source === 'project' ? path.join(projectRoot, 'assets/concept_art') : path.join(dataRoot, 'imports');
            if (!file.startsWith(allowed + path.sep)) throw Error('删除恢复记录路径越界');
            try {
                const stat = await fs.lstat(file);
                const real = await fs.realpath(file);
                if (!stat.isFile() || stat.isSymbolicLink() || !real.startsWith(allowed + path.sep)) continue;
                if (await checksum(real) === item.sha256) delete state.deleted[id];
                else item.status = 'conflict';
            } catch (error) { if (error.code !== 'ENOENT') throw error; item.status = 'deleted'; }
        }
    }
    return { permission, preview, execute, reconcile };
}
