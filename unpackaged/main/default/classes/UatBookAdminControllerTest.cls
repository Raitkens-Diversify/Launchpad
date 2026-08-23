/**
 * Tests for UatBookAdminController — book CRUD, ordered case management,
 * stale-set reorder validation, the usage line, and "Run this book".
 */
@IsTest
private class UatBookAdminControllerTest {

    @TestSetup
    static void setup() {
        UatTestDataFactory.createAdminUser('uatadm');
        UatTestDataFactory.createTesterUser('uattst');
    }

    private static User adminUser() {
        return [SELECT Id FROM User WHERE LastName = 'UAT uatadm' LIMIT 1];
    }

    @IsTest
    static void bookLifecycleWithOrderedCases() {
        System.runAs(adminUser()) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
            Test_Case__c c1 = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1001);
            Test_Case__c c2 = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1002);

            Test.startTest();
            Id bookId = UatBookAdminController.saveBook(
                JSON.serialize(new Map<String, Object>{ 'name' => 'Regression Core', 'description' => 'Core flows' }));
            Id item1 = UatBookAdminController.addCaseToBook(bookId, c1.Id);
            Id item2 = UatBookAdminController.addCaseToBook(bookId, c2.Id);
            Test.stopTest();

            UatBookAdminController.BookDetailDTO detail = UatBookAdminController.getBookDetail(bookId);
            Assert.areEqual(2, detail.items.size());
            Assert.areEqual(item1, detail.items[0].id, 'Append order preserved.');
            Assert.areEqual(0, detail.candidates.size(), 'Both cases now in the book.');

            // Duplicate add is rejected.
            try {
                UatBookAdminController.addCaseToBook(bookId, c1.Id);
                Assert.fail('Duplicate add should throw.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('already'), e.getMessage());
            }

            // Reorder: reverse.
            UatBookAdminController.reorderBookCases(bookId, new List<String>{ item2, item1 });
            detail = UatBookAdminController.getBookDetail(bookId);
            Assert.areEqual(item2, detail.items[0].id, 'New order persisted.');

            // Stale-set reorder is rejected.
            try {
                UatBookAdminController.reorderBookCases(bookId, new List<String>{ item2 });
                Assert.fail('Stale set should throw.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('changed'), e.getMessage());
            }

            // Remove: case leaves the book, reappears as a candidate.
            UatBookAdminController.removeCaseFromBook(item1);
            detail = UatBookAdminController.getBookDetail(bookId);
            Assert.areEqual(1, detail.items.size());
            Assert.areEqual(1, detail.candidates.size());

            List<UatBookAdminController.BookRowDTO> rows = UatBookAdminController.getBooks();
            Assert.areEqual(1, rows.size());
            Assert.areEqual(1, rows[0].caseCount, 'Native rollup reflects the removal.');
        }
    }

    @IsTest
    static void runBookCreatesCycleWithBookAttached() {
        System.runAs(adminUser()) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
            Test_Case__c c1 = UatTestDataFactory.makeCase(tax.mod.Id, 1);
            Test_Book__c book = UatTestDataFactory.makeBook('Smoke Pack', new List<Id>{ c1.Id });

            Test.startTest();
            Id cycleId = UatBookAdminController.runBook(book.Id);
            Test.stopTest();

            Test_Cycle__c cycle = [SELECT Name FROM Test_Cycle__c WHERE Id = :cycleId];
            Assert.areEqual('Smoke Pack Run', cycle.Name);
            Assert.areEqual(1, [
                SELECT COUNT() FROM Test_Cycle_Book__c
                WHERE Test_Cycle__c = :cycleId AND Test_Book__c = :book.Id
            ], 'Book pre-attached.');

            UatBookAdminController.BookDetailDTO detail = UatBookAdminController.getBookDetail(book.Id);
            Assert.areEqual(1, detail.usedByCycles.size(), 'Usage line lists the new cycle.');
            Assert.areEqual(cycleId, detail.usedByCycles[0].cycleId);
        }
    }

    /** Create-book-from-module-group: bundles the group's Complete cases in
     *  Case ID order, skips drafts, and the preview counts both. */
    @IsTest
    static void createBookFromModuleGroupBundlesCompleteCases() {
        System.runAs(adminUser()) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
            Test_Case__c c2 = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1002);
            Test_Case__c c1 = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1001);
            Test_Case__c draft = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1003);
            update new Test_Case__c(Id = draft.Id, Creation_Status__c = 'Draft');

            UatBookAdminController.GroupBookPreviewDTO preview =
                UatBookAdminController.getGroupBookPreview(tax.grp.Id);
            Assert.areEqual(3, preview.totalCaseCount);
            Assert.areEqual(2, preview.completeCaseCount);
            Assert.areEqual(tax.grp.Name, preview.groupName);

            Test.startTest();
            Id bookId = UatBookAdminController.createBookFromModuleGroup(
                tax.grp.Id, '  Helios Group Book  ');
            Test.stopTest();

            Assert.areEqual('Helios Group Book',
                [SELECT Name FROM Test_Book__c WHERE Id = :bookId].Name, 'Name is trimmed.');
            List<Test_Book_Item__c> items = [
                SELECT Test_Case__c, Sort_Order__c FROM Test_Book_Item__c
                WHERE Test_Book__c = :bookId ORDER BY Sort_Order__c
            ];
            Assert.areEqual(2, items.size(), 'The draft case is skipped.');
            Assert.areEqual(c1.Id, items[0].Test_Case__c, 'Case ID order: -1001 first.');
            Assert.areEqual(c2.Id, items[1].Test_Case__c);
            Assert.areEqual(1, items[0].Sort_Order__c);
            Assert.areEqual(2, items[1].Sort_Order__c);
        }
    }

    @IsTest
    static void createBookFromEmptyGroupRejected() {
        System.runAs(adminUser()) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
            try {
                UatBookAdminController.createBookFromModuleGroup(tax.grp.Id, 'Empty Book');
                Assert.fail('Zero Complete cases should be rejected.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('No Complete cases'), e.getMessage());
            }
            Assert.areEqual(0, [SELECT COUNT() FROM Test_Book__c], 'No empty book is created.');
        }
    }

    /** The deferred-add core: first add appends, a repeat returns null
     *  instead of throwing (the UI path addCaseToBook still throws). */
    @IsTest
    static void addCaseIfAbsentIsIdempotent() {
        System.runAs(adminUser()) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
            Test_Case__c c1 = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1001);
            Test_Book__c book = UatTestDataFactory.makeBook('Regression Core', new List<Id>());

            Test.startTest();
            Id first = UatBookAdminController.addCaseIfAbsent(book.Id, c1.Id);
            Id second = UatBookAdminController.addCaseIfAbsent(book.Id, c1.Id);
            Test.stopTest();

            Assert.isNotNull(first, 'First add creates the item.');
            Assert.isNull(second, 'Repeat add is a silent no-op.');
            Assert.areEqual(1, [SELECT COUNT() FROM Test_Book_Item__c WHERE Test_Book__c = :book.Id]);

            try {
                UatBookAdminController.addCaseToBook(book.Id, c1.Id);
                Assert.fail('The UI path still throws on a duplicate.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('already'), e.getMessage());
            }
        }
    }

    @IsTest
    static void draftCasesGatedOutOfBooks() {
        System.runAs(adminUser()) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
            Test_Case__c done = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1001);
            Test_Case__c draft = new Test_Case__c(
                Module__c = tax.mod.Id,
                Version__c = 'v1.0',
                Sequence__c = 1002,
                Creation_Status__c = 'Draft',
                Testing_Surface__c = 'Lightning App (Internal)'
            );
            insert draft;
            Id bookId = UatBookAdminController.saveBook(
                JSON.serialize(new Map<String, Object>{ 'name' => 'Gated' }));

            Test.startTest();
            UatBookAdminController.BookDetailDTO detail = UatBookAdminController.getBookDetail(bookId);
            Assert.areEqual(1, detail.candidates.size(), 'Draft case is not offered.');
            Assert.areEqual(done.Id, detail.candidates[0].id);

            try {
                UatBookAdminController.addCaseToBook(bookId, draft.Id);
                Assert.fail('Adding a Draft case should throw.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('Complete'), e.getMessage());
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void testerCannotWrite() {
        User tester = [SELECT Id FROM User WHERE LastName = 'UAT uattst' LIMIT 1];
        System.runAs(tester) {
            try {
                UatBookAdminController.saveBook(JSON.serialize(new Map<String, Object>{ 'name' => 'Rogue' }));
                Assert.fail('Tester write should throw.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('access'), e.getMessage());
            }
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Test_Book__c]);
    }

    // ---- Delete book (2026-08-05: auto-detach-then-delete) ------------------------

    @IsTest
    static void deleteBookDetachesCyclesAndKeepsTouchedRuns() {
        User tester = [SELECT Id FROM User WHERE LastName = 'UAT uattst' LIMIT 1];
        Test_Book__c book;
        Test_Cycle__c cycle;
        Id claimedCaseId;
        System.runAs(adminUser()) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('BookDel');
            Test_Case__c claimed = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1001);
            Test_Case__c pristine = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1002);
            claimedCaseId = claimed.Id;
            book = UatTestDataFactory.makeBook('Doomed Book', new List<Id>{ claimed.Id, pristine.Id });
            cycle = UatTestDataFactory.makeCycle('Host Cycle', null, new List<Id>{ book.Id }, null);
        }
        System.runAs(tester) {
            UatRunController.claimCase(cycle.Id, claimedCaseId);
        }

        System.runAs(adminUser()) {
            Test.startTest();
            UatBookAdminController.deleteBook(book.Id);
            Test.stopTest();
        }

        Assert.areEqual(0, [SELECT COUNT() FROM Test_Book__c WHERE Id = :book.Id]);
        Assert.areEqual(0, [SELECT COUNT() FROM Test_Book_Item__c WHERE Test_Book__c = :book.Id],
            'Case links cascade with the book.');
        Assert.areEqual(0, [SELECT COUNT() FROM Test_Cycle_Book__c WHERE Test_Book__c = :book.Id],
            'Cycle junctions auto-detached first.');
        Assert.areEqual(1, [
            SELECT COUNT() FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id
        ], 'The claimed run survives; the pristine unclaimed slot was cleaned up.');
        Assert.areEqual(claimedCaseId, [
            SELECT Test_Case__c FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id
        ].Test_Case__c, 'The survivor is the claimed one.');
        Assert.areEqual(2, [SELECT COUNT() FROM Test_Case__c],
            'The cases themselves are never touched.');
    }

    @IsTest
    static void deleteBookUnattached() {
        System.runAs(adminUser()) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('BookDel');
            Test_Case__c tc = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1001);
            Test_Book__c book = UatTestDataFactory.makeBook('Loose Book', new List<Id>{ tc.Id });

            Test.startTest();
            UatBookAdminController.deleteBook(book.Id);
            Test.stopTest();

            Assert.areEqual(0, [SELECT COUNT() FROM Test_Book__c WHERE Id = :book.Id]);
            Assert.areEqual(1, [SELECT COUNT() FROM Test_Case__c WHERE Id = :tc.Id]);
        }
    }

    @IsTest
    static void deleteBookGateNegative() {
        Test_Book__c book;
        System.runAs(adminUser()) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('BookDel');
            Test_Case__c tc = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1001);
            book = UatTestDataFactory.makeBook('Guarded Book', new List<Id>{ tc.Id });
        }
        User tester = [SELECT Id FROM User WHERE LastName = 'UAT uattst' LIMIT 1];
        System.runAs(tester) {
            try {
                UatBookAdminController.deleteBook(book.Id);
                Assert.fail('Testers must not delete books.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('access'), e.getMessage());
            }
        }
        Assert.areEqual(1, [SELECT COUNT() FROM Test_Book__c WHERE Id = :book.Id]);
    }
}