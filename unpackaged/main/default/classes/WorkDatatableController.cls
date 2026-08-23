/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-11
 *
 * Case work list for workTable. All row values come from Case fields.
 * Scope: My (Case OwnerId) or My Team (Case Financial_Advisor_Team__c membership).
 */
public with sharing class WorkDatatableController {
  private static final Integer ROW_LIMIT = 500;
  private static final Integer QUERY_CHUNK_SIZE = 200;
  private static final Integer SOQL_LIMIT_BUFFER = 1;

  private static final String PILL_BASE = 'div-work-pill';
  private static final String PILL_ON_TRACK = PILL_BASE + ' div-work-pill--on-track';
  private static final String PILL_COMPLETED = PILL_BASE + ' div-work-pill--completed';
  private static final String PILL_NOT_STARTED = PILL_BASE + ' div-work-pill--not-started';
  private static final String PILL_HO_SUBMISSION = PILL_BASE + ' div-work-pill--ho-submission';

  private static final Set<String> CASE_FIELDS = new Set<String>{
    'Id',
    'CaseNumber',
    'Case_Branch_Name_DisplayName__c',
    'OwnerId',
    'Owner.Name',
    'LastModifiedDate',
    'Financial_Advisor_Team__c',
    'Total_Main_Track_Tasks__c',
    'Completed_Main_Track_Tasks__c',
    'Main_Track_Task_Completion_Ratio__c',
    'Current_Task_Status__c',
    'Current_Task_Subject_Assignee__c',
    'Owner_Group__c',
    'Number_of_Open_Tasks__c',
    'MilestoneStatus'
  };

  @AuraEnabled(cacheable=true)
  public static WorkDatatableModels.WorkDatatableData getWorkData(String scope) {
    ARCConstants.RelatedTableScope resolvedScope = ARCUtil.relatedTableScopeFromValue(
      scope
    );
    Id currentUserId = UserInfo.getUserId();
    FinancialAdvisorTeamAccessService.TeamAccessContext teamAccess = new FinancialAdvisorTeamAccessService()
      .getCurrentUserTeamAccess();

    List<Case> caseRecords = selectCases(resolvedScope, currentUserId, teamAccess);
    Map<Id, List<Task>> tasksByCaseId = selectTasksByCaseId(caseRecords);

    WorkDatatableModels.WorkDatatableData data = new WorkDatatableModels.WorkDatatableData();
    for (Case caseRecord : caseRecords) {
      List<Task> caseTasks = tasksByCaseId.get(caseRecord.Id);
      data.cases.add(mapCaseRow(caseRecord, caseTasks));
    }
    data.totalCount = data.cases.size();
    return data;
  }

  private static List<Case> selectCases(
    ARCConstants.RelatedTableScope scope,
    Id currentUserId,
    FinancialAdvisorTeamAccessService.TeamAccessContext teamAccess
  ) {
    String caseFields = String.join(new List<String>(CASE_FIELDS), ', ');

    if (scope == ARCConstants.RelatedTableScope.MINE) {
      return Database.query(
        'SELECT ' +
          caseFields +
          ' FROM Case WHERE OwnerId = :currentUserId AND IsClosed = FALSE' +
          ' WITH SECURITY_ENFORCED ORDER BY LastModifiedDate DESC LIMIT :ROW_LIMIT'
      );
    }

    if (teamAccess.teamIds.isEmpty()) {
      return new List<Case>();
    }

    Set<Id> teamIds = teamAccess.teamIds;

    return Database.query(
      'SELECT ' +
        caseFields +
        ' FROM Case WHERE Financial_Advisor_Team__c IN :teamIds' +
        ' AND IsClosed = FALSE WITH SECURITY_ENFORCED' +
        ' ORDER BY LastModifiedDate DESC LIMIT :ROW_LIMIT'
    );
  }

  private static Map<Id, List<Task>> selectTasksByCaseId(List<Case> caseRecords) {
    if (caseRecords.isEmpty()) {
      return new Map<Id, List<Task>>();
    }

    Set<Id> caseIds = new Map<Id, Case>(caseRecords).keySet();
    Map<Id, List<Task>> tasksByCaseId = new Map<Id, List<Task>>();

    if (caseIds.size() <= QUERY_CHUNK_SIZE) {
      return groupTasksByCaseId(queryTasksByCaseIds(caseIds));
    }

    for (Set<Id> caseIdChunk : chunkIdSet(caseIds)) {
      if (!canContinueSoqlWork(SOQL_LIMIT_BUFFER)) {
        break;
      }

      mergeTasksByCaseId(tasksByCaseId, queryTasksByCaseIds(caseIdChunk));
    }

    return tasksByCaseId;
  }

  private static List<Task> queryTasksByCaseIds(Set<Id> caseIds) {
    if (caseIds == null || caseIds.isEmpty()) {
      return new List<Task>();
    }

    return [
      SELECT
        Id,
        Subject,
        Status,
        Owner.Name,
        ActivityDate,
        CompletedDateTime,
        Completed_Date__c,
        WhatId,
        Order__c,
        CreatedDate,
        Branch_Pit_Stop__c,
        Home_Office_Pit_Stop__c,
        Task_Template_Item__r.Home_Office_Goal_Milestone__c,
        Task_Template_Item__r.Home_Office_Submission_Milestone__c,
        Task_Template_Item__r.Branch_Goal_Milestone__c,
        Task_Template_Item__r.Home_Office_Approval_Milestone__c
      FROM Task
      WHERE WhatId IN :caseIds
      WITH SECURITY_ENFORCED
    ];
  }

  private static Map<Id, List<Task>> groupTasksByCaseId(List<Task> taskRecords) {
    Map<Id, List<Task>> tasksByCaseId = new Map<Id, List<Task>>();

    for (Task taskRecord : taskRecords) {
      if (!tasksByCaseId.containsKey(taskRecord.WhatId)) {
        tasksByCaseId.put(taskRecord.WhatId, new List<Task>());
      }
      tasksByCaseId.get(taskRecord.WhatId).add(taskRecord);
    }

    return tasksByCaseId;
  }

  private static void mergeTasksByCaseId(
    Map<Id, List<Task>> tasksByCaseId,
    List<Task> taskRecords
  ) {
    for (Task taskRecord : taskRecords) {
      if (!tasksByCaseId.containsKey(taskRecord.WhatId)) {
        tasksByCaseId.put(taskRecord.WhatId, new List<Task>());
      }
      tasksByCaseId.get(taskRecord.WhatId).add(taskRecord);
    }
  }

  private static List<Set<Id>> chunkIdSet(Set<Id> ids) {
    List<Set<Id>> chunks = new List<Set<Id>>();

    if (ids == null || ids.isEmpty()) {
      return chunks;
    }

    List<Id> idList = new List<Id>(ids);
    for (Integer index = 0; index < idList.size(); index += QUERY_CHUNK_SIZE) {
      Set<Id> chunk = new Set<Id>();
      Integer endIndex = Math.min(index + QUERY_CHUNK_SIZE, idList.size());

      for (Integer chunkIndex = index; chunkIndex < endIndex; chunkIndex++) {
        chunk.add(idList[chunkIndex]);
      }

      chunks.add(chunk);
    }

    return chunks;
  }

  private static Boolean canContinueSoqlWork(Integer reservedQueries) {
    Integer safeReservedQueries = reservedQueries == null ? 1 : reservedQueries;
    return Limits.getQueries() + safeReservedQueries < Limits.getLimitQueries();
  }

  private static WorkDatatableModels.WorkCaseRow mapCaseRow(
    Case caseRecord,
    List<Task> caseTasks
  ) {
    WorkDatatableModels.WorkCaseRow row = new WorkDatatableModels.WorkCaseRow();
    row.id = String.valueOf(caseRecord.Id);
    row.ownerId = String.valueOf(caseRecord.OwnerId);
    row.caseName = caseRecord.Case_Branch_Name_DisplayName__c;
    row.caseNumber = caseRecord.CaseNumber;
    row.assigneeName = resolveAssigneeName(caseRecord);
    row.lastModifiedRaw = caseRecord.LastModifiedDate;
    row.currentTaskSubject = resolveCurrentTaskSubject(caseRecord);

    Integer totalMain = caseRecord.Total_Main_Track_Tasks__c == null
      ? 0
      : Integer.valueOf(caseRecord.Total_Main_Track_Tasks__c);
    Integer completedMain = caseRecord.Completed_Main_Track_Tasks__c == null
      ? 0
      : Integer.valueOf(caseRecord.Completed_Main_Track_Tasks__c);
    row.totalMainTrack = totalMain;
    row.completedMainTrack = completedMain;
    row.mainTrackTasks = resolveMainTrackTasks(caseRecord, completedMain, totalMain);

    applyOverallStatus(row, caseRecord, caseTasks);
    applyMilestone(row, caseRecord);
    row.taskGroups = buildTaskGroups(caseTasks);

    return row;
  }

  private static String resolveMainTrackTasks(
    Case caseRecord,
    Integer completedMain,
    Integer totalMain
  ) {
    if (String.isNotBlank(caseRecord.Main_Track_Task_Completion_Ratio__c)) {
      return formatMainTrackRatio(caseRecord.Main_Track_Task_Completion_Ratio__c);
    }

    return completedMain + ' / ' + totalMain;
  }

  private static String formatMainTrackRatio(String ratioValue) {
    String trimmedRatio = ratioValue.trim();

    if (!trimmedRatio.contains('/')) {
      return trimmedRatio;
    }

    List<String> parts = trimmedRatio.split('/');
    if (parts.size() != 2) {
      return trimmedRatio;
    }

    return parts[0].trim() + ' / ' + parts[1].trim();
  }

  private static String resolveAssigneeName(Case caseRecord) {
    if (String.isNotBlank(caseRecord.Owner_Group__c)) {
      return caseRecord.Owner_Group__c.trim();
    }

    return caseRecord.Owner?.Name;
  }

  private static String resolveCurrentTaskSubject(Case caseRecord) {
    if (String.isBlank(caseRecord.Current_Task_Subject_Assignee__c)) {
      return null;
    }

    List<String> parts = caseRecord.Current_Task_Subject_Assignee__c.split('\\|');
    if (parts.size() > 1) {
      return parts[1].trim();
    }

    return caseRecord.Current_Task_Subject_Assignee__c.trim();
  }

  private static void applyOverallStatus(
    WorkDatatableModels.WorkCaseRow row,
    Case caseRecord,
    List<Task> caseTasks
  ) {
    if (row.totalMainTrack > 0 && row.completedMainTrack >= row.totalMainTrack) {
      row.overallStatus = 'Completed';
      row.overallStatusPillClass = PILL_COMPLETED;
      return;
    }

    if (allTasksCompleted(caseTasks)) {
      row.overallStatus = 'Completed';
      row.overallStatusPillClass = PILL_COMPLETED;
      return;
    }

    if (caseTasks == null || caseTasks.isEmpty()) {
      row.overallStatus = 'Not started';
      row.overallStatusPillClass = PILL_NOT_STARTED;
      return;
    }

    Boolean allNotStarted = true;
    for (Task taskRecord : caseTasks) {
      if (taskRecord.Status != 'Not Started') {
        allNotStarted = false;
        break;
      }
    }

    if (allNotStarted) {
      row.overallStatus = 'Not started';
      row.overallStatusPillClass = PILL_NOT_STARTED;
      return;
    }

    row.overallStatus = 'On track';
    row.overallStatusPillClass = PILL_ON_TRACK;
  }

  private static Boolean allTasksCompleted(List<Task> caseTasks) {
    if (caseTasks == null || caseTasks.isEmpty()) {
      return false;
    }

    for (Task taskRecord : caseTasks) {
      if (taskRecord.Status != 'Completed') {
        return false;
      }
    }

    return true;
  }

  private static void applyMilestone(
    WorkDatatableModels.WorkCaseRow row,
    Case caseRecord
  ) {
    row.milestoneStatus = String.isBlank(caseRecord.MilestoneStatus)
      ? ''
      : caseRecord.MilestoneStatus.trim();

    StatusPill milestonePill = resolveMilestoneStatusPill(row.milestoneStatus);
    row.milestoneStatusPillClass = milestonePill.pillClass;
  }

  private static StatusPill resolveMilestoneStatusPill(String milestoneStatus) {
    if (String.isBlank(milestoneStatus)) {
      return new StatusPill('', '');
    }

    String normalizedStatus = milestoneStatus.toLowerCase();

    if (
      normalizedStatus.contains('compliant') ||
      normalizedStatus.contains('completed')
    ) {
      return new StatusPill(milestoneStatus, PILL_COMPLETED);
    }

    if (
      normalizedStatus.contains('open violation') ||
      normalizedStatus.contains('warning')
    ) {
      return new StatusPill(milestoneStatus, PILL_HO_SUBMISSION);
    }

    if (normalizedStatus.contains('closed violation')) {
      return new StatusPill(milestoneStatus, PILL_NOT_STARTED);
    }

    return new StatusPill(milestoneStatus, PILL_ON_TRACK);
  }

  private static List<WorkDatatableModels.WorkTaskGroup> buildTaskGroups(
    List<Task> caseTasks
  ) {
    List<WorkDatatableModels.WorkTaskGroup> groups = new List<WorkDatatableModels.WorkTaskGroup>();
    if (caseTasks == null || caseTasks.isEmpty()) {
      return groups;
    }

    Map<String, List<Task>> tasksByGroupKey = new Map<String, List<Task>>();
    List<String> orderedKeys = new List<String>{
      'branchPitStop',
      'mainTrack',
      'hoPitStop'
    };

    for (Task taskRecord : caseTasks) {
      String groupKey = resolveTaskGroupKey(taskRecord);
      if (!tasksByGroupKey.containsKey(groupKey)) {
        tasksByGroupKey.put(groupKey, new List<Task>());
      }
      tasksByGroupKey.get(groupKey).add(taskRecord);
    }

    for (String groupKey : orderedKeys) {
      if (!tasksByGroupKey.containsKey(groupKey)) {
        continue;
      }

      List<Task> groupTasks = tasksByGroupKey.get(groupKey);
      sortGroupTasks(groupTasks, groupKey);

      WorkDatatableModels.WorkTaskGroup taskGroup = new WorkDatatableModels.WorkTaskGroup();
      taskGroup.key = groupKey;
      taskGroup.label = resolveTaskGroupLabel(groupKey, groupTasks.size());

      for (Task taskRecord : groupTasks) {
        taskGroup.tasks.add(mapTaskRow(taskRecord));
      }

      groups.add(taskGroup);
    }

    return groups;
  }

  private static void sortGroupTasks(List<Task> tasks, String groupKey) {
    if (tasks == null || tasks.size() < 2) {
      return;
    }

    if (groupKey == 'mainTrack') {
      tasks.sort(new MainTrackTaskComparator());
      return;
    }

    tasks.sort(new PitStopTaskComparator());
  }

  private static String resolveTaskGroupKey(Task taskRecord) {
    if (taskRecord.Home_Office_Pit_Stop__c == true) {
      return 'hoPitStop';
    }

    if (taskRecord.Branch_Pit_Stop__c == true) {
      return 'branchPitStop';
    }

    return 'mainTrack';
  }

  private static String resolveTaskGroupLabel(String groupKey, Integer count) {
    if (groupKey == 'branchPitStop') {
      return 'Branch Pit Stop (' + count + ')';
    }
    if (groupKey == 'hoPitStop') {
      return 'HO Pit Stop (' + count + ')';
    }
    return 'Main Track (' + count + ')';
  }

  private class MainTrackTaskComparator implements System.Comparator<Task> {
    public Integer compare(Task left, Task right) {
      Decimal leftOrder = left.Order__c == null ? 999999 : left.Order__c;
      Decimal rightOrder = right.Order__c == null ? 999999 : right.Order__c;

      if (leftOrder == rightOrder) {
        if (left.CreatedDate == right.CreatedDate) {
          return 0;
        }
        return left.CreatedDate < right.CreatedDate ? -1 : 1;
      }

      return leftOrder < rightOrder ? -1 : 1;
    }
  }

  private class PitStopTaskComparator implements System.Comparator<Task> {
    public Integer compare(Task left, Task right) {
      if (left.CreatedDate == right.CreatedDate) {
        return 0;
      }
      return left.CreatedDate > right.CreatedDate ? -1 : 1;
    }
  }

  private static WorkDatatableModels.WorkTaskRow mapTaskRow(Task taskRecord) {
    WorkDatatableModels.WorkTaskRow row = new WorkDatatableModels.WorkTaskRow();
    row.id = String.valueOf(taskRecord.Id);
    row.name = taskRecord.Subject;
    row.ownerName = taskRecord.Owner?.Name;
    row.dueDate = formatDate(taskRecord.ActivityDate);
    row.completedDate = resolveCompletedDate(taskRecord);
    row.isStarred = isMilestoneTask(taskRecord);

    StatusPill taskPill = resolveTaskStatusPill(taskRecord.Status);
    row.status = taskPill.label;
    row.statusPillClass = taskPill.pillClass;

    return row;
  }

  private static Boolean isMilestoneTask(Task taskRecord) {
    Task_Template_Item__c templateItem = taskRecord?.Task_Template_Item__r;
    if (templateItem == null) {
      return false;
    }

    return templateItem.Home_Office_Goal_Milestone__c == true ||
      templateItem.Home_Office_Submission_Milestone__c == true ||
      templateItem.Branch_Goal_Milestone__c == true ||
      templateItem.Home_Office_Approval_Milestone__c == true;
  }

  private static String resolveCompletedDate(Task taskRecord) {
    if (
      taskRecord.Branch_Pit_Stop__c == true ||
      taskRecord.Home_Office_Pit_Stop__c == true
    ) {
      return taskRecord.Completed_Date__c == null
        ? ''
        : String.valueOf(taskRecord.Completed_Date__c);
    }

    return formatDateTime(taskRecord.CompletedDateTime);
  }

  private static StatusPill resolveTaskStatusPill(String status) {
    if (status == 'Completed') {
      return new StatusPill('Completed', PILL_COMPLETED);
    }
    if (status == 'Not Started') {
      return new StatusPill('Not started', PILL_NOT_STARTED);
    }
    return new StatusPill('On track', PILL_ON_TRACK);
  }

  private static String formatDate(Date value) {
    if (value == null) {
      return '';
    }

    return Datetime.newInstance(value, Time.newInstance(0, 0, 0, 0))
      .format('MMM d, yyyy');
  }

  private static String formatDateTime(Datetime value) {
    if (value == null) {
      return '';
    }

    return value.format('MMM d, yyyy');
  }

  private class StatusPill {
    public String label { get; private set; }
    public String pillClass { get; private set; }

    public StatusPill(String label, String pillClass) {
      this.label = label;
      this.pillClass = pillClass;
    }
  }
}