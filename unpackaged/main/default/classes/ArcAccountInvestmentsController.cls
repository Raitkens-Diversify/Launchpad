/**
 * Investments & Services tab on the Account/Household/Business/Trust/
 * Retirement Plan detail page (arcHouseholdDetail): every ISA
 * (Financial_Account__c), Service (Service__c), and Approved Product
 * (Product__c) tied to this record, normalized into one list tagged with its
 * type, for a simple Name + Type table.
 *
 * ISAs and Services both roll up to a household (Household__c) or are owned
 * directly (Primary_Owner__c, excluded from Household record types by the
 * field's own lookup filter) -- a Household record only ever matches the
 * first clause, everything else potentially both. Product__c relates to an
 * Account directly through Account__c.
 *
 * Each query is capped rather than paginated -- a client's own investments
 * and services are not expected to run into the hundreds (mirrors
 * WorkDatatableController.ROW_LIMIT's precedent: a safe ceiling, not a real
 * page size) -- and the combined, sorted list is paginated client-side by
 * arcDataTable itself, the same pattern this codebase already uses for
 * workTable.
 */
public with sharing class ArcAccountInvestmentsController {
  private static final Integer ROW_LIMIT = 200;

  @AuraEnabled(cacheable=true)
  public static List<InvestmentRow> getInvestmentsAndServices(Id accountId) {
    List<InvestmentRow> rows = new List<InvestmentRow>();
    if (accountId == null) {
      return rows;
    }

    for (Financial_Account__c account : [
      SELECT Id, Name
      FROM Financial_Account__c
      WHERE Household__c = :accountId OR Primary_Owner__c = :accountId
      WITH USER_MODE
      ORDER BY Name
      LIMIT :ROW_LIMIT
    ]) {
      rows.add(new InvestmentRow(account.Id, account.Name, 'Account', 'Financial_Account__c'));
    }

    for (Service__c service : [
      SELECT Id, Name
      FROM Service__c
      WHERE Household__c = :accountId OR Primary_Owner__c = :accountId
      WITH USER_MODE
      ORDER BY Name
      LIMIT :ROW_LIMIT
    ]) {
      rows.add(new InvestmentRow(service.Id, service.Name, 'Service', 'Service__c'));
    }

    for (Product__c product : [
      SELECT Id, Name
      FROM Product__c
      WHERE Account__c = :accountId
      WITH USER_MODE
      ORDER BY Name
      LIMIT :ROW_LIMIT
    ]) {
      rows.add(new InvestmentRow(product.Id, product.Name, 'Approved Product', 'Product__c'));
    }

    rows.sort(new InvestmentRowNameComparator());
    return rows;
  }

  public class InvestmentRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String typeLabel;
    @AuraEnabled
    public String objectApiName;

    public InvestmentRow(Id id, String name, String typeLabel, String objectApiName) {
      this.id = id;
      this.name = name;
      this.typeLabel = typeLabel;
      this.objectApiName = objectApiName;
    }
  }

  private class InvestmentRowNameComparator implements System.Comparator<InvestmentRow> {
    public Integer compare(InvestmentRow left, InvestmentRow right) {
      String leftName = left.name == null ? '' : left.name;
      String rightName = right.name == null ? '' : right.name;
      return leftName.compareTo(rightName);
    }
  }
}