export type Creation = {
  id: string; name: string; kind: string; createdAt: number;
  hasImage: boolean; hasModel: boolean; preview?: string; modelUrl?: string;
  modelStoragePath?: string; previewStoragePath?: string; prompt?: string; projectId?: string;
  conceptIds?: string[]; selectionKnown?: boolean; concepts?: Creation[];
};

/** Group only explicit same-account IDs; titles and timestamps are not identity. */
export function libraryGroups(items: Creation[]): Creation[] {
  const byId = new Map(items.map(item => [item.id, item]));
  const used = new Set<string>();
  const models = items.filter(item => item.hasModel).map(model => {
    const concepts = (model.conceptIds || []).map(id => byId.get(id))
      .filter((c): c is Creation => !!c && !c.hasModel && c.projectId === model.projectId).slice(0, 4);
    concepts.forEach(c => used.add(c.id));
    return { ...model, concepts };
  });
  const drafts = new Map<string, Creation[]>();
  items.filter(item => !item.hasModel && !used.has(item.id)).forEach(item => {
    const key = item.projectId || item.id;
    drafts.set(key, [...(drafts.get(key) || []), item]);
  });
  return [...models, ...Array.from(drafts.values()).flatMap(list => {
    const groups: Creation[] = [];
    for (let i = 0; i < list.length; i += 4) groups.push({ ...list[i], concepts: list.slice(i, i + 4) });
    return groups;
  })].sort((a,b) => b.createdAt-a.createdAt);
}
