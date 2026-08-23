/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-24
 *
 * Builds Event notification titles and HTML email bodies with linked records.
 */
public without sharing class NotificationEventEmailContentService {
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

  private class EventEmailContext {
    public Event eventRecord;
    public Contact contactRecord;
    public Account householdAccount;
    public Id relatedToRecordId;
    public String relatedToLabel;
    public String attendeeSummary;
    public NotificationChangeModels.ChangeContext changeContext;
    public String changedAtDisplay;
  }

  public static String buildDigestTable(
    List<Notification_Log__c> logs,
    Integer bodyLimit
  ) {
    if (logs == null || logs.isEmpty()) {
      return '';
    }

    Map<Id, EventEmailContext> contextByLogId = loadContextsForLogs(logs);
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

    EventEmailContext context = loadContext(logRecord);
    if (context.eventRecord == null) {
      return emptyResult();
    }

    String title = buildTitle(context.changeContext);
    String htmlBody = buildRecordTable(context);
    String plainBody = buildPlainBody(context);
    String targetRecordId = String.valueOf(context.eventRecord.Id);

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

    EventEmailContext context = loadContext(logRecord);

    if (context.changeContext == null && context.eventRecord == null) {
      return NotificationConstants.DISPLAY_NOT_APPLICABLE;
    }

    return buildChangeMadeSummary(context.changeContext, false);
  }

  public static String buildChangedAtDisplay(Notification_Log__c logRecord) {
    if (logRecord == null) {
      return NotificationConstants.DISPLAY_NOT_APPLICABLE;
    }

    EventEmailContext context = loadContext(logRecord);
    return NotificationChangeModels.formatChangedAtDisplay(
      context.changeContext,
      logRecord
    );
  }

  public static Datetime resolveChangedAtDatetime(Notification_Log__c logRecord) {
    if (logRecord == null) {
      return null;
    }

    EventEmailContext context = loadContext(logRecord);
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

    Map<Id, EventEmailContext> contextByLogId = loadContextsForLogs(logs);

    for (Notification_Log__c logRecord : logs) {
      if (logRecord == null || logRecord.Id == null) {
        continue;
      }

      EventEmailContext context = contextByLogId.get(logRecord.Id);

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

  private static EventEmailContext buildMinimalPresentationContext(
    Notification_Log__c logRecord
  ) {
    EventEmailContext context = new EventEmailContext();
    context.changeContext = NotificationChangeModels.fromJson(
      logRecord.Change_Context__c
    );

    if (context.changeContext == null) {
      context.changeContext = new NotificationChangeModels.ChangeContext(
        NotificationConstants.OBJECT_TYPE_EVENT,
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

  private static EventEmailContext loadContext(Notification_Log__c logRecord) {
    EventEmailContext context = new EventEmailContext();
    context.changeContext = NotificationChangeModels.fromJson(
      logRecord.Change_Context__c
    );

    if (context.changeContext == null) {
      context.changeContext = new NotificationChangeModels.ChangeContext(
        NotificationConstants.OBJECT_TYPE_EVENT,
        NotificationConstants.CHANGE_TYPE_INSERT
      );
    }

    NotificationChangeDisplayResolver.enrichChangeContext(context.changeContext);

    List<Event> events = [
      SELECT
        Id,
        Subject,
        Description,
        WhoId,
        WhatId,
        OwnerId,
        Owner.Name,
        StartDateTime,
        EndDateTime
      FROM Event
      WHERE Id = :((Id) logRecord.Source_Record_Id__c)
      LIMIT 1
    ];

    if (events.isEmpty()) {
      return context;
    }

    context.eventRecord = events[0];
    context.contactRecord = resolveContact(context.eventRecord.WhoId);
    context.householdAccount = resolveHouseholdAccount(
      logRecord.Household__c,
      context.eventRecord.WhatId
    );
    resolveRelatedTo(context);
    context.attendeeSummary = resolveAttendeeSummary(context.eventRecord.Id);

    return context;
  }

  private static Map<Id, EventEmailContext> loadContextsForLogs(
    List<Notification_Log__c> logs
  ) {
    Map<Id, EventEmailContext> contextByLogId = new Map<Id, EventEmailContext>();
    Set<Id> eventIds = new Set<Id>();
    Set<Id> contactIds = new Set<Id>();
    Set<Id> householdIds = new Set<Id>();
    Set<Id> relatedToIds = new Set<Id>();

    for (Notification_Log__c logRecord : logs) {
      if (logRecord.Id == null || String.isBlank(logRecord.Source_Record_Id__c)) {
        continue;
      }

      eventIds.add((Id) logRecord.Source_Record_Id__c);

      if (logRecord.Household__c != null) {
        householdIds.add(logRecord.Household__c);
      }
    }

    Map<Id, Event> eventById = new Map<Id, Event>();

    if (!eventIds.isEmpty()) {
      for (Event eventRecord : [
        SELECT
          Id,
          Subject,
          Description,
          WhoId,
          WhatId,
          OwnerId,
          Owner.Name,
          StartDateTime,
          EndDateTime
        FROM Event
        WHERE Id IN :eventIds
      ]) {
        eventById.put(eventRecord.Id, eventRecord);

        if (
          eventRecord.WhoId != null &&
          String.valueOf(eventRecord.WhoId).substring(0, 3) == '003'
        ) {
          contactIds.add(eventRecord.WhoId);
        }

        if (eventRecord.WhatId != null) {
          relatedToIds.add(eventRecord.WhatId);

          if (String.valueOf(eventRecord.WhatId).substring(0, 3) == '001') {
            householdIds.add(eventRecord.WhatId);
          }
        }
      }
    }

    Map<Id, Contact> contactById = NotificationEmailBulkQueryService.selectContactsById(
      contactIds
    );
    Map<Id, Account> accountById = NotificationEmailBulkQueryService.selectAccountsById(
      householdIds
    );
    Map<Id, String> attendeeSummaryByEventId = NotificationEmailBulkQueryService.selectAttendeeSummaryByEventId(
      eventIds
    );
    Map<Id, String> relatedToLabelById = NotificationChangeDisplayResolver.resolveRecordDisplays(
      relatedToIds
    );

    for (Notification_Log__c logRecord : logs) {
      if (logRecord.Id == null || String.isBlank(logRecord.Source_Record_Id__c)) {
        continue;
      }

      EventEmailContext context = new EventEmailContext();
      context.changeContext = NotificationChangeModels.fromJson(
        logRecord.Change_Context__c
      );

      if (context.changeContext == null) {
        context.changeContext = new NotificationChangeModels.ChangeContext(
          NotificationConstants.OBJECT_TYPE_EVENT,
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
      context.eventRecord = eventById.get((Id) logRecord.Source_Record_Id__c);

      if (context.eventRecord == null) {
        continue;
      }

      context.contactRecord = context.eventRecord.WhoId == null
        ? null
        : contactById.get(context.eventRecord.WhoId);
      context.householdAccount = resolveHouseholdAccountFromMaps(
        logRecord.Household__c,
        context.eventRecord.WhatId,
        accountById
      );
      resolveRelatedToFromMaps(context, relatedToLabelById);
      context.attendeeSummary = attendeeSummaryByEventId.containsKey(
          context.eventRecord.Id
        )
        ? attendeeSummaryByEventId.get(context.eventRecord.Id)
        : NotificationConstants.DISPLAY_NOT_APPLICABLE;
      contextByLogId.put(logRecord.Id, context);
    }

    return contextByLogId;
  }

  private static Account resolveHouseholdAccountFromMaps(
    Id householdId,
    Id whatId,
    Map<Id, Account> accountById
  ) {
    if (householdId != null && accountById.containsKey(householdId)) {
      return accountById.get(householdId);
    }

    if (
      whatId != null &&
      String.valueOf(whatId).substring(0, 3) == '001' &&
      accountById.containsKey(whatId)
    ) {
      return accountById.get(whatId);
    }

    return resolveHouseholdAccount(householdId, whatId);
  }

  private static void resolveRelatedToFromMaps(
    EventEmailContext context,
    Map<Id, String> relatedToLabelById
  ) {
    if (context.eventRecord.WhatId == null) {
      return;
    }

    context.relatedToRecordId = context.eventRecord.WhatId;
    context.relatedToLabel = relatedToLabelById.containsKey(
        context.eventRecord.WhatId
      )
      ? relatedToLabelById.get(context.eventRecord.WhatId)
      : String.valueOf(context.eventRecord.WhatId);
  }

  private static String assembleDigestTable(
    List<Notification_Log__c> logs,
    Map<Id, EventEmailContext> contextByLogId,
    Integer bodyLimit
  ) {
    List<NotificationDigestEmailGroupingService.DigestSortEntry> sortEntries = new List<NotificationDigestEmailGroupingService.DigestSortEntry>();
    Map<Id, String> rowHtmlByLogId = new Map<Id, String>();

    for (Notification_Log__c logRecord : logs) {
      EventEmailContext context = contextByLogId.get(logRecord.Id);

      if (context == null || context.eventRecord == null) {
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

    return String.isBlank(body) ? '<p>Event details are unavailable.</p>' : body;
  }

  private static NotificationDigestEmailGroupingService.DigestSortEntry buildDigestSortEntry(
    Notification_Log__c logRecord,
    EventEmailContext context
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
    entry.hasContactAssociation = context.contactRecord != null;
    return entry;
  }

  private static String buildAcDigestTableRow(EventEmailContext context) {
    return '<tr>' +
      '<td>' +
      buildLinkedRecordCell(
        context.eventRecord.Id,
        displayEventSubject(context.eventRecord)
      ) +
      '</td>' +
      '<td>' +
      buildChangeMadeHtmlSummary(context.changeContext) +
      '</td>' +
      '<td>' +
      escapeHtml(displayAssignedTo(context.eventRecord)) +
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

  private static String displayFinancialAdvisorTeam(EventEmailContext context) {
    if (
      context.householdAccount != null &&
      context.householdAccount.Financial_Advisor_Team__r != null &&
      !String.isBlank(context.householdAccount.Financial_Advisor_Team__r.Name)
    ) {
      return context.householdAccount.Financial_Advisor_Team__r.Name;
    }

    return NotificationConstants.DISPLAY_NOT_APPLICABLE;
  }

  private static Contact resolveContact(Id whoId) {
    if (whoId == null || String.valueOf(whoId).substring(0, 3) != '003') {
      return null;
    }

    List<Contact> contacts = [
      SELECT Id, Name
      FROM Contact
      WHERE Id = :whoId
      LIMIT 1
    ];

    return contacts.isEmpty() ? null : contacts[0];
  }

  private static Account resolveHouseholdAccount(Id householdId, Id whatId) {
    Id resolvedHouseholdId = householdId;

    if (resolvedHouseholdId == null && whatId != null && String.valueOf(whatId).substring(0, 3) == '001') {
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

  private static void resolveRelatedTo(EventEmailContext context) {
    if (context.eventRecord.WhatId == null) {
      return;
    }

    Map<Id, String> idToDisplay = NotificationChangeDisplayResolver.resolveRecordDisplays(
      new Set<Id>{ context.eventRecord.WhatId }
    );

    context.relatedToRecordId = context.eventRecord.WhatId;
    context.relatedToLabel = idToDisplay.containsKey(context.eventRecord.WhatId)
      ? idToDisplay.get(context.eventRecord.WhatId)
      : String.valueOf(context.eventRecord.WhatId);
  }

  private static String resolveAttendeeSummary(Id eventId) {
    if (eventId == null) {
      return NotificationConstants.DISPLAY_NOT_APPLICABLE;
    }

    List<String> attendeeNames = new List<String>();

    for (EventRelation attendeeRelation : [
      SELECT Relation.Name
      FROM EventRelation
      WHERE EventId = :eventId AND IsInvitee = TRUE
      ORDER BY Relation.Name ASC NULLS LAST
    ]) {
      if (!String.isBlank(attendeeRelation.Relation.Name)) {
        attendeeNames.add(attendeeRelation.Relation.Name.trim());
      }
    }

    return attendeeNames.isEmpty() ? NotificationConstants.DISPLAY_NOT_APPLICABLE : String.join(attendeeNames, ', ');
  }

  private static String buildTitle(
    NotificationChangeModels.ChangeContext changeContext
  ) {
    if (changeContext == null) {
      return 'New event';
    }

    if (changeContext.triggerType == NotificationConstants.CHANGE_TYPE_INSERT) {
      return 'New event';
    }

    if (
      changeContext.changedFields != null &&
      changeContext.changedFields.size() == 1 &&
      changeContext.changedFields[0].apiName == 'OwnerId'
    ) {
      return 'Event assignment changed';
    }

    return 'Event updated';
  }

  private static String buildPlainBody(EventEmailContext context) {
    List<String> lines = new List<String>();
    lines.add('Subject: ' + displayEventSubject(context.eventRecord));
    lines.add('Change Made: ' + buildChangeMadeSummary(context.changeContext));
    lines.add('Assigned To: ' + displayAssignedTo(context.eventRecord));
    lines.add('Attendees: ' + context.attendeeSummary);
    lines.add('Start Date/Time: ' + displayStartDateTime(context.eventRecord));
    lines.add('End Date/Time: ' + displayEndDateTime(context.eventRecord));
    lines.add('Contact: ' + displayContactName(context.contactRecord));
    lines.add(
      'Household: ' +
      (context.householdAccount == null
        ? NotificationConstants.DISPLAY_NOT_APPLICABLE
        : context.householdAccount.Name)
    );
    lines.add('Description: ' + displayDescription(context.eventRecord));
    return String.join(lines, '\n');
  }

  private static String buildRecordTable(EventEmailContext context) {
    return buildTableOpen(false) + buildTableRow(context, false) + '</tbody></table>';
  }

  private static String buildTableOpen(Boolean forDigest) {
    return '<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse;">' +
      '<thead><tr>' +
      '<th align="left" style="background-color:#f3f3f3;">Subject</th>' +
      '<th align="left" style="background-color:#f3f3f3;">Change Made</th>' +
      buildChangedAtHeader(forDigest) +
      '<th align="left" style="background-color:#f3f3f3;">Assigned To</th>' +
      '<th align="left" style="background-color:#f3f3f3;">Attendees</th>' +
      '<th align="left" style="background-color:#f3f3f3;">Start Date/Time</th>' +
      '<th align="left" style="background-color:#f3f3f3;">End Date/Time</th>' +
      '<th align="left" style="background-color:#f3f3f3;">Contact</th>' +
      '<th align="left" style="background-color:#f3f3f3;">Household</th>' +
      '<th align="left" style="background-color:#f3f3f3;">Description</th>' +
      '</tr></thead><tbody>';
  }

  private static String buildTableRow(
    EventEmailContext context,
    Boolean forDigest
  ) {
    return '<tr>' +
      '<td>' +
      buildLinkedRecordCell(
        context.eventRecord.Id,
        displayEventSubject(context.eventRecord)
      ) +
      '</td>' +
      '<td>' +
      buildChangeMadeHtmlSummary(context.changeContext) +
      '</td>' +
      buildChangedAtCell(context.changedAtDisplay, forDigest) +
      '<td>' +
      escapeHtml(displayAssignedTo(context.eventRecord)) +
      '</td>' +
      '<td>' +
      escapeHtml(context.attendeeSummary) +
      '</td>' +
      '<td>' +
      escapeHtml(displayStartDateTime(context.eventRecord)) +
      '</td>' +
      '<td>' +
      escapeHtml(displayEndDateTime(context.eventRecord)) +
      '</td>' +
      '<td>' +
      buildContactCell(context.contactRecord) +
      '</td>' +
      '<td>' +
      buildHouseholdCell(context.householdAccount) +
      '</td>' +
      '<td>' +
      escapeHtml(displayDescription(context.eventRecord)) +
      '</td>' +
      '</tr>';
  }

  private static String buildContactCell(Contact contactRecord) {
    if (contactRecord == null) {
      return escapeHtml(NotificationConstants.DISPLAY_NOT_APPLICABLE);
    }

    return buildLinkedRecordCell(contactRecord.Id, contactRecord.Name);
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
      return forHtml ? escapeHtml('Event created') : 'Event created';
    }

    if (
      changeContext.changedFields == null ||
      changeContext.changedFields.isEmpty()
    ) {
      return forHtml ? escapeHtml('Event updated') : 'Event updated';
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

  private static String displayAssignedTo(Event eventRecord) {
    if (eventRecord == null || eventRecord.Owner == null) {
      return NotificationConstants.DISPLAY_NOT_APPLICABLE;
    }

    return String.isBlank(eventRecord.Owner.Name)
      ? NotificationConstants.DISPLAY_NOT_APPLICABLE
      : eventRecord.Owner.Name;
  }

  private static String displayStartDateTime(Event eventRecord) {
    if (eventRecord == null || eventRecord.StartDateTime == null) {
      return NotificationConstants.DISPLAY_NOT_APPLICABLE;
    }

    return eventRecord.StartDateTime.format('MM/dd/yyyy h:mm a');
  }

  private static String displayEndDateTime(Event eventRecord) {
    if (eventRecord == null || eventRecord.EndDateTime == null) {
      return NotificationConstants.DISPLAY_NOT_APPLICABLE;
    }

    return eventRecord.EndDateTime.format('MM/dd/yyyy h:mm a');
  }

  private static String displayContactName(Contact contactRecord) {
    if (contactRecord == null || String.isBlank(contactRecord.Name)) {
      return NotificationConstants.DISPLAY_NOT_APPLICABLE;
    }

    return contactRecord.Name;
  }

  private static String displayDescription(Event eventRecord) {
    if (eventRecord == null || String.isBlank(eventRecord.Description)) {
      return NotificationConstants.DISPLAY_NOT_APPLICABLE;
    }

    return eventRecord.Description.trim();
  }

  private static String displayEventSubject(Event eventRecord) {
    if (eventRecord == null) {
      return NotificationConstants.DISPLAY_NOT_APPLICABLE;
    }

    return String.isBlank(eventRecord.Subject) ? 'Event' : eventRecord.Subject;
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
      'Event notification',
      '<p>Event details are unavailable.</p>',
      'Event details are unavailable.',
      null
    );
  }
}