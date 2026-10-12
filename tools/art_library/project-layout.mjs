// Only aliases from an explicit repository migration may retain a project ID.
// Metadata, categories, deletion records and relationships remain keyed by ID.
export function migrateProjectPaths(state, paths) {
    for (const [oldPath, newPath] of Object.entries(paths)) {
        if (!oldPath.startsWith('assets/') || !newPath.startsWith('assets/')) continue;
        const id = state.projectIds[oldPath];
        if (!id || oldPath === newPath) continue;
        const existing = state.projectIds[newPath];
        if (existing && existing !== id) throw Error(`Project migration ID conflict: ${newPath}`);
        state.projectIds[newPath] = id;
        delete state.projectIds[oldPath];
    }
}
