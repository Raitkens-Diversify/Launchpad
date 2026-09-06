/**
 * ResourceCategoryTreeHandlerTest — the Resource_Category__c tree invariants
 * at the data layer: Path__c/Depth__c maintenance, cycle and depth guards,
 * descendant rewrites on move, re-rooting on delete, and one-pass repair.
 */
@isTest
private class ResourceCategoryTreeHandlerTest {

    private static Integer seq = 0;

    private static Resource_Category__c cat(String name, Id parentId) {
        seq++;
        Resource_Category__c c = new Resource_Category__c(
            Name = name, Slug__c = name.toLowerCase().replaceAll('[^a-z0-9]+', '-') + '-' + seq,
            Parent_Category__c = parentId, Is_Active__c = true, Display_Order__c = seq);
        insert c;
        return c;
    }

    private static Resource_Category__c reload(Id id) {
        return [SELECT Id, Name, Parent_Category__c, Path__c, Depth__c FROM Resource_Category__c WHERE Id = :id];
    }

    private static String dmlMessage(Resource_Category__c row, Boolean isDelete) {
        try {
            if (isDelete) {
                delete row;
            } else {
                update row;
            }
        } catch (DmlException e) {
            return e.getDmlMessage(0);
        }
        return null;
    }

    @isTest
    static void insertMaintainsPathAndDepthAndCapsAtMaxDepth() {
        CategoryTreeService.maxDepthOverride = 5;
        Resource_Category__c a = cat('A', null);
        Resource_Category__c b = cat('B', a.Id);
        Resource_Category__c c = cat('C', b.Id);
        Resource_Category__c d = cat('D', c.Id);
        Resource_Category__c e = cat('E', d.Id);

        System.assertEquals('/', reload(a.Id).Path__c);
        System.assertEquals(1, reload(a.Id).Depth__c);
        System.assertEquals('/' + a.Id + '/', reload(b.Id).Path__c);
        System.assertEquals('/' + a.Id + '/' + b.Id + '/' + c.Id + '/' + d.Id + '/', reload(e.Id).Path__c);
        System.assertEquals(5, reload(e.Id).Depth__c);

        String error;
        try {
            cat('F', e.Id);
        } catch (DmlException ex) {
            error = ex.getDmlMessage(0);
        }
        System.assertEquals(CategoryTreeService.depthMessage(5), error, 'a sixth level is refused');
        System.assertEquals(0, [SELECT COUNT() FROM Resource_Category__c WHERE Name = 'F']);
    }

    @isTest
    static void selfParentAndCyclesAreRefused() {
        CategoryTreeService.maxDepthOverride = 5;
        Resource_Category__c a = cat('A', null);
        Resource_Category__c b = cat('B', a.Id);
        Resource_Category__c c = cat('C', b.Id);

        // The platform refuses a direct self-reference on a self-lookup before
        // any trigger runs ("Hierarchy Constraint Violation"); the handler's
        // MSG_SELF is the belt for the braces. Either message is a rejection.
        a.Parent_Category__c = a.Id;
        String selfError = dmlMessage(a, false);
        System.assert(selfError == CategoryTreeService.MSG_SELF || selfError.contains('Hierarchy'),
            'self-parent refused: ' + selfError);

        a.Parent_Category__c = c.Id; // grandchild
        System.assertEquals(CategoryTreeService.MSG_DESCENDANT, dmlMessage(a, false));

        a.Parent_Category__c = b.Id; // child
        System.assertEquals(CategoryTreeService.MSG_DESCENDANT, dmlMessage(a, false));

        System.assertEquals(null, reload(a.Id).Parent_Category__c, 'nothing was saved');
        System.assertEquals('/' + a.Id + '/' + b.Id + '/', reload(c.Id).Path__c);
    }

    @isTest
    static void movingASubtreeCountsItsHeightAndRewritesDescendants() {
        CategoryTreeService.maxDepthOverride = 5;
        Resource_Category__c a = cat('A', null);
        Resource_Category__c b = cat('B', a.Id);
        Resource_Category__c c = cat('C', b.Id);
        Resource_Category__c d = cat('D', c.Id);
        Resource_Category__c e = cat('E', d.Id);   // b's subtree is 4 levels tall
        Resource_Category__c x = cat('X', null);
        Resource_Category__c x1 = cat('X1', x.Id);

        b.Parent_Category__c = x1.Id; // 2 + 4 = 6 > 5
        System.assertEquals(CategoryTreeService.depthMessage(5), dmlMessage(b, false));
        System.assertEquals(a.Id, reload(b.Id).Parent_Category__c, 'rejected move leaves the tree alone');

        Test.startTest();
        b.Parent_Category__c = x.Id;  // 1 + 4 = 5: allowed
        update b;
        Test.stopTest();

        System.assertEquals('/' + x.Id + '/', reload(b.Id).Path__c);
        System.assertEquals(2, reload(b.Id).Depth__c);
        System.assertEquals('/' + x.Id + '/' + b.Id + '/', reload(c.Id).Path__c);
        System.assertEquals('/' + x.Id + '/' + b.Id + '/' + c.Id + '/' + d.Id + '/', reload(e.Id).Path__c);
        System.assertEquals(5, reload(e.Id).Depth__c);
        System.assertEquals('/', reload(a.Id).Path__c, 'the old parent is untouched');
    }

    @isTest
    static void deletingAParentReRootsThePromotedSubtree() {
        CategoryTreeService.maxDepthOverride = 5;
        Resource_Category__c a = cat('A', null);
        Resource_Category__c b = cat('B', a.Id);
        Resource_Category__c c = cat('C', b.Id);
        Resource_Category__c d = cat('D', c.Id);

        Test.startTest();
        delete b; // Parent_Category__c is SetNull: c becomes a root
        Test.stopTest();

        Resource_Category__c cNow = reload(c.Id);
        System.assertEquals(null, cNow.Parent_Category__c);
        System.assertEquals('/', cNow.Path__c);
        System.assertEquals(1, cNow.Depth__c);
        Resource_Category__c dNow = reload(d.Id);
        System.assertEquals('/' + c.Id + '/', dNow.Path__c);
        System.assertEquals(2, dNow.Depth__c);
        System.assertEquals('/', reload(a.Id).Path__c);
    }

    @isTest
    static void oneBatchResolvesParentsFromTheBatchAndRepairsEverything() {
        CategoryTreeService.maxDepthOverride = 5;
        // Four roots, then wired into a chain in ONE update whose order is
        // deliberately child-before-parent: the resolver must read the batch.
        Resource_Category__c a = cat('A', null);
        Resource_Category__c b = cat('B', null);
        Resource_Category__c c = cat('C', null);
        Resource_Category__c d = cat('D', null);

        d.Parent_Category__c = c.Id;
        c.Parent_Category__c = b.Id;
        b.Parent_Category__c = a.Id;
        Test.startTest();
        update new List<Resource_Category__c>{ d, c, b };
        Test.stopTest();

        System.assertEquals('/' + a.Id + '/' + b.Id + '/' + c.Id + '/', reload(d.Id).Path__c);
        System.assertEquals(4, reload(d.Id).Depth__c);

        // Whole-table touch (what the backfill script does) is idempotent.
        List<Resource_Category__c> all = [SELECT Id FROM Resource_Category__c];
        update all;
        System.assertEquals('/' + a.Id + '/' + b.Id + '/' + c.Id + '/', reload(d.Id).Path__c);
        System.assertEquals('/' + a.Id + '/', reload(b.Id).Path__c);
        System.assertEquals(1, reload(a.Id).Depth__c);
    }

    @isTest
    static void bulkInsertUnderOneParentStaysWithinLimits() {
        CategoryTreeService.maxDepthOverride = 5;
        Resource_Category__c root = cat('Root', null);
        List<Resource_Category__c> many = new List<Resource_Category__c>();
        for (Integer i = 0; i < 200; i++) {
            many.add(new Resource_Category__c(
                Name = 'Bulk ' + i, Slug__c = 'bulk-' + i, Parent_Category__c = root.Id,
                Is_Active__c = true, Display_Order__c = i));
        }
        Test.startTest();
        insert many;
        Test.stopTest();
        System.assertEquals(200, [SELECT COUNT() FROM Resource_Category__c WHERE Depth__c = 2 AND Path__c = :('/' + root.Id + '/')]);
    }
}