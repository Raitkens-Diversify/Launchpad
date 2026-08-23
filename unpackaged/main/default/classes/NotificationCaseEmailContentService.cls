/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-24
 *
 * Builds Case notification titles and HTML email bodies with linked records.
 */
public without sharing class NotificationCaseEmailContentService {
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

  private class CaseEmailContext {
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

    Map<Id, CaseEmailContext> contextByLogId = loadContextsForLogs(logs);
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

    CaseEmailContext context = loadContext(logRecord);
    if (context.caseRecord == null) {
      return emptyResult();
    }

    String title = buildTitle(context.changeContext);
    String htmlBody = buildRecordTable(context);
    String plainBody = buildPlainBody(context);
    String targetRecordId = String.valueOf(context.caseRecord.Id);

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

    CaseEmailContext context = loadContext(logRecord);

    if (context.changeContext == null && context.caseRecord == null) {
      return NotificationConstants.DISPLAY_NOT_APPLICABLE;
    }

    return buildChangeMadeSummary(context.changeContext, false);
  }

  public static String buildChangedAtDisplay(Notification_Log__c logRecord) {
    if (logRecord == null) {
      return NotificationConstants.DISPLAY_NOT_APPLICABLE;
    }

    CaseEmailContext context = loadContext(logRecord);
    return NotificationChangeModels.formatChangedAtDisplay(
      context.changeContext,
      logRecord
    );
  }

  public static Datetime resolveChangedAtDatetime(Notification_Log__c logRecord) {
    if (logRecord == null) {
      return null;
    }

    CaseEmailContext context = loadContext(logRecord);
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

    Map<Id, CaseEmailContext> contextByLogId = loadContextsForLogs(logs);

    for (Notification_Log__c logRecord : logs) {
      if (logRecord == null || logRecord.Id == null) {
        continue;
      }

      CaseEmailContext context = contextByLogId.get(logRecord.Id);

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

  private static CaseEmailContext buildMinimalPresentationContext(
    Notification_Log__c logRecord
  ) {
    CaseEmailContext context = new CaseEmailContext();
    context.changeContext = NotificationChangeModels.fromJson(
      logRecord.Change_Context__c
    );

    if (context.changeContext == null) {
      context.changeContext = new NotificationChangeModels.ChangeContext(
        NotificationConstants.OBJECT_TYPE_CASE,
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

  private static CaseEmailContext loadContext(Notification_Log__c logRecord) {
    CaseEmailContext context = new CaseEmailContext();
    context.changeContext = NotificationChangeModels.fromJson(
      logRecord.Change_Context__c
    );

    if (context.changeContext == null) {
      context.changeContext = new NotificationChangeModels.ChangeContext(
        NotificationConstants.OBJECT_TYPE_CASE,
        NotificationConstants.CHANGE_TYPE_INSERT
      );
    }

    NotificationChangeDisplayResolver.enrichChangeContext(context.changeContext);

    List<Case> cases = [
      SELECT
        Id,
        CaseNumber,
        Subject,
        Case_Branch_Name_DisplayName__c,
        OwnerId,
        Owner.Name,
        ContactId,
        Contact.Name,
        AccountId,
        Financial_Advisor_Team__c,
        Financial_Advisor_Team__r.Name,
        Due_Date_of_Current_Task__c
      FROM Case
      WHERE Id = :((Id) logRecord.Source_Record_Id__c)
      LIMIT 1
    ];

    if (cases.isEmpty()) {
      return context;
    }

    context.caseRecord = cases[0];
    context.householdAccount = resolveHouseholdAccount(
      logRecord.Household__c,
      context.caseRecord.AccountId
    );
    context.latestPublishedComment = resolveLatestCaseComment(
      context.caseRecord.Id
    );

    return context;
  }

  private static Map<Id, CaseEmailContext> loadContextsForLogs(
    List<Notification_Log__c> logs
  ) {
    Map<Id, CaseEmailContext> contextByLogId = new Map<Id, CaseEmailContext>();
    Set<Id> caseIds = new Set<Id>();
    Set<Id> householdIds = new Set<Id>();

    for (Notification_Log__c logRecord : logs) {
      if (logRecord.Id == null || String.isBlank(logRecord.Source_Record_Id__c)) {
        continue;
      }

      caseIds.add((Id) logRecord.Source_Record_Id__c);

      if (logRecord.Household__c != null) {
        householdIds.add(logRecord.Household__c);
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
          OwnerId,
          Owner.Name,
          ContactId,
          Contact.Name,
          AccountId,
          Financial_Advisor_Team__c,
          Financial_Advisor_Team__r.Name,
          Due_Date_of_Current_Task__c
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

      CaseEmailContext context = new CaseEmailContext();
      context.changeContext = NotificationChangeModels.fromJson(
        logRecord.Change_Context__c
      );

      if (context.changeContext == null) {
        context.changeContext = new NotificationChangeModels.ChangeContext(
          NotificationConstants.OBJECT_TYPE_CASE,
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
      context.caseRecord = caseById.get((Id) logRecord.Source_Record_Id__c);

      if (context.caseRecord == null) {
        continue;
      }

      context.householdAccount = resolveHouseholdAccountFromMaps(
        logRecord.Household__c,
        context.caseRecord.AccountId,
        accountById
      );
      context.latestPublishedComment = commentByCaseId.get(
        context.caseRecord.Id
      );
      contextByLogId.put(logRecord.Id, context);
    }

    return contextByLogId;
  }

  private static Account resolveHouseholdAccountFromMaps(
    Id householdId,
    Id accountId,
    Map<Id, Account> accountById
  ) {
    if (householdId != null && accountById.containsKey(householdId)) {
      return accountById.get(householdId);
    }

    if (accountId != null && accountById.containsKey(accountId)) {
      return accountById.get(accountId);
    }

    Id resolvedHouseholdId = householdId;

    if (resolvedHouseholdId == null && accountId != null) {
      resolvedHouseholdId = resolveHouseholdFromAccountId(accountId);
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

  private static String assembleDigestTable(
    List<Notification_Log__c> logs,
    Map<Id, CaseEmailContext> contextByLogId,
    Integer bodyLimit
  ) {
    List<NotificationDigestEmailGroupingService.DigestSortEntry> sortEntries = new List<NotificationDigestEmailGroupingService.DigestSortEntry>();
    Map<Id, String> rowHtmlByLogId = new Map<Id, String>();

    for (Notification_Log__c logRecord : logs) {
      CaseEmailContext context = contextByLogId.get(logRecord.Id);

      if (context == null || context.caseRecord == null) {
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

    return String.isBlank(body) ? '<p>Case details are unavailable.</p>' : body;
  }

  private static NotificationDigestEmailGroupingService.DigestSortEntry buildDigestSortEntry(
    Notification_Log__c logRecord,
    CaseEmailContext context
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

  private static String buildAcDigestTableRow(CaseEmailContext context) {
    return '<tr>' +
      '<td>' +
      buildLinkedRecordCell(
        context.caseRecord.Id,
        displaySubject(context.caseRecord)
      ) +
      '</td>' +
      '<td>' +
      buildChangeMadeHtmlSummary(context.changeContext) +
      '</td>' +
      '<td>' +
      escapeHtml(displayOwner(context.caseRecord)) +
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
      escapeHtml(displayFinancialAdvisorTeam(context.caseRecord)) +
      '</td>' +
      '</tr>';
  }

  private static String buildHouseholdCell(Account householdAccount) {
    if (householdAccount == null) {
      return escapeHtml(NotificationConstants.DISPLAY_NOT_APPLICABLE);
    }

    return buildLinkedRecordCell(householdAccount.Id, householdAccount.Name);
  }

  private static Account resolveHouseholdAccount(Id householdId, Id accountId) {
    Id resolvedHouseholdId = householdId;

    if (resolvedHouseholdId == null && accountId != null) {
      resolvedHouseholdId = resolveHouseholdFromAccountId(accountId);
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
      return 'New case';
    }

    if (changeContext.triggerType == NotificationConstants.CHANGE_TYPE_INSERT) {
      return 'New case';
    }

    if (
      changeContext.changedFields != null &&
      changeContext.changedFields.size() == 1 &&
      changeContext.changedFields[0].apiName == 'OwnerId'
    ) {
      return 'Case assignment changed';
    }

    return 'Case updated';
  }

  private static String buildPlainBody(CaseEmailContext context) {
    List<String> lines = new List<String>();
    lines.add(
      'Case Summary Name: ' + displayCaseSummaryName(context.caseRecord)
    );
    lines.add('Subject: ' + displaySubject(context.caseRecord));
    lines.add('Change Made: ' + buildChangeMadeSummary(context.changeContext));
    lines.add('Assigned To: ' + displayOwner(context.caseRecord));
    lines.add(
      'Financial Advisor Team: ' + displayFinancialAdvisorTeam(context.caseRecord)
    );
    lines.add('Due Date: ' + displayDueDate(context.caseRecord));
    lines.add(
      'Household: ' +
      (context.householdAccount == null
        ? NotificationConstants.DISPLAY_NOT_APPLICABLE
        : context.householdAccount.Name)
    );
    lines.add('Case Comments: ' + displayCaseComments(context));
    return String.join(lines, '\n');
  }

  private static String buildRecordTable(CaseEmailContext context) {
    return buildTableOpen(false) + buildTableRow(context, false) + '</tbody></table>';
  }

  private static String buildTableOpen(Boolean forDigest) {
    return '<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse;">' +
      '<thead><tr>' +
      '<th align="left" style="background-color:#f3f3f3;">Case Summary Name</th>' +
      '<th align="left" style="background-color:#f3f3f3;">Subject</th>' +
      '<th align="left" style="background-color:#f3f3f3;">Change Made</th>' +
      buildChangedAtHeader(forDigest) +
      '<th align="left" style="background-color:#f3f3f3;">Assigned To</th>' +
      '<th align="left" style="background-color:#f3f3f3;">Financial Advisor Team</th>' +
      '<th align="left" style="background-color:#f3f3f3;">Due Date</th>' +
      '<th align="left" style="background-color:#f3f3f3;">Household</th>' +
      '<th align="left" style="background-color:#f3f3f3;">Case Comments</th>' +
      '</tr></thead><tbody>';
  }

  private static String buildTableRow(
    CaseEmailContext context,
    Boolean forDigest
  ) {
    return '<tr>' +
      '<td>' +
      buildCaseSummaryNameCell(context.caseRecord) +
      '</td>' +
      '<td>' +
      escapeHtml(displaySubject(context.caseRecord)) +
      '</td>' +
      '<td>' +
      buildChangeMadeHtmlSummary(context.changeContext) +
      '</td>' +
      buildChangedAtCell(context.changedAtDisplay, forDigest) +
      '<td>' +
      escapeHtml(displayOwner(context.caseRecord)) +
      '</td>' +
      '<td>' +
      escapeHtml(displayFinancialAdvisorTeam(context.caseRecord)) +
      '</td>' +
      '<td>' +
      escapeHtml(displayDueDate(context.caseRecord)) +
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

  private static String buildCaseSummaryNameCell(Case caseRecord) {
    List<String> parts = new List<String>();
    parts.add(
      buildLinkedRecordCell(caseRecord.Id, displayCaseSummaryName(caseRecord))
    );

    if (caseRecord.ContactId != null && caseRecord.Contact != null) {
      parts.add(
        buildLinkedRecordCell(caseRecord.ContactId, caseRecord.Contact.Name)
      );
    }

    return String.join(parts, '<br/>');
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
      return forHtml ? escapeHtml('Case created') : 'Case created';
    }

    if (
      changeContext.changedFields == null ||
      changeContext.changedFields.isEmpty()
    ) {
      return forHtml ? escapeHtml('Case updated') : 'Case updated';
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

  private static String displayCaseSummaryName(Case caseRecord) {
    if (caseRecord == null) {
      return NotificationConstants.DISPLAY_NOT_APPLICABLE;
    }

    if (!String.isBlank(caseRecord.Case_Branch_Name_DisplayName__c)) {
      return caseRecord.Case_Branch_Name_DisplayName__c;
    }

    if (!String.isBlank(caseRecord.Subject)) {
      return caseRecord.Subject;
    }

    return String.isBlank(caseRecord.CaseNumber)
      ? 'Case'
      : caseRecord.CaseNumber;
  }

  private static String displaySubject(Case caseRecord) {
    if (caseRecord == null || String.isBlank(caseRecord.Subject)) {
      return NotificationConstants.DISPLAY_NOT_APPLICABLE;
    }

    return caseRecord.Subject;
  }

  private static String displayOwner(Case caseRecord) {
    if (caseRecord == null || caseRecord.Owner == null) {
      return NotificationConstants.DISPLAY_NOT_APPLICABLE;
    }

    return String.isBlank(caseRecord.Owner.Name)
      ? NotificationConstants.DISPLAY_NOT_APPLICABLE
      : caseRecord.Owner.Name;
  }

  private static String displayFinancialAdvisorTeam(Case caseRecord) {
    if (
      caseRecord == null ||
      caseRecord.Financial_Advisor_Team__r == null ||
      String.isBlank(caseRecord.Financial_Advisor_Team__r.Name)
    ) {
      return NotificationConstants.DISPLAY_NOT_APPLICABLE;
    }

    return caseRecord.Financial_Advisor_Team__r.Name;
  }

  private static String displayDueDate(Case caseRecord) {
    if (caseRecord == null || caseRecord.Due_Date_of_Current_Task__c == null) {
      return NotificationConstants.DISPLAY_NOT_APPLICABLE;
    }

    return caseRecord.Due_Date_of_Current_Task__c.format();
  }

  private static String displayCaseComments(CaseEmailContext context) {
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

  private static String buildRecordUrl(Id recordId) {
    return Url.getOrgDomainUrl().toExternalForm() +
      '/lightning/r/' +
      recordId.getSObjectType().getDescribe().getName() +
      '/' +
      recordId +
      '/view';
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
      'Case notification',
      '<p>Case details are unavailable.</p>',
      'Case details are unavailable.',
      null
    );
  }
}