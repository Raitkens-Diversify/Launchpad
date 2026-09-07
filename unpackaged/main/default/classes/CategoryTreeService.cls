/**
 * CategoryTreeService
 *
 * The one tree model shared by the Help Center (Help_Topics data categories)
 * and the Resource Center (Resource_Category__c). Providers map each store
 * into flat TreeNode rows; this class builds and indexes the tree, answers
 * ancestor/descendant questions, validates moves, and owns the max-depth
 * setting and the validation wording. c/treeUtil mirrors the rules and the
 * messages client-side — change them together.
 *
 * Conventions: depth is 1-based (1 = top level) so it equals aria-level in
 * the UI; a built node's `path` is the full id path INCLUDING the node
 * ("/a/b/c/"). Resource_Category__c.Path__c stores the ANCESTOR path
 * ("/a/b/") because a record's own Id is unknown in before-insert — see
 * ResourceCategoryTreeHandler.
 */
public with sharing class CategoryTreeService {

    public static final Integer DEFAULT_MAX_DEPTH = 5;
    /** Salesforce caps a data category group at 5 levels (8 on request). */
    public static final Integer PLATFORM_DATA_CATEGORY_DEPTH = 5;
    public static final String SEP = '/';

    public static final String MSG_SELF = 'A category can\'t be its own parent.';
    public static final String MSG_DESCENDANT = 'Can\'t move a category into its own subtopic.';
    public static final String MSG_MISSING_NODE = 'That category no longer exists — refresh.';
    public static final String MSG_MISSING_PARENT = 'That parent category no longer exists — refresh.';

    public static String depthMessage(Integer maxDepth) {
        return 'Can\'t nest more than ' + maxDepth + ' levels deep.';
    }

    @TestVisible private static Integer maxDepthOverride;

    /** Resource_Center_Setting__mdt.Default.Max_Category_Depth__c, or 5. */
    public static Integer maxDepth() {
        if (maxDepthOverride != null) {
            return maxDepthOverride;
        }
        Integer depth = DEFAULT_MAX_DEPTH;
        Resource_Center_Setting__mdt setting = Resource_Center_Setting__mdt.getInstance('Default');
        if (setting != null) {
            // Read defensively so the class behaves if the record predates the field.
            Object raw = setting.getPopulatedFieldsAsMap().get('Max_Category_Depth__c');
            if (raw instanceof Decimal && ((Decimal) raw) > 0) {
                depth = ((Decimal) raw).intValue();
            }
        }
        return depth;
    }

    /** Help topics live in a data category group, which the platform caps. */
    public static Integer helpTopicMaxDepth() {
        return Math.min(maxDepth(), PLATFORM_DATA_CATEGORY_DEPTH);
    }

    // ---- Shapes ---------------------------------------------------------------------

    public class TreeNode {
        @AuraEnabled public String id;
        @AuraEnabled public String label;
        @AuraEnabled public String slug;
        @AuraEnabled public String parentId;
        @AuraEnabled public Integer depth;
        @AuraEnabled public String path;
        @AuraEnabled public Integer sortOrder;
        /** The store's own order value (Resource_Category__c.Display_Order__c);
            null for help topics. Echoed by edits so a rename keeps its slot. */
        @AuraEnabled public Decimal displayOrder;
        /** Content that lives on this node (home resources / filed articles). */
        @AuraEnabled public Integer itemCount = 0;
        /** Content also shown here ("Also show in" placements); 0 for help topics. */
        @AuraEnabled public Integer secondaryItemCount = 0;
        /** Everything shown on this node or below: own + secondary, rolled up. */
        @AuraEnabled public Integer descendantItemCount = 0;
        @AuraEnabled public Boolean hasChildren = false;
        @AuraEnabled public String iconName;
        @AuraEnabled public String description;
        @AuraEnabled public Boolean active = true;
        @AuraEnabled public List<TreeNode> children = new List<TreeNode>();

        public TreeNode() {}
        public TreeNode(String id, String label, String slug, String parentId) {
            this.id = id;
            this.label = label;
            this.slug = slug;
            this.parentId = parentId;
        }
    }

    /** What the LWC tiers receive: the limit travels with the tree. */
    public class TreeDTO {
        @AuraEnabled public Integer maxDepth;
        @AuraEnabled public Integer nodeCount = 0;
        @AuraEnabled public List<TreeNode> roots = new List<TreeNode>();
    }

    // ---- Tree -----------------------------------------------------------------------

    /**
     * Build from flat rows. Sibling order = input order (providers pre-sort by
     * their order field); sortOrder is rewritten to the 0-based index among
     * siblings. Orphans (parentId not in the set) and nodes caught in a parent
     * cycle are promoted to roots so nothing silently disappears, and counted.
     */
    public static Tree build(List<TreeNode> flat) {
        return build(flat, maxDepth());
    }

    public static Tree build(List<TreeNode> flat, Integer maxDepth) {
        Tree tree = new Tree();
        tree.maxDepth = maxDepth;
        for (TreeNode n : flat) {
            n.children = new List<TreeNode>();
            tree.byId.put(n.id, n);
        }
        for (TreeNode n : flat) {
            TreeNode parent = n.parentId == null ? null : tree.byId.get(n.parentId);
            if (n.parentId != null && parent == null) {
                tree.orphanCount++;
                n.parentId = null;
            }
            if (parent == null) {
                tree.roots.add(n);
            } else {
                parent.children.add(n);
            }
        }
        List<TreeNode> ordered = new List<TreeNode>();
        Set<String> visited = new Set<String>();
        walk(tree.roots, ordered, visited);
        for (TreeNode n : flat) {
            if (!visited.contains(n.id)) {
                // Part of a parent cycle: cut it here and start a new root.
                tree.cycleCount++;
                TreeNode former = n.parentId == null ? null : tree.byId.get(n.parentId);
                if (former != null) {
                    for (Integer i = former.children.size() - 1; i >= 0; i--) {
                        if (former.children[i].id == n.id) {
                            former.children.remove(i);
                        }
                    }
                }
                n.parentId = null;
                tree.roots.add(n);
                walk(new List<TreeNode>{ n }, ordered, visited);
            }
        }
        tree.ordered = ordered;
        for (Integer i = 0; i < tree.roots.size(); i++) {
            tree.roots[i].sortOrder = i;
        }
        tree.rollUp();
        return tree;
    }

    /** Iterative pre-order (depth is data-controlled; no recursion). */
    private static void walk(List<TreeNode> roots, List<TreeNode> ordered, Set<String> visited) {
        List<TreeNode> stack = new List<TreeNode>();
        for (Integer i = roots.size() - 1; i >= 0; i--) {
            TreeNode r = roots[i];
            r.depth = 1;
            r.path = SEP + r.id + SEP;
            stack.add(r);
        }
        while (!stack.isEmpty()) {
            TreeNode n = stack.remove(stack.size() - 1);
            if (visited.contains(n.id)) {
                continue;
            }
            visited.add(n.id);
            ordered.add(n);
            n.hasChildren = !n.children.isEmpty();
            for (Integer i = n.children.size() - 1; i >= 0; i--) {
                TreeNode c = n.children[i];
                c.depth = n.depth + 1;
                c.path = n.path + c.id + SEP;
                c.sortOrder = i;
                stack.add(c);
            }
        }
    }

    public class Tree {
        public Integer maxDepth;
        public Integer orphanCount = 0;
        public Integer cycleCount = 0;
        public List<TreeNode> roots = new List<TreeNode>();
        public Map<String, TreeNode> byId = new Map<String, TreeNode>();
        /** Pre-order (parents before children, siblings in order). */
        public List<TreeNode> ordered = new List<TreeNode>();

        public Integer size() {
            return byId.size();
        }

        public TreeNode get(String id) {
            return byId.get(id);
        }

        public Boolean contains(String id) {
            return byId.containsKey(id);
        }

        /** Recompute descendantItemCount (own + secondary + children) children-first. */
        public void rollUp() {
            for (Integer i = ordered.size() - 1; i >= 0; i--) {
                TreeNode n = ordered[i];
                n.descendantItemCount = (n.itemCount == null ? 0 : n.itemCount)
                    + (n.secondaryItemCount == null ? 0 : n.secondaryItemCount);
                for (TreeNode c : n.children) {
                    n.descendantItemCount += c.descendantItemCount;
                }
            }
        }

        /** Root-first ancestors, excluding the node itself. */
        public List<TreeNode> ancestorsOf(String id) {
            List<TreeNode> nearestFirst = new List<TreeNode>();
            TreeNode cursor = byId.get(id);
            Set<String> seen = new Set<String>();
            while (cursor != null && cursor.parentId != null && !seen.contains(cursor.parentId)) {
                seen.add(cursor.parentId);
                cursor = byId.get(cursor.parentId);
                if (cursor != null) {
                    nearestFirst.add(cursor);
                }
            }
            List<TreeNode> chain = new List<TreeNode>();
            for (Integer i = nearestFirst.size() - 1; i >= 0; i--) {
                chain.add(nearestFirst[i]);
            }
            return chain;
        }

        /** Every node under `id` (pre-order), excluding the node itself. */
        public List<TreeNode> descendantsOf(String id) {
            List<TreeNode> out = new List<TreeNode>();
            TreeNode start = byId.get(id);
            if (start == null) {
                return out;
            }
            for (TreeNode n : ordered) {
                if (n.id != id && n.path != null && n.path.startsWith(start.path)) {
                    out.add(n);
                }
            }
            return out;
        }

        public Set<String> descendantIdsOf(String id) {
            Set<String> ids = new Set<String>();
            for (TreeNode n : descendantsOf(id)) {
                ids.add(n.id);
            }
            return ids;
        }

        /** Every node id in pre-order (roots first, each branch top-down). */
        public List<String> orderedIds() {
            List<String> ids = new List<String>();
            for (TreeNode n : ordered) {
                ids.add(n.id);
            }
            return ids;
        }

        /** Strict: a node is not its own descendant. */
        public Boolean isDescendant(String id, String ancestorId) {
            TreeNode n = byId.get(id);
            TreeNode a = byId.get(ancestorId);
            return n != null && a != null && id != ancestorId && n.path.startsWith(a.path);
        }

        /** Levels in the subtree rooted at `id` (a leaf is 1). */
        public Integer subtreeHeight(String id) {
            TreeNode start = byId.get(id);
            if (start == null) {
                return 0;
            }
            Integer deepest = start.depth;
            for (TreeNode n : descendantsOf(id)) {
                deepest = Math.max(deepest, n.depth);
            }
            return deepest - start.depth + 1;
        }

        /**
         * Why `nodeId` cannot become a child of `newParentId` (null = top
         * level), or null when the move is legal. Counts the moved subtree's
         * own height against the limit, not just the node.
         */
        public String validateMove(String nodeId, String newParentId) {
            TreeNode node = byId.get(nodeId);
            if (node == null) {
                return MSG_MISSING_NODE;
            }
            if (newParentId == null) {
                return subtreeHeight(nodeId) > maxDepth ? depthMessage(maxDepth) : null;
            }
            if (newParentId == nodeId) {
                return MSG_SELF;
            }
            TreeNode parent = byId.get(newParentId);
            if (parent == null) {
                return MSG_MISSING_PARENT;
            }
            if (isDescendant(newParentId, nodeId)) {
                return MSG_DESCENDANT;
            }
            if (parent.depth + subtreeHeight(nodeId) > maxDepth) {
                return depthMessage(maxDepth);
            }
            return null;
        }

        public TreeDTO toDTO() {
            TreeDTO dto = new TreeDTO();
            dto.maxDepth = maxDepth;
            dto.nodeCount = byId.size();
            dto.roots = roots;
            return dto;
        }
    }
}