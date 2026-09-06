/**
 * ResourceCategoryTreeHandler
 *
 * Keeps Resource_Category__c.Path__c / Depth__c true and enforces the tree
 * invariants at the data layer — every DML path (admin console, Setup, data
 * loads, API), not just the UI:
 *   - a category can't be its own parent or sit inside its own subtree;
 *   - the tree never exceeds CategoryTreeService.maxDepth(), counting the
 *     height of a subtree being moved, not just the node;
 *   - reparenting rewrites every descendant's path; deleting a parent
 *     (Parent_Category__c is SetNull) re-roots the promoted children.
 *
 * Path__c holds the ANCESTOR ids ("/" for a root, "/a/b/" for a grandchild)
 * so it can be computed in before-insert, where the record has no Id yet.
 * Everything is derived from Parent_Category__c by walking parent chains
 * (batch values first, then stored rows), never from stored paths — so a
 * plain `update` of every row repairs stale data in one pass
 * (scripts/apex/backfillCategoryPaths.apex).
 */
public without sharing class ResourceCategoryTreeHandler {

    /** Set while this class issues its own descendant/child rewrites. */
    private static Boolean rewriting = false;

    // ---- Before insert / update -------------------------------------------------------

    public static void beforeSave(List<Resource_Category__c> rows) {
        Integer maxDepth = CategoryTreeService.maxDepth();
        Map<Id, Resource_Category__c> stored = new Map<Id, Resource_Category__c>([
            SELECT Id, Parent_Category__c FROM Resource_Category__c
        ]);
        Map<Id, Resource_Category__c> effective = new Map<Id, Resource_Category__c>(stored);
        Set<Id> reparented = new Set<Id>();
        for (Resource_Category__c row : rows) {
            if (row.Id != null) {
                effective.put(row.Id, row); // in-batch values win over stored ones
                Resource_Category__c prior = stored.get(row.Id);
                if (prior != null && prior.Parent_Category__c != row.Parent_Category__c) {
                    reparented.add(row.Id);
                }
            }
        }
        ChainResolver chains = new ChainResolver(effective);

        for (Resource_Category__c row : rows) {
            Id parentId = row.Parent_Category__c;
            if (row.Id != null && parentId == row.Id) {
                row.addError(CategoryTreeService.MSG_SELF);
                continue;
            }
            Chain chain;
            if (parentId == null) {
                chain = new Chain();
            } else {
                chain = chains.resolve(parentId);
                if (chain.missing) {
                    row.addError(CategoryTreeService.MSG_MISSING_PARENT);
                    continue;
                }
                if (chain.cyclic || (row.Id != null && chain.ids.contains(row.Id))) {
                    row.addError(CategoryTreeService.MSG_DESCENDANT);
                    continue;
                }
                chain = chain.prepend(parentId);
            }
            Integer depth = chain.ids.size() + 1;
            if (depth > maxDepth) {
                row.addError(CategoryTreeService.depthMessage(maxDepth));
                continue;
            }
            if (reparented.contains(row.Id) && chains.deepestUnder(row.Id) > maxDepth) {
                // Moving a subtree: its deepest descendant must still fit. Only
                // reparented rows pay for the scan — a whole-table repair
                // (backfill script) touches every row without moving any.
                row.addError(CategoryTreeService.depthMessage(maxDepth));
                continue;
            }
            row.Path__c = chain.toPath();
            row.Depth__c = depth;
        }
    }

    // ---- After update -----------------------------------------------------------------

    /** Reparented rows: rewrite every descendant (their before-save recomputes). */
    public static void afterUpdate(List<Resource_Category__c> rows, Map<Id, Resource_Category__c> oldMap) {
        if (rewriting) {
            return;
        }
        Set<Id> moved = new Set<Id>();
        for (Resource_Category__c row : rows) {
            Resource_Category__c prior = oldMap.get(row.Id);
            if (prior.Parent_Category__c != row.Parent_Category__c || prior.Path__c != row.Path__c) {
                moved.add(row.Id);
            }
        }
        if (moved.isEmpty()) {
            return;
        }
        Map<Id, Resource_Category__c> all = new Map<Id, Resource_Category__c>([
            SELECT Id, Parent_Category__c FROM Resource_Category__c
        ]);
        ChainResolver chains = new ChainResolver(all);
        List<Resource_Category__c> descendants = new List<Resource_Category__c>();
        for (Resource_Category__c cat : all.values()) {
            if (moved.contains(cat.Id)) {
                continue;
            }
            Chain chain = chains.resolve(cat.Id);
            for (Id ancestor : chain.ids) {
                if (moved.contains(ancestor)) {
                    descendants.add(new Resource_Category__c(Id = cat.Id));
                    break;
                }
            }
        }
        rewrite(descendants);
    }

    // ---- After delete -----------------------------------------------------------------

    /**
     * Parent_Category__c is SetNull, so the platform promotes the deleted
     * row's children to top level without firing their trigger. Re-root them
     * explicitly (idempotent whether or not the SetNull has already landed)
     * and let before-save recompute the whole promoted subtree.
     */
    public static void afterDelete(List<Resource_Category__c> deleted) {
        if (rewriting) {
            return;
        }
        Set<Id> deletedIds = new Set<Id>();
        Set<String> prefixes = new Set<String>();
        for (Resource_Category__c row : deleted) {
            deletedIds.add(row.Id);
            prefixes.add((row.Path__c == null ? CategoryTreeService.SEP : row.Path__c)
                + row.Id + CategoryTreeService.SEP);
        }
        List<Resource_Category__c> touched = new List<Resource_Category__c>();
        for (Resource_Category__c cat : [
            SELECT Id, Parent_Category__c, Path__c FROM Resource_Category__c
        ]) {
            Boolean directChild = deletedIds.contains(cat.Parent_Category__c);
            Boolean inSubtree = false;
            if (cat.Path__c != null) {
                for (String prefix : prefixes) {
                    if (cat.Path__c.startsWith(prefix)) {
                        inSubtree = true;
                        break;
                    }
                }
            }
            if (!directChild && !inSubtree) {
                continue;
            }
            Resource_Category__c fix = new Resource_Category__c(Id = cat.Id);
            if (directChild || prefixes.contains(cat.Path__c)) {
                fix.Parent_Category__c = null;
            }
            touched.add(fix);
        }
        rewrite(touched);
    }

    private static void rewrite(List<Resource_Category__c> rows) {
        if (rows.isEmpty()) {
            return;
        }
        rewriting = true;
        try {
            update rows;
        } finally {
            rewriting = false;
        }
    }

    // ---- Parent-chain resolution ------------------------------------------------------

    /** Ancestor ids nearest-first, or a status when the chain is broken. */
    public class Chain {
        public List<Id> ids = new List<Id>();
        public Boolean missing = false;
        public Boolean cyclic = false;

        public Chain prepend(Id nearest) {
            Chain c = new Chain();
            c.ids.add(nearest);
            c.ids.addAll(ids);
            return c;
        }

        /** "/" for a root; root-first ids otherwise: "/root/parent/". */
        public String toPath() {
            if (ids.isEmpty()) {
                return CategoryTreeService.SEP;
            }
            List<String> parts = new List<String>();
            for (Integer i = ids.size() - 1; i >= 0; i--) {
                parts.add(String.valueOf(ids[i]));
            }
            return CategoryTreeService.SEP + String.join(parts, CategoryTreeService.SEP) + CategoryTreeService.SEP;
        }
    }

    public class ChainResolver {
        private final Map<Id, Resource_Category__c> rows;
        private final Map<Id, Chain> memo = new Map<Id, Chain>();

        public ChainResolver(Map<Id, Resource_Category__c> rows) {
            this.rows = rows;
        }

        /** Ancestors of `id` (not including `id`), following Parent_Category__c. */
        public Chain resolve(Id id) {
            if (memo.containsKey(id)) {
                return memo.get(id);
            }
            Chain chain = new Chain();
            Resource_Category__c start = rows.get(id);
            if (start == null) {
                chain.missing = true;
                memo.put(id, chain);
                return chain;
            }
            Set<Id> seen = new Set<Id>{ id };
            Id cursor = start.Parent_Category__c;
            while (cursor != null) {
                if (seen.contains(cursor)) {
                    chain.cyclic = true;
                    break;
                }
                Resource_Category__c parent = rows.get(cursor);
                if (parent == null) {
                    chain.missing = true;
                    break;
                }
                seen.add(cursor);
                chain.ids.add(cursor);
                cursor = parent.Parent_Category__c;
            }
            memo.put(id, chain);
            return chain;
        }

        /** Deepest level (1-based) among `id` and its descendants under the batch's parents. */
        public Integer deepestUnder(Id id) {
            Integer deepest = 0;
            for (Id candidate : rows.keySet()) {
                Chain chain = resolve(candidate);
                if (chain.missing || chain.cyclic) {
                    continue;
                }
                if (candidate == id || chain.ids.contains(id)) {
                    deepest = Math.max(deepest, chain.ids.size() + 1);
                }
            }
            return deepest;
        }
    }
}