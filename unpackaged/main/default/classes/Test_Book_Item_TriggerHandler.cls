/**
 * Test_Book_Item_TriggerHandler — the cross-object fan-out: a case added to
 * (or removed from) a book reaches EVERY cycle currently holding that book.
 * Slot creation/cleanup delegates to UatExecutionService (03 §3).
 */
public without sharing class Test_Book_Item_TriggerHandler {

    public void isAfterInsert(List<Test_Book_Item__c> rows) {
        UatExecutionService.materializeSlots(UatScopeService.cycleIdsUsingBooks(bookIds(rows)));
    }

    public void isAfterDelete(List<Test_Book_Item__c> rows) {
        UatExecutionService.cleanupPristineSlots(UatScopeService.cycleIdsUsingBooks(bookIds(rows)));
    }

    private Set<Id> bookIds(List<Test_Book_Item__c> rows) {
        Set<Id> ids = new Set<Id>();
        for (Test_Book_Item__c row : rows) {
            ids.add(row.Test_Book__c);
        }
        return ids;
    }
}