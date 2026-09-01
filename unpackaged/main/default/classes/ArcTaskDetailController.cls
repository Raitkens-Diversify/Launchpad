/**
 * Task-specific context and related-list data for ARC's Task detail page.
 *
 * Field-level rendering for Task already comes from the generic
 * Envelope_Field__mdt pipeline (ArcRecordDetailController/FieldDetailController).
 * This controller only supplies what that generic pipeline does not: the
 * task's own What/Who/Owner context (for gating the action buttons) and the
 * "Open Activities for Parent Case" related list, which needs to resolve the
 * task's WhatId to a Case before it can query siblings.
 */
public with sharing class ArcTaskDetailController {
  // Mirrors ArcRecordDetailController.NAME_FIELD_BY_OBJECT for the same reason:
  // a lookup's stored value is an id, and What/WhoId are polymorphic, so the
  // display name has to be resolved against whichever object the id actually
  // belongs to. Everything nameable answers to Name; Case does not.
  private static final Map<String, String> NAME_FIELD_BY_OBJECT = new Map<String, String>{
    'Case' => 'CaseNumber'
  };

  @AuraEnabled(cacheable=true)
  public static TaskContext getTaskContext(Id taskId) {
    TaskContext context = new TaskContext();
    if (taskId == null) {
      return context;
    }

    List<Task> matches = [
      SELECT WhatId, WhoId, OwnerId, Status, Subject, Priority, ActivityDate
      FROM Task
      WHERE Id = :taskId
      WITH USER_MODE
      LIMIT 1
    ];
    if (matches.isEmpty()) {
      return context;
    }

    Task record = matches[0];
    context.whatId = record.WhatId;
    context.whoId = record.WhoId;
    context.ownerId = record.OwnerId;
    context.status = record.Status;
    context.subject = record.Subject;
    context.priority = record.Priority;
    context.dueDate = record.ActivityDate;
    context.isParentCase = isCaseId(record.WhatId);

    if (record.WhatId != null) {
      Schema.DescribeSObjectResult whatDescribe = record.WhatId.getSObjectType()
        .getDescribe();
      context.whatObjectApiName = whatDescribe.getName();
      context.whatObjectLabel = whatDescribe.getLabel();
      context.whatName = resolveDisplayName(record.WhatId, context.whatObjectApiName);
    }
    if (record.WhoId != null) {
      context.whoObjectApiName = record.WhoId.getSObjectType().getDescribe().getName();
      context.whoName = resolveDisplayName(record.WhoId, context.whoObjectApiName);
    }

    return context;
  }

  private static String resolveDisplayName(Id recordId, String objectName) {
    if (recordId == null || String.isBlank(objectName)) {
      return null;
    }

    String nameField = NAME_FIELD_BY_OBJECT.containsKey(objectName)
      ? NAME_FIELD_BY_OBJECT.get(objectName)
      : 'Name';

    Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectName);
    if (
      objectType == null ||
      !objectType.getDescribe().fields.getMap().containsKey(nameField)
    ) {
      return null;
    }

    String soql =
      'SELECT ' + nameField + ' FROM ' + objectName + ' WHERE Id = :recordId WITH USER_MODE LIMIT 1';
    try {
      List<SObject> rows = Database.query(soql);
      if (rows.isEmpty()) {
        return null;
      }
      Object value = rows[0].get(nameField);
      return value != null ? String.valueOf(value) : null;
    } catch (Exception e) {
      return null;
    }
  }

  /**
   * Open Cases sharing the same household as this Task (Task.FinServ__Household__c
   * is a direct lookup on Activity, not a hop through the parent Case).
   */
  @AuraEnabled(cacheable=true)
  public static List<ArcCaseDetailController.RelatedCaseInfo> getOpenCasesForHousehold(
    Id taskId
  ) {
    List<ArcCaseDetailController.RelatedCaseInfo> results = new List<ArcCaseDetailController.RelatedCaseInfo>();
    if (taskId == null) {
      return results;
    }

    List<Task> matches = [
      SELECT FinServ__Household__c
      FROM Task
      WHERE Id = :taskId
      WITH USER_MODE
      LIMIT 1
    ];
    if (matches.isEmpty() || matches[0].FinServ__Household__c == null) {
      return results;
    }

    Id householdId = matches[0].FinServ__Household__c;

    for (Case record : [
      SELECT Id, CaseNumber, Subject, Status, Owner.Name, CreatedDate
      FROM Case
      WHERE Household__c = :householdId AND IsClosed = false
      WITH USER_MODE
      ORDER BY CreatedDate DESC
      LIMIT 20
    ]) {
      ArcCaseDetailController.RelatedCaseInfo info = new ArcCaseDetailController.RelatedCaseInfo();
      info.id = record.Id;
      info.caseNumber = record.CaseNumber;
      info.subject = record.Subject;
      info.status = record.Status;
      info.ownerName = record.Owner != null ? record.Owner.Name : null;
      info.createdDate = record.CreatedDate;
      results.add(info);
    }

    return results;
  }

  /**
   * Other open Tasks under the same parent Case as the given Task (the
   * current Task included, if it is itself still open) -- mirrors
   * ArcCaseDetailController.getCaseTasks, filtered to open only, starting
   * from a Task rather than the Case itself.
   */
  @AuraEnabled(cacheable=true)
  public static List<ArcCaseDetailController.TaskInfo> getOpenActivitiesForParentCase(
    Id taskId
  ) {
    List<ArcCaseDetailController.TaskInfo> results = new List<ArcCaseDetailController.TaskInfo>();
    if (taskId == null) {
      return results;
    }

    List<Task> matches = [
      SELECT WhatId
      FROM Task
      WHERE Id = :taskId
      WITH USER_MODE
      LIMIT 1
    ];
    if (matches.isEmpty() || !isCaseId(matches[0].WhatId)) {
      return results;
    }

    Id caseId = matches[0].WhatId;

    for (Task record : [
      SELECT
        Id,
        Subject,
        Status,
        Owner.Name,
        ActivityDate,
        CompletedDateTime,
        IsClosed,
        Branch_Pit_Stop__c,
        Home_Office_Pit_Stop__c
      FROM Task
      WHERE WhatId = :caseId AND IsClosed = false
      WITH USER_MODE
      ORDER BY ActivityDate ASC NULLS LAST, CreatedDate ASC
      LIMIT 200
    ]) {
      ArcCaseDetailController.TaskInfo info = new ArcCaseDetailController.TaskInfo();
      info.id = record.Id;
      info.subject = record.Subject;
      info.status = record.Status;
      info.ownerName = record.Owner != null ? record.Owner.Name : null;
      info.dueDate = record.ActivityDate;
      info.completedDate = record.CompletedDateTime;
      info.branchPitStop = record.Branch_Pit_Stop__c == true;
      info.homeOfficePitStop = record.Home_Office_Pit_Stop__c == true;
      info.isClosed = record.IsClosed == true;
      results.add(info);
    }

    return results;
  }

  /**
   * Open activities (tasks and events together) on the task's parent record,
   * for parents that are not Cases -- the Lightning task page shows this as
   * the parent's own OpenActivities related list (relatedListSingleContainer
   * on Task.WhatId), titled "Open Activities for Parent Financial Account"
   * there because a financial account is what a wizard task hangs off.
   * Case parents keep getOpenActivitiesForParentCase, whose pit-stop columns
   * this generic list has no equivalent of.
   *
   * Queried through the parent's OpenActivities child relationship so tasks
   * and events arrive merged and ordered the way the platform merges them.
   * A parent object with activities disabled fails that subquery; that comes
   * back as an empty list rather than an error, since "no activities to
   * show" is exactly what such a page should say.
   */
  @AuraEnabled(cacheable=true)
  public static List<OpenActivityInfo> getOpenActivitiesForParent(Id taskId) {
    List<OpenActivityInfo> results = new List<OpenActivityInfo>();
    if (taskId == null) {
      return results;
    }

    List<Task> matches = [
      SELECT WhatId
      FROM Task
      WHERE Id = :taskId
      WITH USER_MODE
      LIMIT 1
    ];
    if (matches.isEmpty() || matches[0].WhatId == null || isCaseId(matches[0].WhatId)) {
      return results;
    }

    Id whatId = matches[0].WhatId;
    String objectName = whatId.getSObjectType().getDescribe().getName();

    List<SObject> parents;
    try {
      parents = Database.query(
        'SELECT Id, (SELECT Id, Subject, Who.Name, IsTask, ActivityDate' +
          ' FROM OpenActivities' +
          ' ORDER BY ActivityDate ASC NULLS LAST LIMIT 50)' +
          ' FROM ' + objectName +
          ' WHERE Id = :whatId WITH USER_MODE LIMIT 1'
      );
    } catch (Exception e) {
      return results;
    }
    if (parents.isEmpty()) {
      return results;
    }

    List<OpenActivity> activities = parents[0].getSObjects('OpenActivities') == null
      ? new List<OpenActivity>()
      : (List<OpenActivity>) parents[0].getSObjects('OpenActivities');
    for (OpenActivity activity : activities) {
      OpenActivityInfo info = new OpenActivityInfo();
      info.id = activity.Id;
      info.subject = activity.Subject;
      info.whoName = activity.Who != null ? activity.Who.Name : null;
      info.isTask = activity.IsTask == true;
      info.dueDate = activity.ActivityDate;
      results.add(info);
    }

    return results;
  }

  private static Boolean isCaseId(Id value) {
    return value != null && value.getSObjectType() == Case.SObjectType;
  }

  public class OpenActivityInfo {
    @AuraEnabled
    public Id id;

    @AuraEnabled
    public String subject;

    /** The activity's Who (contact/lead) display name; null when unset. */
    @AuraEnabled
    public String whoName;

    /** True for a task, false for an event -- the checkbox column. */
    @AuraEnabled
    public Boolean isTask;

    @AuraEnabled
    public Date dueDate;
  }

  public class TaskContext {
    @AuraEnabled
    public Id whatId;

    @AuraEnabled
    public String whatName;

    @AuraEnabled
    public String whatObjectApiName;

    /** The parent object's label, for "Open Activities for Parent <label>". */
    @AuraEnabled
    public String whatObjectLabel;

    @AuraEnabled
    public Id whoId;

    @AuraEnabled
    public String whoName;

    @AuraEnabled
    public String whoObjectApiName;

    @AuraEnabled
    public Id ownerId;

    @AuraEnabled
    public String status;

    @AuraEnabled
    public String priority;

    @AuraEnabled
    public Date dueDate;

    @AuraEnabled
    public String subject;

    @AuraEnabled
    public Boolean isParentCase = false;
  }
}