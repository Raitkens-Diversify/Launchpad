/**
 * ResourceCategoryTreeProvider
 *
 * Maps Resource_Category__c into CategoryTreeService's shape: one flat query
 * (the table is reference data), one build. Node id is the record Id, slug is
 * Slug__c, sibling order is Display_Order__c then Name.
 *
 * activeOnly = the reader view: an inactive category hides its whole subtree
 * (the tree is rebuilt without them, so no orphan promotion leaks a hidden
 * branch), and only site-visible resources count. The admin view passes
 * false and sees every row.
 *
 * Counts per node: itemCount = resources whose home this is,
 * secondaryItemCount = "Also show in" placements here; descendantItemCount
 * (rolled up by CategoryTreeService) = everything shown under the node.
 */
public with sharing class ResourceCategoryTreeProvider {

    private static final Integer LIST_LIMIT = 2000;

    public static CategoryTreeService.Tree load(Boolean activeOnly) {
        List<Resource_Category__c> rows = [
            SELECT Id, Name, Slug__c, Description__c, Icon_Name__c, Parent_Category__c,
                   Is_Active__c, Display_Order__c
            FROM Resource_Category__c
            ORDER BY Display_Order__c NULLS LAST, Name ASC
            LIMIT :LIST_LIMIT
        ];
        Map<Id, Resource_Category__c> byId = new Map<Id, Resource_Category__c>(rows);
        ResourceCategoryTreeHandler.ChainResolver chains = new ResourceCategoryTreeHandler.ChainResolver(byId);

        List<CategoryTreeService.TreeNode> flat = new List<CategoryTreeService.TreeNode>();
        Set<Id> kept = new Set<Id>();
        for (Resource_Category__c c : rows) {
            if (activeOnly && !visible(c, chains, byId)) {
                continue;
            }
            CategoryTreeService.TreeNode n = new CategoryTreeService.TreeNode(
                c.Id, c.Name, c.Slug__c, c.Parent_Category__c == null ? null : String.valueOf(c.Parent_Category__c));
            n.iconName = c.Icon_Name__c;
            n.description = c.Description__c;
            n.displayOrder = c.Display_Order__c;
            n.active = c.Is_Active__c == true;
            flat.add(n);
            kept.add(c.Id);
        }
        CategoryTreeService.Tree tree = CategoryTreeService.build(flat, CategoryTreeService.maxDepth());
        applyCounts(tree, kept, activeOnly);
        return tree;
    }

    public static CategoryTreeService.TreeDTO loadDTO(Boolean activeOnly) {
        return load(activeOnly).toDTO();
    }

    // ---- Internals ----------------------------------------------------------------

    /** Active itself and every ancestor active (a broken chain hides too). */
    private static Boolean visible(Resource_Category__c c,
            ResourceCategoryTreeHandler.ChainResolver chains, Map<Id, Resource_Category__c> byId) {
        if (c.Is_Active__c != true) {
            return false;
        }
        ResourceCategoryTreeHandler.Chain chain = chains.resolve(c.Id);
        if (chain.missing || chain.cyclic) {
            return false;
        }
        for (Id ancestor : chain.ids) {
            if (byId.get(ancestor).Is_Active__c != true) {
                return false;
            }
        }
        return true;
    }

    private static void applyCounts(CategoryTreeService.Tree tree, Set<Id> categoryIds, Boolean activeOnly) {
        if (categoryIds.isEmpty()) {
            return;
        }
        Map<String, Integer> home = new Map<String, Integer>();
        List<AggregateResult> homeRows = activeOnly
            ? [SELECT Category__c cat, COUNT(Id) c FROM Resource__c
               WHERE Category__c IN :categoryIds AND Is_Active__c = true GROUP BY Category__c]
            : [SELECT Category__c cat, COUNT(Id) c FROM Resource__c
               WHERE Category__c IN :categoryIds GROUP BY Category__c];
        for (AggregateResult ar : homeRows) {
            home.put(String.valueOf(ar.get('cat')), (Integer) ar.get('c'));
        }
        Map<String, Integer> secondary = new Map<String, Integer>();
        if (Schema.sObjectType.Resource_Category_Link__c.isAccessible()) {
            List<AggregateResult> linkRows = activeOnly
                ? [SELECT Category__c cat, COUNT(Id) c FROM Resource_Category_Link__c
                   WHERE Category__c IN :categoryIds
                   AND Resource__r.Is_Active__c = true AND Resource__r.Category__r.Is_Active__c = true
                   GROUP BY Category__c]
                : [SELECT Category__c cat, COUNT(Id) c FROM Resource_Category_Link__c
                   WHERE Category__c IN :categoryIds GROUP BY Category__c];
            for (AggregateResult ar : linkRows) {
                secondary.put(String.valueOf(ar.get('cat')), (Integer) ar.get('c'));
            }
        }
        for (CategoryTreeService.TreeNode n : tree.ordered) {
            n.itemCount = home.containsKey(n.id) ? home.get(n.id) : 0;
            n.secondaryItemCount = secondary.containsKey(n.id) ? secondary.get(n.id) : 0;
        }
        tree.rollUp();
    }
}