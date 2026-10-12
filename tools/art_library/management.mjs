import fs from 'node:fs/promises';
import path from 'node:path';
import { randomUUID } from 'node:crypto';

const fail = (status, message) => Object.assign(new Error(message), { status });
const defaults = ['建筑', '单位', '地形', '界面', '其他'];
export const defaultCategories = () => defaults.map((name, i) => ({ id: `type-${i}`, name }));
export function validFilename(name) {
    return typeof name === 'string' && name.length > 0 && name.length <= 180
        && !/[\\/:*?"<>|\x00-\x1f]/.test(name) && !name.startsWith('.') && !/[. ]$/.test(name)
        && !/^(con|prn|aux|nul|com[0-9¹²³]|lpt[0-9¹²³])(\.|$)/i.test(name);
}
export function categoryName(value, categories, exceptId) {
    const name = typeof value === 'string' ? value.trim() : '';
    if (!name || [...name].length > 32 || /[\x00-\x1f]/.test(name)) throw fail(400, '分类名称须为 1–32 个字符');
    if (categories.some(c => c.id !== exceptId && c.name.normalize('NFKC').toLowerCase() === name.normalize('NFKC').toLowerCase())) throw fail(409, '已存在同名分类');
    return name;
}
export async function migrateCatalog(state, stateFile, atomic) {
    if (![1, 2, 3].includes(state.schema) || !state.metadata || !Array.isArray(state.imports) || !state.fingerprints) throw Error('资源库元数据格式错误，请从备份恢复 catalog.json');
    if (state.schema === 1) {
        try { await fs.copyFile(stateFile, stateFile + '.schema1-' + randomUUID() + '.bak'); }
        catch (error) { if (error.code !== 'ENOENT') throw error; }
        state.categories = defaultCategories();
        state.projectIds = {};
        for (const meta of Object.values(state.metadata)) {
            let category = state.categories.find(c => c.name === meta.category);
            if (!category && meta.category) { category = { id: randomUUID(), name: meta.category }; state.categories.push(category); }
            if (category) meta.categoryId = category.id;
            delete meta.category;
        }
        state.schema = 2;
        await atomic(stateFile, state);
    }
    if (state.schema === 2) {
        try { await fs.copyFile(stateFile, stateFile + '.schema2-' + randomUUID() + '.bak'); }
        catch (error) { if (error.code !== 'ENOENT') throw error; }
        state.firstSeenAt = {};
        const knownIds = new Set([...Object.keys(state.metadata), ...Object.values(state.projectIds || {}), ...Object.keys(state.deleted || {}), ...state.imports.map(item => item.id)]);
        for (const id of knownIds) state.firstSeenAt[id] = null;
        for (const item of state.imports) if (Number.isFinite(Date.parse(item.importedAt))) state.firstSeenAt[item.id] = item.importedAt;
        for (const meta of Object.values(state.metadata)) {
            if (meta.categoryId) meta.categoryIds = [meta.categoryId];
            delete meta.categoryId;
        }
        state.schema = 3;
        await atomic(stateFile, state);
    }
    if (!state.firstSeenAt || typeof state.firstSeenAt !== 'object' || Array.isArray(state.firstSeenAt)) throw Error('首次入库时间记录无效');
    if (!Array.isArray(state.categories) || !state.projectIds || defaults.some((_, i) => !state.categories.some(c => c.id === `type-${i}`))
        || state.categories.some(c => typeof c.id !== 'string' || typeof c.name !== 'string')
        || new Set(state.categories.map(c => c.id)).size !== state.categories.length) throw Error('资源库分类索引无效');
}

// Only explicit references in project source/configuration are detectable here.
// Dynamic paths and external tools are deliberately not presented as covered.
export async function scanProjectReferences(projectRoot) {
    const sources = [];
    const extensions = new Set(['.gd', '.tscn', '.tres', '.godot', '.cfg', '.json', '.gdshader', '.cs', '.py']);
    async function walk(dir) {
        for (const item of await fs.readdir(dir, { withFileTypes: true })) {
            if (item.isSymbolicLink() || item.name.startsWith('.') || ['node_modules', 'build', 'tools', 'agent_md'].includes(item.name)) continue;
            const file = path.join(dir, item.name);
            if (file === path.join(projectRoot, 'assets', 'concept_art')) continue;
            if (item.isDirectory()) await walk(file);
            else if (extensions.has(path.extname(file).toLowerCase())) {
                const content = (await fs.readFile(file, 'utf8')).replaceAll('\\\\', '/').replaceAll('\\', '/');
                sources.push({ file: path.relative(projectRoot, file).replaceAll('\\', '/'), content });
            }
        }
    }
    await walk(projectRoot);
    return relativePath => sources.filter(source => source.content.includes(relativePath)).map(source => source.file);
}
export async function renamePermission(record, projectRoot) {
    if (!['concept', 'imported'].includes(record.scope)) return { canRename: false, reason: '原文件仅查看；可修改显示名称、分类、标签和备注。' };
    if (record.source === 'project') {
        for (const suffix of ['.import', '.uid']) {
            try { await fs.lstat(record.file + suffix); return { canRename: false, reason: `存在 ${suffix} 伴随文件，请通过 Godot 管理实际文件名。` }; }
            catch (error) { if (error.code !== 'ENOENT') throw error; }
        }
        const referencedBy = (await scanProjectReferences(projectRoot))(record.relativePath);
        if (referencedBy.length) return { canRename: false, reason: '文件被项目引用：' + referencedBy.join('、'), referencedBy };
    }
    return { canRename: true, reason: '可在原目录重命名；不会改扩展名或覆盖文件。' };
}

// Hard-link + unlink gives same-volume moves a no-overwrite guarantee. The
// journal handles a stop between the two operations, including case-only names.
async function moveExclusive(from, to) { await fs.link(from, to); await fs.unlink(from); }
async function exactExists(file) {
    return (await fs.readdir(path.dirname(file))).includes(path.basename(file));
}
export function createRenamer({ state, stateFile, projectRoot, importRoot, dataRoot, atomic, save, safeFile, scan, get }) {
    const journalFile = path.join(dataRoot, 'rename-pending.json');
    let blocked = false;
    async function journalPaths(journal) {
        if (!['project', 'library'].includes(journal.source) || !validFilename(journal.oldName) || !validFilename(journal.newName)
            || !/^\.rename-[\w-]+$/.test(journal.tempName) || typeof journal.directory !== 'string') throw Error('重命名恢复记录无效');
        const root = journal.source === 'project' ? path.join(projectRoot, 'assets', 'concept_art') : importRoot;
        const dir = await fs.realpath(journal.directory);
        const realRoot = await fs.realpath(root);
        if (dir !== realRoot && !dir.startsWith(realRoot + path.sep)) throw Error('重命名恢复路径越界');
        return { old: path.join(dir, journal.oldName), target: path.join(dir, journal.newName), temp: path.join(dir, journal.tempName) };
    }
    async function recover() {
        let journal;
        try { journal = JSON.parse(await fs.readFile(journalFile, 'utf8')); }
        catch (error) { if (error.code === 'ENOENT') return; throw error; }
        const paths = await journalPaths(journal);
        const committed = journal.source === 'project' ? state.projectIds[journal.newRelative] === journal.id && !state.projectIds[journal.oldRelative]
            : state.imports.find(x => x.id === journal.id)?.file === journal.newRelative;
        const keep = committed ? paths.target : paths.old;
        const present = [];
        for (const file of new Set(Object.values(paths))) if (await exactExists(file)) {
            const stat = await fs.lstat(file, { bigint: true });
            if (!stat.isFile() || stat.isSymbolicLink() || `${stat.dev}:${stat.ino}` !== journal.identity) {
                if (file === keep || file === paths.temp) throw Error('恢复路径已被其他文件占用，请检查 rename-pending.json');
                // A concurrently created destination is not ours to overwrite or remove.
                continue;
            }
            present.push(file);
        }
        if (!present.length) throw Error('重命名恢复文件缺失，请检查 rename-pending.json');
        if (!present.includes(keep)) await fs.link(present[0], keep);
        for (const file of present) if (file !== keep) await fs.unlink(file);
        await fs.unlink(journalFile);
    }
    async function rename(record, stem) {
        if (blocked) throw fail(503, '上次重命名恢复未完成，请重启服务并检查日志');
        const permission = await renamePermission(record, projectRoot);
        if (!permission.canRename) throw fail(403, permission.reason);
        const ext = path.extname(record.name);
        if (typeof stem !== 'string' || !validFilename(stem) || !validFilename(stem + ext)) throw fail(400, '文件名无效，请保留扩展名并避免特殊字符');
        const name = stem + ext;
        if (name === record.name) return record;
        const oldFile = await safeFile(record);
        const directory = path.dirname(oldFile);
        const names = await fs.readdir(directory);
        if (names.some(n => n !== record.name && n.toLowerCase() === name.toLowerCase())) throw fail(409, '同目录已存在同名文件');
        // Revalidate the narrower write root; read access to assets is not write permission.
        const oldRelative = record.source === 'project' ? record.relativePath : state.imports.find(x => x.id === record.id).file;
        const newRelative = path.posix.join(path.posix.dirname(oldRelative), name);
        const stat = await fs.lstat(oldFile, { bigint: true });
        const journal = { id: record.id, source: record.source, directory, oldName: record.name, newName: name,
            oldRelative, newRelative, tempName: '.rename-' + randomUUID(), identity: `${stat.dev}:${stat.ino}` };
        const paths = await journalPaths(journal);
        const before = structuredClone(state);
        // Flush fingerprints/metadata before journalling so recovery sees a consistent base.
        await save();
        await atomic(journalFile, journal);
        try {
            await moveExclusive(paths.old, paths.temp);
            await moveExclusive(paths.temp, paths.target);
            if (record.source === 'project') { delete state.projectIds[oldRelative]; state.projectIds[newRelative] = record.id; }
            else state.imports.find(x => x.id === record.id).file = newRelative;
            await save();
        } catch (error) {
            Object.assign(state, before);
            try { await recover(); } catch (recoveryError) { blocked = true; console.error(recoveryError); throw fail(503, '重命名中断，恢复记录已保留；请重启服务检查'); }
            if (error.code === 'EEXIST') throw fail(409, '目标文件已存在，未覆盖');
            throw error;
        }
        try { await fs.unlink(journalFile); } catch (error) { blocked = true; console.error('重命名已保存，恢复记录将在重启时清理', error); }
        await scan();
        return get(record.id);
    }
    return { recover, rename };
}
