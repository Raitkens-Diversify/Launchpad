/**
 * UatScopeService
 *
 * A cycle's effective case scope = every case from every attached book
 * (Test_Cycle_Book__c -> Test_Book_Item__c) unioned with directly-added cases
 * (Test_Cycle_Case__c), de-duplicated — the same case reachable through two
 * books, or a book AND a direct add, appears once, with every source labeled.
 *
 * Computed read-time (no cache object, by design — see the build plan): the
 * eager execution slots ARE the materialized scope the tester queue reads;
 * this service is the single implementation every other consumer goes
 * through, so a cache could later be introduced behind these signatures.
 *
 * 3 SOQL per call regardless of cycle count.
 */
public inherited sharing class UatScopeService {

    public class ScopeEntry {
        public Id caseId;
        /** Book names and/or 'Added directly' — every path that reaches the case. */
        public List<String> sources = new List<String>();
        /** Lowest book sort order the case appears at, for stable display order. */
        public Decimal displayOrder;
    }

    /** cycleId -> (caseId -> entry). Cycles with empty scope map to empty maps. */
    public static Map<Id, Map<Id, ScopeEntry>> effectiveScope(Set<Id> cycleIds) {
        Map<Id, Map<Id, ScopeEntry>> result = new Map<Id, Map<Id, ScopeEntry>>();
        if (cycleIds == null || cycleIds.isEmpty()) {
            return result;
        }
        for (Id cycleId : cycleIds) {
            result.put(cycleId, new Map<Id, ScopeEntry>());
        }

        // Books attached per cycle (a book can be attached to many cycles).
        Map<Id, List<Id>> cyclesByBook = new Map<Id, List<Id>>();
        for (Test_Cycle_Book__c junction : [
            SELECT Test_Cycle__c, Test_Book__c
            FROM Test_Cycle_Book__c
            WHERE Test_Cycle__c IN :cycleIds
        ]) {
            if (!cyclesByBook.containsKey(junction.Test_Book__c)) {
                cyclesByBook.put(junction.Test_Book__c, new List<Id>());
            }
            cyclesByBook.get(junction.Test_Book__c).add(junction.Test_Cycle__c);
        }

        if (!cyclesByBook.isEmpty()) {
            for (Test_Book_Item__c item : [
                SELECT Test_Book__c, Test_Book__r.Name, Test_Case__c, Sort_Order__c
                FROM Test_Book_Item__c
                WHERE Test_Book__c IN :cyclesByBook.keySet()
                ORDER BY Test_Book__r.Name, Sort_Order__c
            ]) {
                for (Id cycleId : cyclesByBook.get(item.Test_Book__c)) {
                    addSource(result.get(cycleId), item.Test_Case__c,
                        item.Test_Book__r.Name, item.Sort_Order__c);
                }
            }
        }

        for (Test_Cycle_Case__c direct : [
            SELECT Test_Cycle__c, Test_Case__c
            FROM Test_Cycle_Case__c
            WHERE Test_Cycle__c IN :cycleIds
        ]) {
            addSource(result.get(direct.Test_Cycle__c), direct.Test_Case__c,
                'Added directly', null);
        }
        return result;
    }

    /** Every cycle currently holding any of these books — the book-item
     *  trigger fan-out and the Book editor's usage line both use this. */
    public static Set<Id> cycleIdsUsingBooks(Set<Id> bookIds) {
        Set<Id> cycleIds = new Set<Id>();
        if (bookIds == null || bookIds.isEmpty()) {
            return cycleIds;
        }
        for (Test_Cycle_Book__c junction : [
            SELECT Test_Cycle__c FROM Test_Cycle_Book__c WHERE Test_Book__c IN :bookIds
        ]) {
            cycleIds.add(junction.Test_Cycle__c);
        }
        return cycleIds;
    }

    private static void addSource(Map<Id, ScopeEntry> perCase, Id caseId, String source, Decimal order) {
        ScopeEntry entry = perCase.get(caseId);
        if (entry == null) {
            entry = new ScopeEntry();
            entry.caseId = caseId;
            perCase.put(caseId, entry);
        }
        if (!entry.sources.contains(source)) {
            entry.sources.add(source);
        }
        if (order != null && (entry.displayOrder == null || order < entry.displayOrder)) {
            entry.displayOrder = order;
        }
    }
}