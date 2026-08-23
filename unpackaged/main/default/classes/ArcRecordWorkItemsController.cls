/**
 * Author: Claude
 * Date: 2026-08-17
 *
 * The cases and tasks that belong to one contact or household, for the Related
 * Work card on the Experience Cloud account detail page.
 *
 * Conventions:
 * - `with sharing`, plus an explicit CRUD guard per entry point. Sharing alone
 *   is not treated as sufficient in this codebase — FLS/CRUD is checked on top.
 * - Both queries run WITH USER_MODE and carry a LIMIT backed by a named
 *   constant. No SOQL inside a loop.
 * - Wrappers, not raw sObjects, are returned to the LWC.
 */
public with sharing class ArcRecordWorkItemsController {
  /**
   * A card, not a list page: enough rows to be useful with a "View all" out to
   * the real list when there are more.
   */
  private static final Integer ROW_LIMIT = 10;

  /**
   * One more than ROW_LIMIT is fetched so "showing 10 of more" can be told from
   * "showing 10 of exactly 10" without a second COUNT() query.
   */
  private static final Integer FETCH_LIMIT = 11;

  @AuraEnabled(cacheable=true)
  public static WorkItems getWorkItems(Id recordId) {
    if (recordId == null) {
      throw new AuraHandledException('Record Id is required.');
    }

    WorkItems result = new WorkItems();
    result.cases = queryCases(recordId);
    result.tasks = queryTasks(recordId, resolvePersonContactId(recordId));
    return result;
  }

  /**
   * The Contact behind a person account, or null for a business account or
   * household. Task.WhoId points at a Contact, and Task.Who is polymorphic, so
   * the contact has to be resolved here rather than traversed in the query.
   */
  private static Id resolvePersonContactId(Id recordId) {
    if (
      recordId.getSObjectType() != Account.SObjectType ||
      !Schema.sObjectType.Account.isAccessible()
    ) {
      return null;
    }

    List<Account> rows = [
      SELECT PersonContactId
      FROM Account
      WHERE Id = :recordId
      WITH USER_MODE
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0].PersonContactId;
  }

  /**
   * A case reaches an account three ways: directly, through the contact behind
   * a person account, or through the household. A member's cases and their
   * household's cases are the same conversation to the person reading the page,
   * so all three are included rather than only the direct link.
   */
  private static List<WorkItem> queryCases(Id recordId) {
    if (!Schema.sObjectType.Case.isAccessible()) {
      return new List<WorkItem>();
    }

    List<WorkItem> items = new List<WorkItem>();
    for (Case record : [
      SELECT Id, CaseNumber, Subject, Status, Type, CreatedDate
      FROM Case
      WHERE
        AccountId = :recordId
        OR FinServ__Household__c = :recordId
        OR Contact.AccountId = :recordId
      WITH USER_MODE
      ORDER BY CreatedDate DESC
      LIMIT :FETCH_LIMIT
    ]) {
      WorkItem item = new WorkItem();
      item.id = record.Id;
      item.title = String.isBlank(record.Subject)
        ? record.CaseNumber
        : record.Subject;
      item.subtitle = record.CaseNumber;
      item.status = record.Status;
      item.detail = record.Type;
      item.createdDate = record.CreatedDate;
      items.add(item);
    }
    return items;
  }

  /**
   * Tasks hang off either polymorphic lookup — WhatId for the account itself,
   * WhoId for the contact behind a person account — so both are matched. The
   * contact id is passed in because Task.Who is polymorphic and cannot be
   * traversed to Account in SOQL.
   */
  private static List<WorkItem> queryTasks(Id recordId, Id personContactId) {
    if (!Schema.sObjectType.Task.isAccessible()) {
      return new List<WorkItem>();
    }

    List<WorkItem> items = new List<WorkItem>();
    for (Task record : [
      SELECT Id, Subject, Status, Priority, ActivityDate, CreatedDate
      FROM Task
      WHERE
        WhatId = :recordId
        OR (WhoId != NULL AND WhoId = :personContactId)
      WITH USER_MODE
      ORDER BY CreatedDate DESC
      LIMIT :FETCH_LIMIT
    ]) {
      WorkItem item = new WorkItem();
      item.id = record.Id;
      item.title = record.Subject;
      item.subtitle = record.ActivityDate == null
        ? null
        : record.ActivityDate.format();
      item.status = record.Status;
      item.detail = record.Priority;
      item.createdDate = record.CreatedDate;
      items.add(item);
    }
    return items;
  }

  // ---- Wrappers exposed to LWC ------------------------------------------

  public class WorkItems {
    @AuraEnabled
    public List<WorkItem> cases;

    @AuraEnabled
    public List<WorkItem> tasks;
  }

  public class WorkItem {
    @AuraEnabled
    public Id id;

    @AuraEnabled
    public String title;

    @AuraEnabled
    public String subtitle;

    @AuraEnabled
    public String status;

    @AuraEnabled
    public String detail;

    @AuraEnabled
    public Datetime createdDate;
  }
}