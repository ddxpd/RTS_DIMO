export const RECENT_CATEGORY = { id: 'recent-day', name: '最近一天新增', automatic: true };
export const DAY_MS = 24 * 60 * 60 * 1000;
export function isRecent(firstSeenAt, at) {
    const age = at - Date.parse(firstSeenAt);
    return Number.isFinite(age) && age >= 0 && age < DAY_MS;
}
export function readCategoryIds(body, categories) {
    const ids = body.categoryIds !== undefined ? body.categoryIds : [body.categoryId || categories.find(c => c.name === body.category)?.id];
    if (!Array.isArray(ids) || ids.some(id => typeof id !== 'string' || !categories.some(c => c.id === id))) {
        throw Object.assign(Error('请选择有效的普通分类'), { status: 400 });
    }
    return [...new Set(ids)];
}
export function combineCategories(current, selected, mode = 'replace') {
    const ids = mode === 'add' ? [...new Set([...current, ...selected])] : mode === 'remove' ? current.filter(id => !selected.includes(id)) : selected;
    return ids.length ? ids : ['type-4'];
}
