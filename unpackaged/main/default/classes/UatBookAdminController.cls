/**
 * UatBookAdminController
 *
 * Apex behind the Admin Console's UAT Test Books section (adminUatBooks):
 * book list with case counts, the book editor (fields + ordered case list +
 * candidate cases + the cycles-using-this-book usage line), reorder with
 * stale-set validation (the adminCategoryManager convention: the server
 * rejects the save unless the submitted id set exactly matches the live
 * items, so an optimistic client apply is authoritative on success), and
 * "Run this book" (creates a cycle with the book pre-attached).
 *
 * Removing a case from a book never deletes execution history — it only
 * drops the case from the book's (and therefore attached cycles') scope
 * going forward. The confirmation wording in the UI says so. Deleting a
 * whole book (2026-08-05) follows the same rule: it auto-detaches from its
 * cycles first, which cleans up only pristine unclaimed slots — claimed and
 * touched runs survive.
 *
 * Conventions: with sharing, describe asserts + stripInaccessible,
 * AuraHandledException, JSON-string write payloads (org quirk).
 */
public with sharing class UatBookAdminController {

    // ---- DTOs ----------------------------------------------------------------

    public class BookRowDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String description;
        @AuraEnabled public Integer caseCount;
    }

    public class BookItemDTO {
        @AuraEnabled public Id id;          // Test_Book_Item__c Id
        @AuraEnabled public Id caseId;
        @AuraEnabled public String caseCode;
        @AuraEnabled public String title;   // null = fall back to the code
        @AuraEnabled public String moduleName;
    }

    public class CandidateCaseDTO {
        @AuraEnabled public Id id;          // Test_Case__c Id
        @AuraEnabled public String caseCode;
        @AuraEnabled public String title;   // null = fall back to the code
        @AuraEnabled public String moduleName;
        @AuraEnabled public Id systemId;
        @AuraEnabled public String systemName;
    }

    public class UsageDTO {
        @AuraEnabled public Id cycleId;
        @AuraEnabled public String cycleName;
    }

    public class BookDetailDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String description;
        @AuraEnabled public List<BookItemDTO> items = new List<BookItemDTO>();
        @AuraEnabled public List<CandidateCaseDTO> candidates = new List<CandidateCaseDTO>();
        @AuraEnabled public List<UsageDTO> usedByCycles = new List<UsageDTO>();
    }

    public class BookInput {
        public Id id;               // null = create
        public String name;
        public String description;
    }

    // ---- Reads ---------------------------------------------------------------

    @AuraEnabled
    public static List<BookRowDTO> getBooks() {
        assertBooksReadable();
        List<BookRowDTO> rows = new List<BookRowDTO>();
        for (Test_Book__c b : [
            SELECT Id, Name, Description__c, Case_Count__c
            FROM Test_Book__c
            ORDER BY Name
        ]) {
            BookRowDTO row = new BookRowDTO();
            row.id = b.Id;
            row.name = b.Name;
            row.description = b.Description__c;
            row.caseCount = b.Case_Count__c == null ? 0 : (Integer) b.Case_Count__c;
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled
    public static BookDetailDTO getBookDetail(Id bookId) {
        assertBooksReadable();
        Test_Book__c book;
        try {
            book = [SELECT Id, Name, Description__c FROM Test_Book__c WHERE Id = :bookId];
        } catch (QueryException e) {
            throw auraError('That test book no longer exists.');
        }
        BookDetailDTO dto = new BookDetailDTO();
        dto.id = book.Id;
        dto.name = book.Name;
        dto.description = book.Description__c;

        Set<Id> inBook = new Set<Id>();
        for (Test_Book_Item__c item : [
            SELECT Id, Test_Case__c, Test_Case__r.Case_ID__c, Test_Case__r.Title__c,
                Test_Case__r.Module__r.Name
            FROM Test_Book_Item__c
            WHERE Test_Book__c = :bookId
            ORDER BY Sort_Order__c
        ]) {
            BookItemDTO i = new BookItemDTO();
            i.id = item.Id;
            i.caseId = item.Test_Case__c;
            i.caseCode = item.Test_Case__r.Case_ID__c;
            i.title = item.Test_Case__r.Title__c;
            i.moduleName = item.Test_Case__r.Module__r.Name;
            dto.items.add(i);
            inBook.add(item.Test_Case__c);
        }

        // Only finished definitions are offered — a Draft case in a book that
        // any cycle holds would instantly land in tester queues.
        for (Test_Case__c c : [
            SELECT Id, Case_ID__c, Title__c, Module__r.Name,
                Module__r.Module_Group__r.System__c,
                Module__r.Module_Group__r.System__r.Name
            FROM Test_Case__c
            WHERE Id NOT IN :inBook
            AND Creation_Status__c = :UatConstants.CREATION_COMPLETE
            ORDER BY Case_ID__c
            LIMIT 500
        ]) {
            CandidateCaseDTO cand = new CandidateCaseDTO();
            cand.id = c.Id;
            cand.caseCode = c.Case_ID__c;
            cand.title = c.Title__c;
            cand.moduleName = c.Module__r.Name;
            cand.systemId = c.Module__r.Module_Group__r.System__c;
            cand.systemName = c.Module__r.Module_Group__r.System__r.Name;
            dto.candidates.add(cand);
        }

        // The blast-radius line: which cycles currently use this book.
        for (Test_Cycle_Book__c junction : [
            SELECT Test_Cycle__c, Test_Cycle__r.Name
            FROM Test_Cycle_Book__c
            WHERE Test_Book__c = :bookId
            ORDER BY Test_Cycle__r.Name
        ]) {
            UsageDTO u = new UsageDTO();
            u.cycleId = junction.Test_Cycle__c;
            u.cycleName = junction.Test_Cycle__r.Name;
            dto.usedByCycles.add(u);
        }
        return dto;
    }

    // ---- Writes ---------------------------------------------------------------

    @AuraEnabled
    public static Id saveBook(String inputJson) {
        assertBookAdmin();
        BookInput input;
        try {
            input = String.isBlank(inputJson)
                ? null
                : (BookInput) JSON.deserialize(inputJson, BookInput.class);
        } catch (Exception e) {
            throw auraError('Could not read the form — refresh and try again.');
        }
        if (input == null || String.isBlank(input.name)) {
            throw auraError('Give the book a name.');
        }
        Test_Book__c record = new Test_Book__c(
            Id = input.id,
            Name = input.name.trim(),
            Description__c = input.description
        );
        SObjectAccessDecision decision = Security.stripInaccessible(
            record.Id == null ? AccessType.CREATABLE : AccessType.UPDATABLE,
            new List<Test_Book__c>{ record }
        );
        Test_Book__c stripped = (Test_Book__c) decision.getRecords()[0];
        if (record.Id == null) {
            insert stripped;
            record.Id = stripped.Id;
        } else {
            update stripped;
        }
        return record.Id;
    }

    public class GroupBookPreviewDTO {
        @AuraEnabled public String groupName;
        @AuraEnabled public Integer completeCaseCount;
        @AuraEnabled public Integer totalCaseCount;
    }

    /** Counts behind the Create-book-from-module-group confirm ("Adds N
     *  Complete cases; M draft/retired are skipped"). */
    @AuraEnabled
    public static GroupBookPreviewDTO getGroupBookPreview(Id groupId) {
        assertBooksReadable();
        Module_Group__c grp;
        try {
            grp = [SELECT Name FROM Module_Group__c WHERE Id = :groupId];
        } catch (QueryException e) {
            throw auraError('That module group no longer exists.');
        }
        GroupBookPreviewDTO dto = new GroupBookPreviewDTO();
        dto.groupName = grp.Name;
        dto.totalCaseCount = [
            SELECT COUNT() FROM Test_Case__c WHERE Module__r.Module_Group__c = :groupId
        ];
        dto.completeCaseCount = [
            SELECT COUNT() FROM Test_Case__c
            WHERE Module__r.Module_Group__c = :groupId
            AND Creation_Status__c = :UatConstants.CREATION_COMPLETE
        ];
        return dto;
    }

    /** Taxonomy shortcut: a new book pre-filled with every Complete case
     *  under the module group, in Case ID order. Draft/In Progress/Retired
     *  cases are skipped (the same gate as every add-picker); zero Complete
     *  cases is a friendly error rather than an empty book. */
    @AuraEnabled
    public static Id createBookFromModuleGroup(Id groupId, String bookName) {
        assertBookAdmin();
        if (groupId == null || String.isBlank(bookName)) {
            throw auraError('Give the book a name.');
        }
        List<Test_Case__c> cases = [
            SELECT Id FROM Test_Case__c
            WHERE Module__r.Module_Group__c = :groupId
            AND Creation_Status__c = :UatConstants.CREATION_COMPLETE
            ORDER BY Case_ID__c
        ];
        if (cases.isEmpty()) {
            throw auraError('No Complete cases under this group yet — finish some case '
                + 'definitions first, or create an empty book from the Books section.');
        }
        Test_Book__c book = new Test_Book__c(Name = bookName.trim().left(80));
        insert book;
        List<Test_Book_Item__c> items = new List<Test_Book_Item__c>();
        for (Integer i = 0; i < cases.size(); i++) {
            items.add(new Test_Book_Item__c(
                Test_Book__c = book.Id,
                Test_Case__c = cases[i].Id,
                Sort_Order__c = i + 1
            ));
        }
        insert items;
        return book.Id;
    }

    /** Appends at the end of the run order. */
    @AuraEnabled
    public static Id addCaseToBook(Id bookId, Id caseId) {
        assertBookAdmin();
        if (bookId == null || caseId == null) {
            throw auraError('Missing book or case — refresh and try again.');
        }
        Id itemId = addCaseIfAbsent(bookId, caseId);
        if (itemId == null) {
            throw auraError('That case is already in this book.');
        }
        return itemId;
    }

    /** Core append, shared with the deferred Target_Book__c add (a case
     *  carrying that lookup joins its book when it reaches Complete). Keeps
     *  the Complete gate; an already-present case returns null instead of
     *  throwing so the deferred path is idempotent. */
    public static Id addCaseIfAbsent(Id bookId, Id caseId) {
        if (!Schema.sObjectType.Test_Book_Item__c.isCreateable()) {
            throw auraError('You do not have access to add cases to books.');
        }
        // Server-side backstop for the candidate-list filter above.
        List<Test_Case__c> found = [
            SELECT Creation_Status__c FROM Test_Case__c WHERE Id = :caseId
        ];
        if (found.isEmpty() || found[0].Creation_Status__c != UatConstants.CREATION_COMPLETE) {
            throw auraError('Only cases marked Complete can be added — cycles using this book would show it to testers immediately.');
        }
        Integer existing = [
            SELECT COUNT() FROM Test_Book_Item__c
            WHERE Test_Book__c = :bookId AND Test_Case__c = :caseId
        ];
        if (existing > 0) {
            return null;
        }
        List<Test_Book_Item__c> maxItem = [
            SELECT Sort_Order__c FROM Test_Book_Item__c
            WHERE Test_Book__c = :bookId
            ORDER BY Sort_Order__c DESC
            LIMIT 1
        ];
        Decimal nextOrder = maxItem.isEmpty() || maxItem[0].Sort_Order__c == null
            ? 1
            : maxItem[0].Sort_Order__c + 1;
        Test_Book_Item__c item = new Test_Book_Item__c(
            Test_Book__c = bookId,
            Test_Case__c = caseId,
            Sort_Order__c = nextOrder
        );
        insert item;
        return item.Id;
    }

    /** Drops the case from the book's scope going forward. Never touches
     *  execution history (the UI confirmation says so). */
    @AuraEnabled
    public static void removeCaseFromBook(Id bookItemId) {
        assertBookAdmin();
        if (!Schema.sObjectType.Test_Book_Item__c.isDeletable()) {
            throw auraError('You do not have access to remove cases from books.');
        }
        delete new Test_Book_Item__c(Id = bookItemId);
    }

    /** Persists a full new order. Stale-set validation: the submitted ids
     *  must exactly match the book's live items. */
    @AuraEnabled
    public static void reorderBookCases(Id bookId, List<String> orderedItemIds) {
        assertBookAdmin();
        Map<Id, Test_Book_Item__c> live = new Map<Id, Test_Book_Item__c>([
            SELECT Id FROM Test_Book_Item__c WHERE Test_Book__c = :bookId
        ]);
        if (orderedItemIds == null || live.size() != orderedItemIds.size()
            || !live.keySet().equals(new Set<Id>((List<Id>) orderedItemIds))) {
            throw auraError('This book changed since you loaded it — refresh and try again.');
        }
        List<Test_Book_Item__c> updates = new List<Test_Book_Item__c>();
        Integer order = 1;
        for (String itemId : orderedItemIds) {
            updates.add(new Test_Book_Item__c(Id = itemId, Sort_Order__c = order++));
        }
        update updates;
    }

    /**
     * Delete a book: auto-detach-then-delete in one confirmed action
     * (2026-08-05). The cycle junctions go first in one DML — their
     * after-delete trigger runs cleanupPristineSlots across the affected
     * cycles (pristine unclaimed slots die; claimed, in-progress, and
     * completed runs are kept). Then the book delete cascades its
     * Test_Book_Item__c rows (that trigger resolves no cycles — no-op). The
     * cases themselves are never touched.
     */
    @AuraEnabled
    public static void deleteBook(Id bookId) {
        assertBookAdmin();
        if (!Schema.sObjectType.Test_Book__c.isDeletable()
            || !Schema.sObjectType.Test_Cycle_Book__c.isDeletable()) {
            throw auraError('You do not have access to delete test books.');
        }
        try {
            Integer exists = [SELECT COUNT() FROM Test_Book__c WHERE Id = :bookId];
            if (exists == 0) {
                throw auraError('That test book no longer exists.');
            }
        } catch (QueryException e) {
            throw auraError('That test book no longer exists.');
        }
        List<Test_Cycle_Book__c> junctions = [
            SELECT Id FROM Test_Cycle_Book__c WHERE Test_Book__c = :bookId
        ];
        if (!junctions.isEmpty()) {
            delete junctions;
        }
        try {
            delete new Test_Book__c(Id = bookId);
        } catch (DmlException e) {
            throw auraError('The book could not be deleted: ' + e.getDmlMessage(0));
        }
    }

    /** "Run this book": new cycle named after the book, book pre-attached.
     *  Returns the cycle Id so the console can land on its editor. */
    @AuraEnabled
    public static Id runBook(Id bookId) {
        assertBookAdmin();
        if (!Schema.sObjectType.Test_Cycle__c.isCreateable()) {
            throw auraError('You do not have access to create test cycles.');
        }
        Test_Book__c book;
        try {
            book = [SELECT Name FROM Test_Book__c WHERE Id = :bookId];
        } catch (QueryException e) {
            throw auraError('That test book no longer exists.');
        }
        Test_Cycle__c cycle = new Test_Cycle__c(Name = (book.Name + ' Run').left(120));
        insert cycle;
        insert new Test_Cycle_Book__c(Test_Cycle__c = cycle.Id, Test_Book__c = bookId);
        return cycle.Id;
    }

    // ---- Internals -------------------------------------------------------------

    private static void assertBookAdmin() {
        if (!Schema.sObjectType.Test_Book__c.isCreateable()
            || !Schema.sObjectType.Test_Book__c.isUpdateable()) {
            throw auraError('You do not have access to manage test books.');
        }
    }

    private static void assertBooksReadable() {
        if (!Schema.sObjectType.Test_Book__c.isAccessible()
            || !Schema.sObjectType.Test_Book_Item__c.isAccessible()) {
            throw auraError('You do not have access to test books.');
        }
    }

    /** AuraHandledException whose message survives into logs and test output. */
    private static AuraHandledException auraError(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}