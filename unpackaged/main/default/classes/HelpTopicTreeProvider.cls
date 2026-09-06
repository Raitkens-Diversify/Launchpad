/**
 * HelpTopicTreeProvider
 *
 * Maps the Help_Topics Knowledge data category group into CategoryTreeService's
 * shape. Two sources of the same nesting: the describe (what readers see —
 * one describe per transaction, it is expensive) and a HelpTopicMetadataService
 * snapshot (what the admin console just read live over SOAP). Node id and slug
 * are the category API name; sibling order is the group's order; there are no
 * icon/description fields on data categories.
 *
 * Counts are published articles (Online, latest, en_US) filed on the node —
 * what a reader would see. The admin delete guard counts every version and
 * lives in HelpTopicAdminController on purpose (it must fail closed).
 */
public with sharing class HelpTopicTreeProvider {

    public static final String GROUP_NAME = 'Help_Topics';
    private static final Integer ARTICLE_SCAN_LIMIT = 10000;

    private static List<CategoryTreeService.TreeNode> describeFlatCache;
    private static Map<String, Integer> countCache;

    /** Reader tree from the describe, any depth. Cached flat per transaction. */
    public static CategoryTreeService.Tree load(Boolean withCounts) {
        if (describeFlatCache == null) {
            describeFlatCache = describeFlat();
        }
        return buildFrom(describeFlatCache, withCounts);
    }

    /** Admin tree from a live Metadata API snapshot (root 'All' excluded). */
    public static CategoryTreeService.Tree fromSnapshot(
            List<HelpTopicMetadataService.Category> topLevel, Boolean withCounts) {
        List<CategoryTreeService.TreeNode> flat = new List<CategoryTreeService.TreeNode>();
        // Iterative pre-order over (category, parentName) pairs.
        List<HelpTopicMetadataService.Category> stack = new List<HelpTopicMetadataService.Category>();
        List<String> parents = new List<String>();
        for (Integer i = topLevel.size() - 1; i >= 0; i--) {
            stack.add(topLevel[i]);
            parents.add(null);
        }
        while (!stack.isEmpty()) {
            HelpTopicMetadataService.Category c = stack.remove(stack.size() - 1);
            String parentName = parents.remove(parents.size() - 1);
            flat.add(new CategoryTreeService.TreeNode(c.name, c.label, c.name, parentName));
            for (Integer i = c.children.size() - 1; i >= 0; i--) {
                stack.add(c.children[i]);
                parents.add(c.name);
            }
        }
        return buildFrom(flat, withCounts);
    }

    /** Published-article count per category API name (transaction cached). */
    public static Map<String, Integer> publishedArticleCounts() {
        if (countCache != null) {
            return countCache;
        }
        countCache = new Map<String, Integer>();
        if (!Schema.sObjectType.Knowledge__kav.isAccessible()) {
            return countCache;
        }
        Map<Id, Knowledge__kav> online = new Map<Id, Knowledge__kav>([
            SELECT Id FROM Knowledge__kav
            WHERE PublishStatus = 'Online' AND IsLatestVersion = true AND Language = 'en_US'
            LIMIT :ARTICLE_SCAN_LIMIT
        ]);
        if (online.isEmpty()) {
            return countCache;
        }
        Map<String, Set<Id>> articlesByName = new Map<String, Set<Id>>();
        // DataCategoryGroupName is not filterable in SOQL — filter in Apex.
        for (Knowledge__DataCategorySelection sel : [
            SELECT ParentId, DataCategoryGroupName, DataCategoryName
            FROM Knowledge__DataCategorySelection
            WHERE ParentId IN :online.keySet()
        ]) {
            if (sel.DataCategoryGroupName != GROUP_NAME) {
                continue;
            }
            if (!articlesByName.containsKey(sel.DataCategoryName)) {
                articlesByName.put(sel.DataCategoryName, new Set<Id>());
            }
            articlesByName.get(sel.DataCategoryName).add(sel.ParentId);
        }
        for (String name : articlesByName.keySet()) {
            countCache.put(name, articlesByName.get(name).size());
        }
        return countCache;
    }

    // ---- Internals ----------------------------------------------------------------

    private static CategoryTreeService.Tree buildFrom(
            List<CategoryTreeService.TreeNode> template, Boolean withCounts) {
        // Fresh node objects per build: CategoryTreeService.build mutates
        // children/depth/path, and one transaction may build several trees.
        List<CategoryTreeService.TreeNode> flat = new List<CategoryTreeService.TreeNode>();
        Map<String, Integer> counts = withCounts ? publishedArticleCounts() : null;
        for (CategoryTreeService.TreeNode t : template) {
            CategoryTreeService.TreeNode n = new CategoryTreeService.TreeNode(t.id, t.label, t.slug, t.parentId);
            if (counts != null && counts.containsKey(n.id)) {
                n.itemCount = counts.get(n.id);
            }
            flat.add(n);
        }
        return CategoryTreeService.build(flat, CategoryTreeService.helpTopicMaxDepth());
    }

    /** Every category under the group's root, any depth, in group order. */
    private static List<CategoryTreeService.TreeNode> describeFlat() {
        List<CategoryTreeService.TreeNode> flat = new List<CategoryTreeService.TreeNode>();
        List<Schema.DescribeDataCategoryGroupResult> groups =
            Schema.describeDataCategoryGroups(new List<String>{ 'KnowledgeArticleVersion' });
        List<Schema.DataCategoryGroupSobjectTypePair> pairs =
            new List<Schema.DataCategoryGroupSobjectTypePair>();
        for (Schema.DescribeDataCategoryGroupResult g : groups) {
            if (g.getName() == GROUP_NAME) {
                Schema.DataCategoryGroupSobjectTypePair pair =
                    new Schema.DataCategoryGroupSobjectTypePair();
                pair.setSobject(g.getSobject());
                pair.setDataCategoryGroupName(g.getName());
                pairs.add(pair);
            }
        }
        if (pairs.isEmpty()) {
            return flat;
        }
        for (Schema.DescribeDataCategoryGroupStructureResult structure :
                Schema.describeDataCategoryGroupStructures(pairs, false)) {
            for (Schema.DataCategory root : structure.getTopCategories()) {
                // root is 'All'; its children are the top-level topics.
                List<Schema.DataCategory> stack = new List<Schema.DataCategory>();
                List<String> parents = new List<String>();
                List<Schema.DataCategory> tops = root.getChildCategories();
                for (Integer i = tops.size() - 1; i >= 0; i--) {
                    stack.add(tops[i]);
                    parents.add(null);
                }
                while (!stack.isEmpty()) {
                    Schema.DataCategory c = stack.remove(stack.size() - 1);
                    String parentName = parents.remove(parents.size() - 1);
                    flat.add(new CategoryTreeService.TreeNode(c.getName(), c.getLabel(), c.getName(), parentName));
                    List<Schema.DataCategory> kids = c.getChildCategories();
                    for (Integer i = kids.size() - 1; i >= 0; i--) {
                        stack.add(kids[i]);
                        parents.add(c.getName());
                    }
                }
            }
        }
        return flat;
    }
}