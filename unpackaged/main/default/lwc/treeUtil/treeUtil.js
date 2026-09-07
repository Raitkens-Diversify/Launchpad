/**
 * treeUtil — the one pure tree module behind the Help Center / Resource Center
 * category trees: builds and indexes the server's TreeNode shape, answers
 * ancestor/descendant questions, validates moves (self, own subtree, depth
 * counting the moved subtree's height — the same rules and wording as
 * CategoryTreeService.validateMove), flattens a tree into the rows the
 * presentational components render, and does the small breadcrumb and
 * parent-picker helpers. No LWC imports, no DOM.
 *
 * Node shape (both apps): { id, label, slug, parentId, depth (1-based),
 *   path, sortOrder, itemCount, secondaryItemCount, descendantItemCount,
 *   hasChildren, iconName?, description?, active?, children[] }.
 * Keys are node ids: Data Category API names (Help Center) or record Ids
 * (Resource Center) — opaque here.
 *
 * An indexed tree is { roots, byId: Map, ordered: [] (pre-order) }. Indexing
 * never mutates the input: nodes are cloned, so wired (read-only) Apex
 * results can be indexed directly.
 */

export const DEFAULT_MAX_DEPTH = 5;
/** Sidebar depth (1-based) at which c-ds-tree re-roots the panel on the
    active branch — the ONE place this threshold lives (visibleRows, dsTree). */
export const REBASE_DEPTH = 4;

// Mirror of CategoryTreeService's messages — change both together.
export const MSG = Object.freeze({
    SELF: "A category can't be its own parent.",
    DESCENDANT: "Can't move a category into its own subtopic.",
    MISSING_NODE: 'That category no longer exists — refresh.',
    MISSING_PARENT: 'That parent category no longer exists — refresh.',
    depth: (max) => `Can't nest more than ${max} levels deep.`
});

const SEP = '/';

function cloneNode(n) {
    return {
        ...n,
        parentId: n.parentId === undefined ? null : n.parentId,
        itemCount: n.itemCount || 0,
        secondaryItemCount: n.secondaryItemCount || 0,
        descendantItemCount: n.descendantItemCount || 0,
        children: []
    };
}

/** Index nested roots (the server DTO) into { roots, byId, ordered }. */
export function indexTree(roots) {
    const tree = { roots: [], byId: new Map(), ordered: [] };
    const stack = [];
    (roots || []).forEach((r, i) => {
        const c = cloneNode(r);
        c.parentId = null;
        c.depth = 1;
        c.path = SEP + c.id + SEP;
        c.sortOrder = i;
        tree.roots.push(c);
        stack.push([c, r]);
    });
    // Iterative pre-order; sibling order preserved by pushing in reverse.
    const work = stack.reverse();
    while (work.length) {
        const [node, src] = work.pop();
        tree.byId.set(node.id, node);
        tree.ordered.push(node);
        const kids = src.children || [];
        node.hasChildren = kids.length > 0;
        const cloned = kids.map((k, i) => {
            const c = cloneNode(k);
            c.parentId = node.id;
            c.depth = node.depth + 1;
            c.path = node.path + c.id + SEP;
            c.sortOrder = i;
            return c;
        });
        node.children = cloned;
        for (let i = cloned.length - 1; i >= 0; i--) {
            work.push([cloned[i], kids[i]]);
        }
    }
    rollUp(tree);
    return tree;
}

/**
 * Build from flat rows ({ id, label, parentId, ... } in sibling order).
 * Orphans and cycle members become roots so nothing silently disappears.
 */
export function buildTree(flat) {
    const byId = new Map();
    (flat || []).forEach((n) => byId.set(n.id, { ...n, children: [] }));
    const roots = [];
    byId.forEach((n) => {
        const parent = n.parentId == null ? null : byId.get(n.parentId);
        if (parent) {
            parent.children.push(n);
        } else {
            roots.push({ ...n, parentId: null });
        }
    });
    // Nodes unreachable from a root sit in a parent cycle: cut and promote.
    const reachable = new Set();
    const mark = (list) => {
        const work = [...list];
        while (work.length) {
            const n = work.pop();
            if (reachable.has(n.id)) {
                continue;
            }
            reachable.add(n.id);
            work.push(...n.children);
        }
    };
    mark(roots);
    byId.forEach((n) => {
        if (!reachable.has(n.id)) {
            const former = byId.get(n.parentId);
            if (former) {
                former.children = former.children.filter((c) => c.id !== n.id);
            }
            roots.push({ ...n, parentId: null });
            mark([n]);
        }
    });
    return indexTree(roots);
}

function rollUp(tree) {
    for (let i = tree.ordered.length - 1; i >= 0; i--) {
        const n = tree.ordered[i];
        n.descendantItemCount = (n.itemCount || 0) + (n.secondaryItemCount || 0);
        n.children.forEach((c) => {
            n.descendantItemCount += c.descendantItemCount;
        });
    }
}

export function findNode(tree, key) {
    return tree.byId.get(key) || null;
}

/** Root-first ancestors, excluding the node itself. */
export function ancestorsOf(tree, key) {
    const out = [];
    let cursor = tree.byId.get(key);
    const seen = new Set();
    while (cursor && cursor.parentId != null && !seen.has(cursor.parentId)) {
        seen.add(cursor.parentId);
        cursor = tree.byId.get(cursor.parentId);
        if (cursor) {
            out.unshift(cursor);
        }
    }
    return out;
}

/** Ancestor keys root-first, then the key itself. */
export function pathKeys(tree, key) {
    const node = tree.byId.get(key);
    if (!node) {
        return [];
    }
    return [...ancestorsOf(tree, key).map((a) => a.id), key];
}

/** Every node below `key` in pre-order, excluding the node itself. */
export function descendantsOf(tree, key) {
    const start = tree.byId.get(key);
    if (!start) {
        return [];
    }
    return tree.ordered.filter((n) => n.id !== key && n.path.startsWith(start.path));
}

/** Strict: a node is not its own descendant. */
export function isDescendant(tree, key, ancestorKey) {
    const n = tree.byId.get(key);
    const a = tree.byId.get(ancestorKey);
    return Boolean(n && a && key !== ancestorKey && n.path.startsWith(a.path));
}

/** Levels in the subtree rooted at `key` (a leaf is 1). */
export function subtreeHeight(tree, key) {
    const start = tree.byId.get(key);
    if (!start) {
        return 0;
    }
    let deepest = start.depth;
    descendantsOf(tree, key).forEach((n) => {
        deepest = Math.max(deepest, n.depth);
    });
    return deepest - start.depth + 1;
}

/**
 * Why `key` cannot become a child of `newParentKey` (null = top level), or
 * null when the move is legal. Counts the moved subtree's own height.
 */
export function validateMove(tree, key, newParentKey, maxDepth = DEFAULT_MAX_DEPTH) {
    const node = tree.byId.get(key);
    if (!node) {
        return MSG.MISSING_NODE;
    }
    if (newParentKey == null) {
        return subtreeHeight(tree, key) > maxDepth ? MSG.depth(maxDepth) : null;
    }
    if (newParentKey === key) {
        return MSG.SELF;
    }
    const parent = tree.byId.get(newParentKey);
    if (!parent) {
        return MSG.MISSING_PARENT;
    }
    if (isDescendant(tree, newParentKey, key)) {
        return MSG.DESCENDANT;
    }
    if (parent.depth + subtreeHeight(tree, key) > maxDepth) {
        return MSG.depth(maxDepth);
    }
    return null;
}

/**
 * Drop validity for the editor. target = { parentKey|null, index } — the
 * slot among the target parent's children. Reordering within the current
 * parent is always fine; anything else goes through validateMove.
 */
export function canDrop(tree, dragKey, target, maxDepth = DEFAULT_MAX_DEPTH) {
    if (!target) {
        return { ok: false, reason: null };
    }
    const node = tree.byId.get(dragKey);
    if (!node) {
        return { ok: false, reason: MSG.MISSING_NODE };
    }
    const parentKey = target.parentKey == null ? null : target.parentKey;
    if (parentKey === (node.parentId == null ? null : node.parentId)) {
        return { ok: true, reason: null };
    }
    const reason = validateMove(tree, dragKey, parentKey, maxDepth);
    return { ok: reason === null, reason };
}

/** Siblings of a parent (root list for null). */
export function siblingsOf(tree, parentKey) {
    if (parentKey == null) {
        return tree.roots;
    }
    const parent = tree.byId.get(parentKey);
    return parent ? parent.children : [];
}

/**
 * The move a drop implies: the new parent and the FULL ordered sibling key
 * list including the mover (what moveCategory / moveTopic expect), or null
 * when the drop changes nothing.
 */
export function moveResult(tree, dragKey, target) {
    const node = tree.byId.get(dragKey);
    if (!node || !target) {
        return null;
    }
    const parentKey = target.parentKey == null ? null : target.parentKey;
    const keys = siblingsOf(tree, parentKey).map((s) => s.id).filter((k) => k !== dragKey);
    const sameParent = parentKey === (node.parentId == null ? null : node.parentId);
    let index = target.index;
    if (sameParent && node.sortOrder < target.index) {
        index -= 1; // the mover's own slot vanished
    }
    index = Math.max(0, Math.min(index, keys.length));
    keys.splice(index, 0, dragKey);
    if (sameParent && siblingsOf(tree, parentKey).every((s, i) => s.id === keys[i])) {
        return null;
    }
    return { newParentKey: parentKey, orderedSiblingKeys: keys };
}

/**
 * Where the pointer is over a row: the top quarter drops BEFORE it, the
 * bottom quarter AFTER it, the middle INTO it (only when the row may hold
 * the mover, checked by the caller through canDrop). Returns the slot as a
 * { position, parentKey, index } target, or null over the mover / its subtree.
 */
export function dropTarget(tree, dragKey, overKey, ratio, allowInto = true) {
    const over = tree.byId.get(overKey);
    if (!over || overKey === dragKey || isDescendant(tree, overKey, dragKey)) {
        return null;
    }
    if (allowInto && ratio > 0.25 && ratio < 0.75) {
        return { position: 'into', parentKey: over.id, index: over.children.length };
    }
    const parentKey = over.parentId == null ? null : over.parentId;
    const before = ratio <= 0.5;
    return { position: before ? 'before' : 'after', parentKey, index: over.sortOrder + (before ? 0 : 1) };
}

/** Apply a move to the tree (returns a new indexed tree; input untouched). */
export function applyMove(tree, key, newParentKey, orderedSiblingKeys) {
    const flat = tree.ordered.map((n) => ({ ...n, children: undefined }));
    const mover = flat.find((n) => n.id === key);
    if (!mover) {
        return tree;
    }
    mover.parentId = newParentKey == null ? null : newParentKey;
    const orderIndex = new Map((orderedSiblingKeys || []).map((k, i) => [k, i]));
    const siblingParent = mover.parentId;
    const rest = flat.filter((n) => (n.parentId == null ? null : n.parentId) !== siblingParent);
    const siblings = flat
        .filter((n) => (n.parentId == null ? null : n.parentId) === siblingParent)
        .sort((a, b) => (orderIndex.has(a.id) ? orderIndex.get(a.id) : 1e9) - (orderIndex.has(b.id) ? orderIndex.get(b.id) : 1e9));
    return buildTree([...rest, ...siblings]);
}

/** Keys of the active node and every ancestor: what an accordion expands. */
export function expandedForActive(tree, activeKey) {
    return new Set(pathKeys(tree, activeKey));
}

/**
 * Visible rows for a tree whose expanded set is `expandedKeys` (a Set or an
 * array): a node shows when every ancestor is expanded. Each row carries
 * index (0-based position among siblings), setSize, expanded and isLast.
 */
export function flattenTree(tree, expandedKeys, roots = tree.roots) {
    const expanded = expandedKeys instanceof Set ? expandedKeys : new Set(expandedKeys || []);
    const rows = [];
    const work = [];
    for (let i = roots.length - 1; i >= 0; i--) {
        work.push(roots[i]);
    }
    while (work.length) {
        const n = work.pop();
        const siblings = siblingsOf(tree, n.parentId);
        const isExpanded = n.hasChildren && expanded.has(n.id);
        rows.push({
            ...n,
            index: n.sortOrder,
            setSize: siblings.length,
            expanded: isExpanded,
            isLast: n.sortOrder === siblings.length - 1
        });
        if (isExpanded) {
            for (let i = n.children.length - 1; i >= 0; i--) {
                work.push(n.children[i]);
            }
        }
    }
    return rows;
}

/**
 * Sidebar rows: the path to the active node is expanded (siblings visible at
 * every level), everything else collapsed. At depth >= rebaseDepth the list
 * is rebased at the active node's grandparent so deep levels never become a
 * wall of indents: the result carries `base` (the rebased node) and an
 * `upKey` (its parent's key) for a single "back up" row; the breadcrumb
 * carries the rest of the chain.
 */
export function visibleRows(tree, activeKey, { rebaseDepth = REBASE_DEPTH } = {}) {
    const expanded = expandedForActive(tree, activeKey);
    const active = tree.byId.get(activeKey);
    if (!active || active.depth < rebaseDepth) {
        return { rows: flattenTree(tree, expanded), base: null, upKey: null };
    }
    const chain = ancestorsOf(tree, activeKey);
    const base = chain[chain.length - 2]; // grandparent
    const rows = flattenTree(tree, expanded, [base]).map((r) => ({
        ...r,
        depth: r.depth - base.depth + 1
    }));
    return { rows, base, upKey: base.parentId == null ? null : base.parentId };
}

/**
 * Parent-picker options: every node except `excludeKey` and its subtree,
 * labels indented by depth, in tree order. `{ value, label, depth }`.
 */
export function optionsFor(tree, excludeKey, maxDepth = DEFAULT_MAX_DEPTH) {
    const excluded = new Set(excludeKey ? [excludeKey, ...descendantsOf(tree, excludeKey).map((d) => d.id)] : []);
    const height = excludeKey ? subtreeHeight(tree, excludeKey) : 1;
    return tree.ordered
        .filter((n) => !excluded.has(n.id) && n.depth + height <= maxDepth)
        .map((n) => ({
            value: n.id,
            label: `${'— '.repeat(n.depth - 1)}${n.label}`,
            depth: n.depth
        }));
}

/** "1 article" / "3 articles" — the reader-facing count with its noun. */
export function pluralize(n, noun) {
    const count = Number(n) || 0;
    return `${count} ${count === 1 ? noun : noun + 's'}`;
}

/**
 * The count line every reader surface prints for a node: "N articles" for a
 * leaf, "N sections · M articles" for a node with children. Sections are the
 * node's direct children (`children.length`, or a tile's `sectionCount`);
 * the item count is the whole subtree (descendantItemCount, falling back to
 * itemCount). `noun` names the content ('article' / 'resource').
 */
export function countLine(node, noun = 'article') {
    if (!node) {
        return '';
    }
    const sections = node.sectionCount != null ? node.sectionCount : (node.children || []).length;
    const items = node.descendantItemCount != null ? node.descendantItemCount : (node.itemCount || 0);
    const itemsText = pluralize(items, noun);
    return sections > 0 ? `${pluralize(sections, 'section')} · ${itemsText}` : itemsText;
}

/**
 * Breadcrumb truncation: when there are more than `max` items, keep the
 * first, an ellipsis carrying the hidden middle, and the last two.
 */
export function truncateMiddle(items, max) {
    const list = items || [];
    if (!max || max < 3 || list.length <= max) {
        return list;
    }
    const tail = list.slice(-2);
    const hidden = list.slice(1, list.length - 2);
    return [list[0], { ellipsis: true, hidden }, ...tail];
}