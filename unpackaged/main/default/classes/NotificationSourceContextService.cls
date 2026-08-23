/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-16
 *
 * Resolves household name, source detail, target record id, and notification title/body
 * for delivery and inbox display. Mirrors Notification_Resolve_Source_Context flow logic.
 */
public without sharing class NotificationSourceContextService {
  public class ResolveResult {
    @AuraEnabled
    public String householdName { get; private set; }
    @AuraEnabled
    public String sourceDetail { get; private set; }
    @AuraEnabled
    public String targetRecordId { get; private set; }
    @AuraEnabled
    public String title { get; private set; }
    @AuraEnabled
    public String body { get; private set; }

    public ResolveResult(
      String householdName,
      String sourceDetail,
      String targetRecordId,
      String title,
      String body
    ) {
      this.householdName = householdName;
      this.sourceDetail = sourceDetail;
      this.targetRecordId = targetRecordId;
      this.title = title;
      this.body = body;
    }
  }

  public static ResolveResult resolve(
    String sourceType,
    String sourceRecordId,
    Id householdId
  ) {
    String householdName = resolveHouseholdName(householdId);
    String sourceDetail = resolveSourceDetail(sourceType, sourceRecordId);
    String targetRecordId = resolveTargetRecordId(sourceRecordId, householdId);
    String title = buildTitle(sourceType, householdName);
    String body = buildBody(sourceType, householdName, sourceDetail);

    return new ResolveResult(
      householdName,
      sourceDetail,
      targetRecordId,
      title,
      body
    );
  }

  private static String resolveHouseholdName(Id householdId) {
    if (householdId == null) {
      return 'this household';
    }

    List<Account> households = [
      SELECT Name
      FROM Account
      WHERE Id = :householdId
      LIMIT 1
    ];

    if (households.isEmpty() || String.isBlank(households[0].Name)) {
      return 'this household';
    }

    return households[0].Name;
  }

  private static String resolveSourceDetail(
    String sourceType,
    String sourceRecordId
  ) {
    if (String.isBlank(sourceType)) {
      return 'Open the notification to view the new record.';
    }

    if (sourceType == NotificationConstants.OBJECT_TYPE_CASE) {
      return resolveCaseDetail(sourceRecordId);
    }

    if (sourceType == NotificationConstants.OBJECT_TYPE_TASK) {
      return resolveTaskDetail(sourceRecordId);
    }

    if (sourceType == NotificationConstants.OBJECT_TYPE_EVENT) {
      return resolveEventDetail(sourceRecordId);
    }

    return 'Open the notification to view the new record.';
  }

  private static String resolveCaseDetail(String sourceRecordId) {
    if (String.isBlank(sourceRecordId)) {
      return 'Case details unavailable';
    }

    List<Case> cases = [
      SELECT CaseNumber, Subject
      FROM Case
      WHERE Id = :sourceRecordId
      LIMIT 1
    ];

    if (cases.isEmpty()) {
      return 'Case details unavailable';
    }

    Case caseRecord = cases[0];
    if (String.isBlank(caseRecord.Subject)) {
      return caseRecord.CaseNumber;
    }

    return caseRecord.CaseNumber + ' - ' + caseRecord.Subject;
  }

  private static String resolveTaskDetail(String sourceRecordId) {
    if (String.isBlank(sourceRecordId)) {
      return 'Task details unavailable';
    }

    List<Task> tasks = [
      SELECT Subject
      FROM Task
      WHERE Id = :sourceRecordId
      LIMIT 1
    ];

    if (tasks.isEmpty()) {
      return 'Task details unavailable';
    }

    return String.isBlank(tasks[0].Subject) ? 'New task' : tasks[0].Subject;
  }

  private static String resolveEventDetail(String sourceRecordId) {
    if (String.isBlank(sourceRecordId)) {
      return 'Event details unavailable';
    }

    List<Event> events = [
      SELECT Subject
      FROM Event
      WHERE Id = :sourceRecordId
      LIMIT 1
    ];

    if (events.isEmpty()) {
      return 'Event details unavailable';
    }

    return String.isBlank(events[0].Subject) ? 'New event' : events[0].Subject;
  }

  private static String resolveTargetRecordId(
    String sourceRecordId,
    Id householdId
  ) {
    if (!String.isBlank(sourceRecordId)) {
      return sourceRecordId;
    }

    return householdId == null ? null : String.valueOf(householdId);
  }

  private static String resolveObjectLabel(String sourceType) {
    if (sourceType == NotificationConstants.OBJECT_TYPE_CASE) {
      return 'case';
    }

    if (sourceType == NotificationConstants.OBJECT_TYPE_TASK) {
      return 'task';
    }

    if (sourceType == NotificationConstants.OBJECT_TYPE_EVENT) {
      return 'event';
    }

    return String.isBlank(sourceType) ? 'record' : sourceType.toLowerCase();
  }

  private static String buildTitle(String sourceType, String householdName) {
    return 'New ' + resolveObjectLabel(sourceType);
  }

  private static String buildBody(
    String sourceType,
    String householdName,
    String sourceDetail
  ) {
    return 'New ' +
      resolveObjectLabel(sourceType) +
      ' created for ' +
      householdName;
  }
}