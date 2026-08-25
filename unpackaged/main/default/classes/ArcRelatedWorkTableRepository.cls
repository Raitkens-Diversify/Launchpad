/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-11
 *
 * Case and Task queries for arcRelatedTable Work mode.
 */
public with sharing class ArcRelatedWorkTableRepository {
  private static final Integer ROW_LIMIT = 500;

  private final FinancialAdvisorTeamAccessService teamAccessService;

  public ArcRelatedWorkTableRepository() {
    this(new FinancialAdvisorTeamAccessService());
  }

  public ArcRelatedWorkTableRepository(
    FinancialAdvisorTeamAccessService teamAccessService
  ) {
    this.teamAccessService = teamAccessService;
  }

  public ArcRelatedTableModels.TableData selectRows(
    ArcRelatedTableScope.Value scope
  ) {
    ArcRelatedTableModels.TableData data = new ArcRelatedTableModels.TableData();
    Id currentUserId = UserInfo.getUserId();
    FinancialAdvisorTeamAccessService.TeamAccessContext teamAccess = teamAccessService.getCurrentUserTeamAccess();

    List<ArcRelatedTableModels.TableRow> rows = new List<ArcRelatedTableModels.TableRow>();
    rows.addAll(selectCaseRows(scope, currentUserId, teamAccess));
    rows.addAll(selectTaskRows(scope, currentUserId, teamAccess));

    rows.sort(new WorkRowComparator());
    if (rows.size() > ROW_LIMIT) {
      List<ArcRelatedTableModels.TableRow> trimmed = new List<ArcRelatedTableModels.TableRow>();
      for (Integer index = 0; index < ROW_LIMIT; index++) {
        trimmed.add(rows[index]);
      }
      rows = trimmed;
    }

    data.rows = rows;
    data.totalCount = rows.size();
    return data;
  }

  private List<ArcRelatedTableModels.TableRow> selectCaseRows(
    ArcRelatedTableScope.Value scope,
    Id currentUserId,
    FinancialAdvisorTeamAccessService.TeamAccessContext teamAccess
  ) {
    List<Case> caseRecords;
    if (scope == ArcRelatedTableScope.Value.MINE) {
      caseRecords = [
        SELECT
          Id,
          Subject,
          Status,
          OwnerId,
          Owner.Name,
          LastModifiedDate,
          Financial_Advisor_Team__c,
          AccountId,
          Account.Name,
          Total_Main_Track_Tasks__c,
          Completed_Main_Track_Tasks__c
        FROM Case
        WHERE OwnerId = :currentUserId
        WITH SECURITY_ENFORCED
        ORDER BY LastModifiedDate DESC
        LIMIT :ROW_LIMIT
      ];
    } else if (teamAccess.teamIds.isEmpty()) {
      caseRecords = new List<Case>();
    } else {
      caseRecords = [
        SELECT
          Id,
          Subject,
          Status,
          OwnerId,
          Owner.Name,
          LastModifiedDate,
          Financial_Advisor_Team__c,
          AccountId,
          Account.Name,
          Total_Main_Track_Tasks__c,
          Completed_Main_Track_Tasks__c
        FROM Case
        WHERE Financial_Advisor_Team__c IN :teamAccess.teamIds
        WITH SECURITY_ENFORCED
        ORDER BY LastModifiedDate DESC
        LIMIT :ROW_LIMIT
      ];
    }

    List<ArcRelatedTableModels.TableRow> rows = new List<ArcRelatedTableModels.TableRow>();
    for (Case caseRecord : caseRecords) {
      rows.add(mapCaseRow(caseRecord));
    }
    return rows;
  }

  private List<ArcRelatedTableModels.TableRow> selectTaskRows(
    ArcRelatedTableScope.Value scope,
    Id currentUserId,
    FinancialAdvisorTeamAccessService.TeamAccessContext teamAccess
  ) {
    Set<Id> ownerIds = scope == ArcRelatedTableScope.Value.MINE
      ? new Set<Id>{ currentUserId }
      : teamAccess.teamMemberUserIds;

    if (ownerIds.isEmpty()) {
      return new List<ArcRelatedTableModels.TableRow>();
    }

    List<Task> taskRecords = [
      SELECT
        Id,
        Subject,
        Status,
        OwnerId,
        Owner.Name,
        ActivityDate,
        LastModifiedDate,
        WhatId,
        WhoId
      FROM Task
      WHERE OwnerId IN :ownerIds AND IsClosed = FALSE
      WITH SECURITY_ENFORCED
      ORDER BY ActivityDate DESC NULLS LAST, LastModifiedDate DESC
      LIMIT :ROW_LIMIT
    ];

    Map<Id, String> relatedLabelByWhatId = resolveRelatedLabels(taskRecords);
    List<ArcRelatedTableModels.TableRow> rows = new List<ArcRelatedTableModels.TableRow>();
    for (Task taskRecord : taskRecords) {
      rows.add(mapTaskRow(taskRecord, relatedLabelByWhatId));
    }
    return rows;
  }

  private static Map<Id, String> resolveRelatedLabels(List<Task> taskRecords) {
    Map<Id, String> labelByWhatId = new Map<Id, String>();
    Set<Id> caseIds = new Set<Id>();
    Set<Id> accountIds = new Set<Id>();

    for (Task taskRecord : taskRecords) {
      if (taskRecord.WhatId == null) {
        continue;
      }

      Schema.SObjectType sobjectType = taskRecord.WhatId.getSObjectType();
      if (sobjectType == Case.SObjectType) {
        caseIds.add(taskRecord.WhatId);
      } else if (sobjectType == Account.SObjectType) {
        accountIds.add(taskRecord.WhatId);
      }
    }

    if (!caseIds.isEmpty()) {
      for (Case caseRecord : [
        SELECT Id, CaseNumber, Subject
        FROM Case
        WHERE Id IN :caseIds
        WITH SECURITY_ENFORCED
      ]) {
        labelByWhatId.put(
          caseRecord.Id,
          String.isNotBlank(caseRecord.CaseNumber)
            ? caseRecord.CaseNumber
            : caseRecord.Subject
        );
      }
    }

    if (!accountIds.isEmpty()) {
      for (Account accountRecord : [
        SELECT Id, Name
        FROM Account
        WHERE Id IN :accountIds
        WITH SECURITY_ENFORCED
      ]) {
        labelByWhatId.put(accountRecord.Id, accountRecord.Name);
      }
    }

    return labelByWhatId;
  }

  private static ArcRelatedTableModels.TableRow mapCaseRow(Case caseRecord) {
    ArcRelatedTableModels.TableRow row = new ArcRelatedTableModels.TableRow();
    row.id = String.valueOf(caseRecord.Id);
    row.recordType = 'Case';
    row.subject = caseRecord.Subject;
    row.status = caseRecord.Status;
    row.ownerName = caseRecord.Owner?.Name;
    row.relatedTo = caseRecord.Account?.Name;
    row.activityDateRaw = caseRecord.LastModifiedDate;
    row.activityDate = formatDateTime(caseRecord.LastModifiedDate);
    applyMainTrackTasks(row, caseRecord);
    return row;
  }

  private static void applyMainTrackTasks(
    ArcRelatedTableModels.TableRow row,
    Case caseRecord
  ) {
    Integer totalMain = caseRecord.Total_Main_Track_Tasks__c == null
      ? 0
      : Integer.valueOf(caseRecord.Total_Main_Track_Tasks__c);
    Integer completedMain = caseRecord.Completed_Main_Track_Tasks__c == null
      ? 0
      : Integer.valueOf(caseRecord.Completed_Main_Track_Tasks__c);

    row.totalMainTrack = totalMain;
    row.completedMainTrack = completedMain;
    row.mainTrackTasks = completedMain + ' / ' + totalMain;
  }

  private static ArcRelatedTableModels.TableRow mapTaskRow(
    Task taskRecord,
    Map<Id, String> relatedLabelByWhatId
  ) {
    ArcRelatedTableModels.TableRow row = new ArcRelatedTableModels.TableRow();
    row.id = String.valueOf(taskRecord.Id);
    row.recordType = 'Task';
    row.subject = taskRecord.Subject;
    row.status = taskRecord.Status;
    row.ownerName = taskRecord.Owner?.Name;
    row.relatedTo = taskRecord.WhatId == null
      ? ''
      : relatedLabelByWhatId.get(taskRecord.WhatId);
    Datetime activityDateTime = taskRecord.ActivityDate == null
      ? taskRecord.LastModifiedDate
      : Datetime.newInstance(taskRecord.ActivityDate, Time.newInstance(0, 0, 0, 0));
    row.activityDateRaw = activityDateTime;
    row.activityDate = formatDate(taskRecord.ActivityDate, taskRecord.LastModifiedDate);
    return row;
  }

  private static String formatDate(Date activityDate, Datetime fallbackDateTime) {
    if (activityDate != null) {
      return Datetime.newInstance(activityDate, Time.newInstance(0, 0, 0, 0))
        .format('MMM d, yyyy');
    }

    return formatDateTime(fallbackDateTime);
  }

  private static String formatDateTime(Datetime value) {
    if (value == null) {
      return '';
    }

    return value.format('MMM d, yyyy HH:mm');
  }

  private class WorkRowComparator implements Comparator<ArcRelatedTableModels.TableRow> {
    public Integer compare(
      ArcRelatedTableModels.TableRow first,
      ArcRelatedTableModels.TableRow second
    ) {
      Datetime firstDate = first?.activityDateRaw;
      Datetime secondDate = second?.activityDateRaw;

      if (firstDate == null && secondDate == null) {
        return 0;
      }
      if (firstDate == null) {
        return 1;
      }
      if (secondDate == null) {
        return -1;
      }
      if (firstDate == secondDate) {
        return 0;
      }

      return firstDate > secondDate ? -1 : 1;
    }
  }
}