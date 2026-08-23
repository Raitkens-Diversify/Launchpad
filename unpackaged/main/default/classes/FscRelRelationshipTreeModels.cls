/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-14
 *
 * Data transfer objects for shared household relationship tree reads.
 */
public class FscRelRelationshipTreeModels {
  public class ScopedAccountSummary {
    @AuraEnabled
    public String accountId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Boolean isHouseholdRelated;

    public ScopedAccountSummary() {
      this.isHouseholdRelated = false;
    }
  }

  public class GroupedAccountContacts {
    @AuraEnabled
    public String category;
    @AuraEnabled
    public List<ScopedAccountSummary> contacts;

    public GroupedAccountContacts() {
      this.contacts = new List<ScopedAccountSummary>();
    }
  }
}