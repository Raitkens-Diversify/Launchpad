/**
 * Display identity (Name + account number) for FinServ__FinancialAccount__c
 * ids, resolved in system mode.
 *
 * The ARC portal profile has no object permission on the FinServ financial
 * account, and the object's external sharing model is Private, so every
 * USER_MODE / with-sharing read of it returns nothing for a portal user.
 * Records portal users CAN read (check logs, check deposits, order tickets)
 * still point at FinServ accounts, and the Lightning app shows those users
 * the account's name wherever the lookup appears — ARC showing a blank for
 * the same field is the bug, not the permission model.
 *
 * `without sharing` is deliberate and narrowly scoped. The contract:
 *  - Callers pass only ids they read off records the current user already
 *    accessed under USER_MODE — this class never widens which *records* a
 *    user can discover, only labels ids they legitimately hold.
 *  - Only Name and FinServ__FinancialAccountNumber__c leave this class.
 *    No balances, no ownership, no other fields — add nothing here without
 *    the same scrutiny.
 *  - Not @AuraEnabled. The client cannot call this directly.
 */
public without sharing class ArcFinServAccountLabels {
  public class Entry {
    public String name;
    public String accountNumber;
  }

  /** Name + account number per id; ids that resolve to nothing are absent. */
  public static Map<Id, Entry> resolve(Set<Id> financialAccountIds) {
    Map<Id, Entry> labelsById = new Map<Id, Entry>();
    if (financialAccountIds == null || financialAccountIds.isEmpty()) {
      return labelsById;
    }

    for (FinServ__FinancialAccount__c account : [
      SELECT Id, Name, FinServ__FinancialAccountNumber__c
      FROM FinServ__FinancialAccount__c
      WHERE Id IN :financialAccountIds
    ]) {
      Entry entry = new Entry();
      entry.name = account.Name;
      entry.accountNumber = account.FinServ__FinancialAccountNumber__c;
      labelsById.put(account.Id, entry);
    }
    return labelsById;
  }
}