/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-24
 *
 * Builds Task notification titles and HTML email bodies with linked records.
 */
public without sharing class NotificationTaskEmailContentService {
  public class ContentResult {
    public String title;
    public String htmlBody;
    public String plainBody;
    public String targetRecordId;

    public ContentResult(
      String title,
      String htmlBody,
      String plainBody,
      String targetRecordId
    ) {
      this.title = title;
      this.htmlBody = htmlBody;
      this.plainBody = plainBody;
      this.targetRecordId = targetRecordId;
    }
  }

  private class TaskEmailContext {
    public Task taskRecord;
    public Case caseRecord;
    public Account householdAccount;
    public NotificationChangeModels.ChangeContext changeContext;
    public String changedAtDisplay;
    public String latestPublishedComment;
  }

  public static String buildDigestTable(
    List<Notification_Log__c> logs,
    Integer bodyLimit
  ) {
    if (logs == null || logs.isEmpty()) {
      return '';
    }

    Map<Id, TaskEmailContext> contextByLogId = loadContextsForLogs(logs);
    return assembleDigestTable(logs, contextByLogId, bodyLimit);
  }

  public static ContentResult build(Notification_Log__c logRecord) {
    if (logRecord == null || String.isBlank(logRecord.Source_Record_Id__c)) {
      return emptyResult();
    }

    String cacheKey = NotificationEmailContentCache.buildSourceKey(
      logRecord.Source_Type__c,
      logRecord.Source_Record_Id__c
    );
    Object cachedContent = NotificationEmailContentCache.get(cacheKey);
    if (cachedContent instanceof ContentResult) {
      return (ContentResult) cachedContent;
    }

    TaskEmailContext context = loadContext(logRecord);
    if (context.taskRecord == null) {
      return emptyResult();
    }

    String title = buildTitle(context.changeContext);
    String htmlBody = buildHtmlBody(context);
    String plainBody = buildPlainBody(context);
    String targetRecordId = String.valueOf(context.taskRecord.Id);

    ContentResult result = new ContentResult(
      title,
      htmlBody,
      plainBody,
      targetRecordId
    );
    NotificationEmailContentCache.put(cacheKey, result);
    return result;
  }

  public static String buildChangeMadePlainText(Notification_Log__c logRecord) {
    if (logRecord == null || String.isBlank(logRecord.Source_Record_Id__c)) {
      return NotificationConstants.DISPLAY_NOT_APPLICABLE;
    }

    TaskEmailContext context = loadContext(logRecord);

    if (context.changeContext == null && context.taskRecord == null) {
      return NotificationConstants.DISPLAY_NOT_APPLICABLE;
    }

    return buildChangeMadeSummary(context.changeContext, false);
  }

  public static String buildChangedAtDisplay(Notification_Log__c logRecord) {
    if (logRecord == null) {
      return NotificationConstants.DISPLAY_NOT_APPLICABLE;
    }

    TaskEmailContext context = loadContext(logRecord);
    return NotificationChangeModels.formatChangedAtDisplay(
      context.changeContext,
      logRecord
    );
  }

  public static Datetime resolveChangedAtDatetime(Notification_Log__c logRecord) {
    if (logRecord == null) {
      return null;
    }

    TaskEmailContext context = loadContext(logRecord);
    return NotificationChangeModels.resolveChangedAtDatetime(
      context.changeContext,
      logRecord
    );
  }

  public static Map<Id, NotificationCenterModels.LogPresentationFields> loadPresentationFieldsForLogs(
    List<Notification_Log__c> logs
  ) {
    Map<Id, NotificationCenterModels.LogPresentationFields> fieldsByLogId = new Map<Id, NotificationCenterModels.LogPresentationFields>();

    if (logs == null || logs.isEmpty()) {
      return fieldsByLogId;
    }

    Map<Id, TaskEmailContext> contextByLogId = loadContextsForLogs(logs);

    for (Notification_Log__c logRecord : logs) {
      if (logRecord == null || logRecord.Id == null) {
        continue;
      }

      TaskEmailContext context = contextByLogId.get(logRecord.Id);

      if (context == null) {
        context = buildMinimalPresentationContext(logRecord);
      }

      NotificationCenterModels.LogPresentationFields fields = new NotificationCenterModels.LogPresentationFields();
      fields.changeMadePlainText = buildChangeMadeSummary(
        context.changeContext,
        false
      );
      fields.changedAtDisplay = String.isBlank(context.changedAtDisplay)
        ? NotificationChangeModels.formatChangedAtDisplay(
            context.changeContext,
            logRecord
          )
        : context.changedAtDisplay;
      fields.changedAtDatetime = NotificationChangeModels.resolveChangedAtDatetime(
        context.changeContext,
        logRecord
      );
      fieldsByLogId.put(logRecord.Id, fields);
    }

    return fieldsByLogId;
  }

  private static TaskEmailContext buildMinimalPresentationContext(
    Notification_Log__c logRecord
  ) {
    TaskEmailContext context = new TaskEmailContext();
    context.changeContext = NotificationChangeModels.fromJson(
      logRecord.Change_Context__c
    );

    if (context.changeContext == null) {
      context.changeContext = new NotificationChangeModels.ChangeContext(
        NotificationConstants.OBJECT_TYPE_TASK,
        NotificationConstants.CHANGE_TYPE_INSERT
      );
    }

    NotificationChangeDisplayResolver.enrichChangeContext(context.changeContext);
    context.changedAtDisplay = NotificationChangeModels.formatChangedAtDisplay(
      context.changeContext,
      logRecord
    );
    return context;
  }

  private static TaskEmailContext loadContext(Notification_Log__c logRecord) {
    TaskEmailContext context = new TaskEmailContext();
    context.changeContext = NotificationChangeModels.fromJson(
      logRecord.Change_Context__c
    );

    if (context.changeContext == null) {
      context.changeContext = new NotificationChangeModels.ChangeContext(
        NotificationConstants.OBJECT_TYPE_TASK,
        NotificationConstants.CHANGE_TYPE_INSERT
      );
    }

    NotificationChangeDisplayResolver.enrichChangeContext(context.changeContext);

    List<Task> tasks = [
      SELECT
        Id,
        Subject,
        WhatId,
        OwnerId,
        Owner.Name,
        Status,
        ActivityDate,
        Priority
      FROM Task
      WHERE Id = :((Id) logRecord.Source_Record_Id__c)
      LIMIT 1
    ];

    if (tasks.isEmpty()) {
      return context;
    }

    context.taskRecord = tasks[0];
    context.caseRecord = resolveCase(context.taskRecord.WhatId);
    context.householdAccount = resolveHouseholdAccount(
      logRecord.Household__c,
      context.taskRecord.WhatId,
      context.caseRecord
    );
    context.latestPublishedComment = context.caseRecord == null
      ? null
      : resolveLatestCaseComment(context.caseRecord.Id);

    return context;
  }

  private static Map<Id, TaskEmailContext> loadContextsForLogs(
    List<Notification_Log__c> logs
  ) {
    Map<Id, TaskEmailContext> contextByLogId = new Map<Id, TaskEmailContext>();
    Set<Id> taskIds = new Set<Id>();
    Set<Id> caseIds = new Set<Id>();
    Set<Id> householdIds = new Set<Id>();

    for (Notification_Log__c logRecord : logs) {
      if (logRecord.Id == null || String.isBlank(logRecord.Source_Record_Id__c)) {
        continue;
      }

      taskIds.add((Id) logRecord.Source_Record_Id__c);

      if (logRecord.Household__c != null) {
        householdIds.add(logRecord.Household__c);
      }
    }

    Map<Id, Task> taskById = new Map<Id, Task>();

    if (!taskIds.isEmpty()) {
      for (Task taskRecord : [
        SELECT
          Id,
          Subject,
          WhatId,
          OwnerId,
          Owner.Name,
          Status,
          ActivityDate,
          Priority
        FROM Task
        WHERE Id IN :taskIds
      ]) {
        taskById.put(taskRecord.Id, taskRecord);

        if (
          taskRecord.WhatId != null &&
          String.valueOf(taskRecord.WhatId).substring(0, 3) == '500'
        ) {
          caseIds.add(taskRecord.WhatId);
        }

        if (
          taskRecord.WhatId != null &&
          String.valueOf(taskRecord.WhatId).substring(0, 3) == '001'
        ) {
          householdIds.add(taskRecord.WhatId);
        }
      }
    }

    Map<Id, Case> caseById = new Map<Id, Case>();

    if (!caseIds.isEmpty()) {
      for (Case caseRecord : [
        SELECT
          Id,
          CaseNumber,
          Subject,
          Case_Branch_Name_DisplayName__c,
          Description,
          AccountId,
          ContactId,
          Financial_Advisor_Team__c,
          Financial_Advisor_Team__r.Name
        FROM Case
        WHERE Id IN :caseIds
      ]) {
        caseById.put(caseRecord.Id, caseRecord);

        if (caseRecord.AccountId != null) {
          householdIds.add(caseRecord.AccountId);
        }
      }
    }

    Map<Id, Account> accountById = NotificationEmailBulkQueryService.selectAccountsById(
      householdIds
    );
    Map<Id, String> commentByCaseId = NotificationEmailBulkQueryService.selectLatestPublishedCommentByCaseId(
      caseIds
    );

    for (Notification_Log__c logRecord : logs) {
      if (logRecord.Id == null || String.isBlank(logRecord.Source_Record_Id__c)) {
        continue;
      }

      TaskEmailContext context = new TaskEmailContext();
      context.changeContext = NotificationChangeModels.fromJson(
        logRecord.Change_Context__c
      );

      if (context.changeContext == null) {
        context.changeContext = new NotificationChangeModels.ChangeContext(
          NotificationConstants.OBJECT_TYPE_TASK,
          NotificationConstants.CHANGE_TYPE_INSERT
        );
      }

      NotificationChangeDisplayResolver.enrichChangeContext(
        context.changeContext
      );
      context.changedAtDisplay = NotificationChangeModels.formatChangedAtDisplay(
        context.changeContext,
        logRecord
      );
      context.taskRecord = taskById.get((Id) logRecord.Source_Record_Id__c);

      if (context.taskRecord == null) {
        continue;
      }

      context.caseRecord = context.taskRecord.WhatId == null
        ? null
        : caseById.get(context.taskRecord.WhatId);
      context.householdAccount = resolveHouseholdAccountFromMaps(
        logRecord.Household__c,
        context.taskRecord.WhatId,
        context.caseRecord,
        accountById
      );
      context.latestPublishedComment = context.caseRecord == null
        ? null
        : commentByCaseId.get(context.caseRecord.Id);
      contextByLogId.put(logRecord.Id, context);
    }

    return contextByLogId;
  }

  private static Account resolveHouseholdAccountFromMaps(
    Id householdId,
    Id whatId,
    Case caseRecord,
    Map<Id, Account> accountById
  ) {
    if (householdId != null && accountById.containsKey(householdId)) {
      return accountById.get(householdId);
    }

    if (caseRecord != null && caseRecord.AccountId != null) {
      if (accountById.containsKey(caseRecord.AccountId)) {
        return accountById.get(caseRecord.AccountId);
      }
    }

    if (
      whatId != null &&
      String.valueOf(whatId).substring(0, 3) == '001' &&
      accountById.containsKey(whatId)
    ) {
      return accountById.get(whatId);
    }

    return resolveHouseholdAccount(householdId, whatId, caseRecord);
  }

  private static String assembleDigestTable(
    List<Notification_Log__c> logs,
    Map<Id, TaskEmailContext> contextByLogId,
    Integer bodyLimit
  ) {
    List<NotificationDigestEmailGroupingService.DigestSortEntry> sortEntries = new List<NotificationDigestEmailGroupingService.DigestSortEntry>();
    Map<Id, String> rowHtmlByLogId = new Map<Id, String>();

    for (Notification_Log__c logRecord : logs) {
      TaskEmailContext context = contextByLogId.get(logRecord.Id);

      if (context == null || context.taskRecord == null) {
        continue;
      }

      sortEntries.add(buildDigestSortEntry(logRecord, context));
      rowHtmlByLogId.put(logRecord.Id, buildAcDigestTableRow(context));
    }

    List<NotificationDigestEmailGroupingService.DigestAssemblyItem> assemblyItems = NotificationDigestEmailGroupingService.buildAcAssemblyOrder(
      sortEntries
    );
    String body = NotificationDigestEmailGroupingService.assembleAcTableHtml(
      assemblyItems,
      rowHtmlByLogId,
      bodyLimit
    );

    return String.isBlank(body) ? '<p>Task details are unavailable.</p>' : body;
  }

  private static NotificationDigestEmailGroupingService.DigestSortEntry buildDigestSortEntry(
    Notification_Log__c logRecord,
    TaskEmailContext context
  ) {
    NotificationDigestEmailGroupingService.DigestSortEntry entry = new NotificationDigestEmailGroupingService.DigestSortEntry();
    entry.logRecord = logRecord;
    entry.householdId = context.householdAccount == null
      ? logRecord.Household__c
      : context.householdAccount.Id;
    entry.householdName = context.householdAccount == null
      ? null
      : context.householdAccount.Name;
    entry.changeDate = NotificationChangeModels.resolveChangedAtDatetime(
      context.changeContext,
      logRecord
    );
    entry.hasHouseholdAssociation =
      logRecord.Household__c != null || context.householdAccount != null;
    entry.hasContactAssociation =
      context.caseRecord != null && context.caseRecord.ContactId != null;
    return entry;
  }

  private static String buildAcDigestTableRow(TaskEmailContext context) {
    return '<tr>' +
      '<td>' +
      buildLinkedRecordCell(
        context.taskRecord.Id,
        displayTaskLabel(context.taskRecord)
      ) +
      '</td>' +
      '<td>' +
      buildChangeMadeHtmlSummary(context.changeContext) +
      '</td>' +
      '<td>' +
      escapeHtml(displayAssignedTo(context.taskRecord)) +
      '</td>' +
      '<td>' +
      escapeHtml(
        String.isBlank(context.changedAtDisplay) ? NotificationConstants.DISPLAY_NOT_APPLICABLE : context.changedAtDisplay
      ) +
      '</td>' +
      '<td>' +
      buildHouseholdCell(context.householdAccount) +
      '</td>' +
      '<td>' +
      escapeHtml(displayFinancialAdvisorTeam(context)) +
      '</td>' +
      '</tr>';
  }

  private static String buildHouseholdCell(Account householdAccount) {
    if (householdAccount == null) {
      return escapeHtml(NotificationConstants.DISPLAY_NOT_APPLICABLE);
    }

    return buildLinkedRecordCell(householdAccount.Id, householdAccount.Name);
  }

  private static String displayFinancialAdvisorTeam(TaskEmailContext context) {
    if (
      context.caseRecord != null &&
      context.caseRecord.Financial_Advisor_Team__r != null &&
      !String.isBlank(context.caseRecord.Financial_Advisor_Team__r.Name)
    ) {
      return context.caseRecord.Financial_Advisor_Team__r.Name;
    }

    if (
      context.householdAccount != null &&
      context.householdAccount.Financial_Advisor_Team__r != null &&
      !String.isBlank(context.householdAccount.Financial_Advisor_Team__r.Name)
    ) {
      return context.householdAccount.Financial_Advisor_Team__r.Name;
    }

    return NotificationConstants.DISPLAY_NOT_APPLICABLE;
  }

  private static Case resolveCase(Id whatId) {
    if (whatId == null || String.valueOf(whatId).substring(0, 3) != '500') {
      return null;
    }

    List<Case> cases = [
      SELECT Id, CaseNumber, Subject, Case_Branch_Name_DisplayName__c, Description, AccountId
      FROM Case
      WHERE Id = :whatId
      LIMIT 1
    ];

    return cases.isEmpty() ? null : cases[0];
  }

  private static Account resolveHouseholdAccount(
    Id householdId,
    Id whatId,
    Case caseRecord
  ) {
    Id resolvedHouseholdId = householdId;

    if (resolvedHouseholdId == null && caseRecord != null) {
      resolvedHouseholdId = resolveHouseholdFromAccountId(caseRecord.AccountId);
    }

    if (
      resolvedHouseholdId == null &&
      whatId != null &&
      String.valueOf(whatId).substring(0, 3) == '001'
    ) {
      resolvedHouseholdId = resolveHouseholdFromAccountId(whatId);
    }

    if (resolvedHouseholdId == null) {
      return null;
    }

    List<Account> households = [
      SELECT Id, Name
      FROM Account
      WHERE Id = :resolvedHouseholdId
      LIMIT 1
    ];

    return households.isEmpty() ? null : households[0];
  }

  private static Id resolveHouseholdFromAccountId(Id accountId) {
    if (accountId == null) {
      return null;
    }

    FscRelHouseholdModels.RootAccountResolveResult resolveResult = new FscRelHouseholdService()
      .resolveRootAccount(accountId);
    return resolveResult.rootAccountId;
  }

  private static String buildTitle(
    NotificationChangeModels.ChangeContext changeContext
  ) {
    if (changeContext == null) {
      return 'New task';
    }

    if (changeContext.triggerType == NotificationConstants.CHANGE_TYPE_INSERT) {
      return 'New task';
    }

    if (
      changeContext.changedFields != null &&
      changeContext.changedFields.size() == 1 &&
      changeContext.changedFields[0].apiName == 'OwnerId'
    ) {
      return 'Task assignment changed';
    }

    return 'Task updated';
  }

  private static String buildHtmlBody(TaskEmailContext context) {
    return buildRecordTable(context);
  }

  private static String buildPlainBody(TaskEmailContext context) {
    List<String> lines = new List<String>();
    lines.add('Subject: ' + displayTaskLabel(context.taskRecord));
    lines.add('Change Made: ' + buildChangeMadeSummary(context.changeContext));
    lines.add('Assigned To: ' + displayAssignedTo(context.taskRecord));
    lines.add('Due Date: ' + displayDueDate(context.taskRecord));
    lines.add('Case Summary Name: ' + displayCaseLabel(context.caseRecord));
    lines.add(
      'Household: ' +
      (context.householdAccount == null
        ? NotificationConstants.DISPLAY_NOT_APPLICABLE
        : context.householdAccount.Name)
    );
    lines.add('Case Comments: ' + displayCaseComments(context));
    return String.join(lines, '\n');
  }

  private static String buildRecordTable(TaskEmailContext context) {
    return buildTableOpen(false) + buildTableRow(context, false) + '</tbody></table>';
  }

  private static String buildTableOpen(Boolean forDigest) {
    return '<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse;">' +
      '<thead><tr>' +
      '<th align="left" style="background-color:#f3f3f3;">Subject</th>' +
      '<th align="left" style="background-color:#f3f3f3;">Change Made</th>' +
      buildChangedAtHeader(forDigest) +
      '<th align="left" style="background-color:#f3f3f3;">Assigned To</th>' +
      '<th align="left" style="background-color:#f3f3f3;">Due Date</th>' +
      '<th align="left" style="background-color:#f3f3f3;">Case Summary Name</th>' +
      '<th align="left" style="background-color:#f3f3f3;">Household</th>' +
      '<th align="left" style="background-color:#f3f3f3;">Case Comments</th>' +
      '</tr></thead><tbody>';
  }

  private static String buildTableRow(
    TaskEmailContext context,
    Boolean forDigest
  ) {
    return '<tr>' +
      '<td>' +
      buildLinkedRecordCell(
        context.taskRecord.Id,
        displayTaskLabel(context.taskRecord)
      ) +
      '</td>' +
      '<td>' +
      buildChangeMadeHtmlSummary(context.changeContext) +
      '</td>' +
      buildChangedAtCell(context.changedAtDisplay, forDigest) +
      '<td>' +
      escapeHtml(displayAssignedTo(context.taskRecord)) +
      '</td>' +
      '<td>' +
      escapeHtml(displayDueDate(context.taskRecord)) +
      '</td>' +
      '<td>' +
      (context.caseRecord == null
        ? NotificationConstants.DISPLAY_NOT_APPLICABLE
        : buildLinkedRecordCell(
            context.caseRecord.Id,
            displayCaseLabel(context.caseRecord)
          )) +
      '</td>' +
      '<td>' +
      (context.householdAccount == null
        ? NotificationConstants.DISPLAY_NOT_APPLICABLE
        : buildLinkedRecordCell(
            context.householdAccount.Id,
            context.householdAccount.Name
          )) +
      '</td>' +
      '<td>' +
      escapeHtml(displayCaseComments(context)) +
      '</td>' +
      '</tr>';
  }

  private static String buildChangeMadeSummary(
    NotificationChangeModels.ChangeContext changeContext
  ) {
    return buildChangeMadeSummary(changeContext, false);
  }

  private static String buildChangeMadeHtmlSummary(
    NotificationChangeModels.ChangeContext changeContext
  ) {
    return buildChangeMadeSummary(changeContext, true);
  }

  private static String buildChangeMadeSummary(
    NotificationChangeModels.ChangeContext changeContext,
    Boolean forHtml
  ) {
    if (changeContext == null) {
      return forHtml ? escapeHtml(NotificationConstants.DISPLAY_NOT_APPLICABLE) : NotificationConstants.DISPLAY_NOT_APPLICABLE;
    }

    if (changeContext.triggerType == NotificationConstants.CHANGE_TYPE_INSERT) {
      return forHtml ? escapeHtml('Task created') : 'Task created';
    }

    if (
      changeContext.changedFields == null ||
      changeContext.changedFields.isEmpty()
    ) {
      return forHtml ? escapeHtml('Task updated') : 'Task updated';
    }

    String lineBreak = forHtml ? '<br/>' : '\n';
    String blockBreak = forHtml ? '<br/><br/>' : '\n\n';
    List<String> summaries = new List<String>();

    for (
      NotificationChangeModels.FieldChange fieldChange : changeContext.changedFields
    ) {
      summaries.add(buildFieldChangeSummary(fieldChange, lineBreak, forHtml));
    }

    return String.join(summaries, blockBreak);
  }

  private static String buildFieldChangeSummary(
    NotificationChangeModels.FieldChange fieldChange,
    String lineBreak,
    Boolean forHtml
  ) {
    String label = forHtml
      ? '<strong>' + escapeHtml(fieldChange.label) + '</strong>'
      : fieldChange.label;
    String oldDisplay = forHtml
      ? escapeHtml(fieldChange.oldDisplay)
      : fieldChange.oldDisplay;
    String newDisplay = forHtml
      ? escapeHtml(fieldChange.newDisplay)
      : fieldChange.newDisplay;

    return label + lineBreak + 'Old: ' + oldDisplay + lineBreak + 'New: ' + newDisplay;
  }

  private static String displayAssignedTo(Task taskRecord) {
    if (taskRecord == null || taskRecord.Owner == null) {
      return NotificationConstants.DISPLAY_NOT_APPLICABLE;
    }

    return String.isBlank(taskRecord.Owner.Name)
      ? NotificationConstants.DISPLAY_NOT_APPLICABLE
      : taskRecord.Owner.Name;
  }

  private static String displayDueDate(Task taskRecord) {
    if (taskRecord == null || taskRecord.ActivityDate == null) {
      return NotificationConstants.DISPLAY_NOT_APPLICABLE;
    }

    return taskRecord.ActivityDate.format();
  }

  private static String displayCaseComments(TaskEmailContext context) {
    if (context == null || context.caseRecord == null) {
      return NotificationConstants.DISPLAY_NOT_APPLICABLE;
    }

    if (!String.isBlank(context.latestPublishedComment)) {
      return context.latestPublishedComment;
    }

    String latestComment = resolveLatestCaseComment(context.caseRecord.Id);
    return String.isBlank(latestComment) ? NotificationConstants.DISPLAY_NOT_APPLICABLE : latestComment;
  }

  private static String resolveLatestCaseComment(Id caseId) {
    if (caseId == null) {
      return null;
    }

    List<CaseComment> caseComments = [
      SELECT CommentBody
      FROM CaseComment
      WHERE ParentId = :caseId AND IsPublished = TRUE
      ORDER BY CreatedDate DESC, Id DESC
      LIMIT 1
    ];

    if (caseComments.isEmpty() || String.isBlank(caseComments[0].CommentBody)) {
      return null;
    }

    return caseComments[0].CommentBody.trim();
  }

  private static String buildLinkedRecordCell(Id recordId, String label) {
    if (recordId == null) {
      return escapeHtml(String.isBlank(label) ? NotificationConstants.DISPLAY_NOT_APPLICABLE : label);
    }

    String safeLabel = String.isBlank(label) ? String.valueOf(recordId) : label;
    return '<a href="' +
      escapeHtml(buildRecordUrl(recordId)) +
      '">' +
      escapeHtml(safeLabel) +
      '</a>';
  }

  private static String buildRecordUrl(Id recordId) {
    return Url.getOrgDomainUrl().toExternalForm() +
      '/lightning/r/' +
      recordId.getSObjectType().getDescribe().getName() +
      '/' +
      recordId +
      '/view';
  }

  private static String displayTaskLabel(Task taskRecord) {
    if (taskRecord == null) {
      return NotificationConstants.DISPLAY_NOT_APPLICABLE;
    }

    return String.isBlank(taskRecord.Subject) ? 'Task' : taskRecord.Subject;
  }

  private static String displayCaseLabel(Case caseRecord) {
    if (caseRecord == null) {
      return NotificationConstants.DISPLAY_NOT_APPLICABLE;
    }

    if (!String.isBlank(caseRecord.Case_Branch_Name_DisplayName__c)) {
      return caseRecord.Case_Branch_Name_DisplayName__c;
    }

    if (!String.isBlank(caseRecord.Subject)) {
      return caseRecord.Subject;
    }

    return caseRecord.CaseNumber;
  }

  private static String buildChangedAtHeader(Boolean forDigest) {
    return forDigest == true
      ? '<th align="left" style="background-color:#f3f3f3;">Changed At</th>'
      : '';
  }

  private static String buildChangedAtCell(
    String changedAtDisplay,
    Boolean forDigest
  ) {
    if (forDigest != true) {
      return '';
    }

    return '<td>' +
      escapeHtml(
        String.isBlank(changedAtDisplay) ? NotificationConstants.DISPLAY_NOT_APPLICABLE : changedAtDisplay
      ) +
      '</td>';
  }

  private static String escapeHtml(String value) {
    if (String.isBlank(value)) {
      return '';
    }

    return value.replace('&', '&amp;')
      .replace('<', '&lt;')
      .replace('>', '&gt;')
      .replace('"', '&quot;')
      .replace('\'', '&#39;');
  }

  private static ContentResult emptyResult() {
    return new ContentResult(
      'Task notification',
      '<p>Task details are unavailable.</p>',
      'Task details are unavailable.',
      null
    );
  }
}