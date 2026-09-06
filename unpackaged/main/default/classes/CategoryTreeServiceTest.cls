/**
 * CategoryTreeServiceTest — pure tree operations, no DML.
 */
@isTest
private class CategoryTreeServiceTest {

    private static CategoryTreeService.TreeNode node(String id, String parentId, Integer items) {
        CategoryTreeService.TreeNode n = new CategoryTreeService.TreeNode(id, id.toUpperCase(), id, parentId);
        n.itemCount = items;
        return n;
    }

    /** a > b > c > d > e (five levels) plus a second root x > x1. */
    private static List<CategoryTreeService.TreeNode> chain() {
        return new List<CategoryTreeService.TreeNode>{
            node('a', null, 1), node('b', 'a', 2), node('c', 'b', 0), node('d', 'c', 4), node('e', 'd', 8),
            node('x', null, 0), node('x1', 'x', 3)
        };
    }

    @isTest
    static void buildsDepthPathOrderAndCounts() {
        CategoryTreeService.Tree tree = CategoryTreeService.build(chain(), 5);

        System.assertEquals(2, tree.roots.size());
        System.assertEquals('a', tree.roots[0].id);
        System.assertEquals(0, tree.roots[0].sortOrder);
        System.assertEquals(1, tree.roots[1].sortOrder);
        System.assertEquals(1, tree.get('a').depth);
        System.assertEquals(5, tree.get('e').depth);
        System.assertEquals('/a/b/c/d/e/', tree.get('e').path);
        System.assertEquals(true, tree.get('a').hasChildren);
        System.assertEquals(false, tree.get('e').hasChildren);
        // own vs. rolled-up counts
        System.assertEquals(1, tree.get('a').itemCount);
        System.assertEquals(15, tree.get('a').descendantItemCount);
        System.assertEquals(12, tree.get('c').descendantItemCount);
        System.assertEquals(7, tree.ordered.size());
        System.assertEquals('a', tree.ordered[0].id);
        System.assertEquals('b', tree.ordered[1].id);
        System.assertEquals(5, tree.toDTO().maxDepth);
        System.assertEquals(7, tree.toDTO().nodeCount);
    }

    @isTest
    static void ancestorsDescendantsAndHeight() {
        CategoryTreeService.Tree tree = CategoryTreeService.build(chain(), 5);

        List<CategoryTreeService.TreeNode> up = tree.ancestorsOf('d');
        System.assertEquals(3, up.size());
        System.assertEquals('a', up[0].id);
        System.assertEquals('c', up[2].id);
        System.assertEquals(0, tree.ancestorsOf('a').size());

        System.assertEquals(new Set<String>{ 'c', 'd', 'e' }, tree.descendantIdsOf('b'));
        System.assertEquals(0, tree.descendantIdsOf('e').size());
        System.assertEquals(true, tree.isDescendant('e', 'a'));
        System.assertEquals(false, tree.isDescendant('a', 'a'));
        System.assertEquals(false, tree.isDescendant('x1', 'a'));

        System.assertEquals(5, tree.subtreeHeight('a'));
        System.assertEquals(3, tree.subtreeHeight('c'));
        System.assertEquals(1, tree.subtreeHeight('e'));
        System.assertEquals(0, tree.subtreeHeight('nope'));
    }

    @isTest
    static void validateMoveCoversEveryRule() {
        CategoryTreeService.Tree tree = CategoryTreeService.build(chain(), 5);

        System.assertEquals(CategoryTreeService.MSG_MISSING_NODE, tree.validateMove('nope', 'a'));
        System.assertEquals(CategoryTreeService.MSG_SELF, tree.validateMove('b', 'b'));
        System.assertEquals(CategoryTreeService.MSG_MISSING_PARENT, tree.validateMove('b', 'nope'));
        System.assertEquals(CategoryTreeService.MSG_DESCENDANT, tree.validateMove('b', 'e'));
        // c's subtree is 3 tall; under x1 (depth 2) it would reach level 5 — allowed.
        System.assertEquals(null, tree.validateMove('c', 'x1'));
        // b's subtree is 4 tall; under x1 it would reach level 6 — rejected.
        System.assertEquals(CategoryTreeService.depthMessage(5), tree.validateMove('b', 'x1'));
        // Promoting to top level is always fine for a valid tree.
        System.assertEquals(null, tree.validateMove('e', null));
        System.assertEquals(null, tree.validateMove('x1', 'a'));
    }

    @isTest
    static void orphansAndCyclesBecomeRootsNotLosses() {
        List<CategoryTreeService.TreeNode> flat = new List<CategoryTreeService.TreeNode>{
            node('root', null, 0),
            node('lost', 'gone', 0),          // orphan
            node('p', 'q', 0), node('q', 'p', 0) // two-node cycle
        };
        CategoryTreeService.Tree tree = CategoryTreeService.build(flat, 5);

        System.assertEquals(4, tree.ordered.size(), 'every node is still in the tree');
        System.assertEquals(1, tree.orphanCount);
        System.assertEquals(1, tree.cycleCount, 'one cut breaks a two-node cycle');
        System.assertEquals(null, tree.get('lost').parentId);
        System.assertEquals(1, tree.get('lost').depth);
        Boolean pIsRoot = tree.get('p').parentId == null;
        Boolean qIsRoot = tree.get('q').parentId == null;
        System.assert(pIsRoot != qIsRoot, 'exactly one of the cycle nodes is promoted');
        System.assertEquals(2, tree.get(pIsRoot ? 'q' : 'p').depth);
    }

    @isTest
    static void maxDepthReadsSettingOrDefault() {
        CategoryTreeService.maxDepthOverride = 3;
        System.assertEquals(3, CategoryTreeService.maxDepth());
        System.assertEquals(3, CategoryTreeService.helpTopicMaxDepth());
        CategoryTreeService.maxDepthOverride = 8;
        System.assertEquals(8, CategoryTreeService.maxDepth());
        System.assertEquals(CategoryTreeService.PLATFORM_DATA_CATEGORY_DEPTH,
            CategoryTreeService.helpTopicMaxDepth(), 'help topics clamp to the platform limit');
        CategoryTreeService.maxDepthOverride = null;
        System.assert(CategoryTreeService.maxDepth() > 0, 'setting or default');
        System.assert(CategoryTreeService.depthMessage(5).contains('5'));
    }
}