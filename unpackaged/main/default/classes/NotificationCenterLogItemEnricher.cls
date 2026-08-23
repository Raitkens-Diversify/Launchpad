/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-06
 *
 * Enriches notification log rows with AC1 presentation fields.
 */
public with sharing class NotificationCenterLogItemEnricher {
  private class SourcePresentation {
    public String subject;
    public String assignedTo;
    public String financialAdvisorTeamName;
    public String branchName;
    public Id branchId;
    public String branchAffiliations;
    public Id financialAdvisorTeamId;
  }

  public static void enrichItems(
    List<NotificationCenterModels.LogItem> items,
    List<Notification_Log__c> notifications
  ) {
    if (items == null || items.isEmpty()) {
      return;
    }

    Map<Id, Notification_Log__c> notificationById = new Map<Id, Notification_Log__c>();

    if (notifications != null) {
      for (Notification_Log__c notification : notifications) {
        notificationById.put(notification.Id, notification);
      }
    }

    Map<Id, SourcePresentation> presentationBySourceId = loadSourcePresentations(
      notifications
    );
    Map<Id, NotificationCenterModels.LogPresentationFields> presentationByLogId = loadPresentationFieldsByLogId(
      notifications
    );

    for (NotificationCenterModels.LogItem item : items) {
      Notification_Log__c notification = notificationById.get(item.id);
      NotificationCenterModels.LogPresentationFields presentation = presentationByLogId.get(
        item.id
      );

      if (presentation != null) {
        item.changeMade = presentation.changeMadePlainText;
        item.changeDateLabel = presentation.changedAtDisplay;
        item.changeDate = presentation.changedAtDatetime;
      } else {
        applyFallbackPresentation(item, notification);
      }

      SourcePresentation sourcePresentation = resolveSourcePresentation(
        item,
        presentationBySourceId
      );

      if (sourcePresentation != null) {
        item.subject = String.isBlank(sourcePresentation.subject)
          ? item.title
          : sourcePresentation.subject;
        item.assignedTo = sourcePresentation.assignedTo;
        item.financialAdvisorTeamName = sourcePresentation.financialAdvisorTeamName;
        item.financialAdvisorTeamId = sourcePresentation.financialAdvisorTeamId;
        item.branchName = sourcePresentation.branchName;
        item.branchId = sourcePresentation.branchId;
        item.branchAffiliations = sourcePresentation.branchAffiliations;
      } else {
        item.subject = item.title;
      }

      if (String.isBlank(item.assignedTo)) {
        item.assignedTo = NotificationConstants.DISPLAY_NOT_APPLICABLE;
      }

      if (String.isBlank(item.financialAdvisorTeamName)) {
        item.financialAdvisorTeamName = NotificationConstants.DISPLAY_NOT_APPLICABLE;
      }
    }
  }

  public static List<Notification_Log__c> filterLogsByChangeDateRange(
    List<Notification_Log__c> notifications,
    Date startDate,
    Date endDate
  ) {
    if (notifications == null || notifications.isEmpty()) {
      return new List<Notification_Log__c>();
    }

    if (startDate == null && endDate == null) {
      return notifications;
    }

    List<Notification_Log__c> filteredNotifications = new List<Notification_Log__c>();

    for (Notification_Log__c notification : notifications) {
      NotificationChangeModels.ChangeContext changeContext = NotificationChangeModels.fromJson(
        notification.Change_Context__c
      );
      Datetime changeDate = NotificationChangeModels.resolveChangedAtDatetime(
        changeContext,
        notification
      );

      if (matchesChangeDateRange(changeDate, startDate, endDate)) {
        filteredNotifications.add(notification);
      }
    }

    return filteredNotifications;
  }

  public static List<NotificationCenterModels.LogItem> applyContextFilters(
    List<NotificationCenterModels.LogItem> items,
    Date startDate,
    Date endDate,
    String searchTerm
  ) {
    if (items == null || items.isEmpty()) {
      return new List<NotificationCenterModels.LogItem>();
    }

    String normalizedSearchTerm = String.isBlank(searchTerm)
      ? null
      : searchTerm.trim().toLowerCase();
    List<NotificationCenterModels.LogItem> filteredItems = new List<NotificationCenterModels.LogItem>();

    for (NotificationCenterModels.LogItem item : items) {
      if (!matchesChangeDateRange(item.changeDate, startDate, endDate)) {
        continue;
      }

      if (
        normalizedSearchTerm != null &&
        !matchesSubjectSearchTerm(item, normalizedSearchTerm)
      ) {
        continue;
      }

      filteredItems.add(item);
    }

    return filteredItems;
  }

  public static List<NotificationCenterModels.LogItem> applyFacetFilters(
    List<NotificationCenterModels.LogItem> items,
    List<String> selectedHouseholdIds,
    List<String> selectedBranchNames
  ) {
    if (items == null || items.isEmpty()) {
      return new List<NotificationCenterModels.LogItem>();
    }

    Set<String> householdFilter = normalizeHouseholdFilter(selectedHouseholdIds);
    Set<String> branchFilter = normalizeBranchNameFilter(selectedBranchNames);
    List<NotificationCenterModels.LogItem> filteredItems = new List<NotificationCenterModels.LogItem>();

    for (NotificationCenterModels.LogItem item : items) {
      if (
        !householdFilter.isEmpty() &&
        !matchesHouseholdFilter(item, householdFilter)
      ) {
        continue;
      }

      if (!branchFilter.isEmpty() && !matchesBranchNameFilter(item, branchFilter)) {
        continue;
      }

      filteredItems.add(item);
    }

    return filteredItems;
  }

  public static void collectFilterOptions(
    List<NotificationCenterModels.LogItem> items,
    Map<String, NotificationCenterModels.FilterOption> householdOptionsByValue,
    Map<String, NotificationCenterModels.FilterOption> branchOptionsByValue
  ) {
    if (items == null || items.isEmpty()) {
      return;
    }

    if (householdOptionsByValue == null) {
      householdOptionsByValue = new Map<String, NotificationCenterModels.FilterOption>();
    }

    if (branchOptionsByValue == null) {
      branchOptionsByValue = new Map<String, NotificationCenterModels.FilterOption>();
    }

    for (NotificationCenterModels.LogItem item : items) {
      if (item == null) {
        continue;
      }

      if (item.householdId != null && !String.isBlank(item.householdName)) {
        String householdKey = String.valueOf(item.householdId);

        if (!householdOptionsByValue.containsKey(householdKey)) {
          householdOptionsByValue.put(
            householdKey,
            new NotificationCenterModels.FilterOption(
              householdKey,
              item.householdName
            )
          );
        }
      }

      if (
        !String.isBlank(item.branchName) &&
        item.branchName != NotificationConstants.DISPLAY_NOT_APPLICABLE
      ) {
        String branchKey = item.branchName.trim().toLowerCase();

        if (!branchOptionsByValue.containsKey(branchKey)) {
          branchOptionsByValue.put(
            branchKey,
            new NotificationCenterModels.FilterOption(
              item.branchName.trim(),
              item.branchName.trim()
            )
          );
        }
      }
    }
  }

  public static List<NotificationCenterModels.LogItem> applyPresentationFilters(
    List<NotificationCenterModels.LogItem> items,
    Date startDate,
    Date endDate,
    String branchFilter,
    String searchTerm
  ) {
    List<NotificationCenterModels.LogItem> contextFilteredItems = applyContextFilters(
      items,
      startDate,
      endDate,
      searchTerm
    );
    List<String> selectedBranchNames = String.isBlank(branchFilter) ||
      branchFilter == NotificationConstants.LOG_BRANCH_ALL
      ? new List<String>()
      : new List<String>{ branchFilter };

    return applyFacetFilters(contextFilteredItems, new List<String>(), selectedBranchNames);
  }

  public static String buildPresentationDedupKey(
    NotificationCenterModels.LogItem item,
    Notification_Log__c notification
  ) {
    String baseCorrelationKey = resolveBaseCorrelationKey(notification);

    if (!String.isBlank(baseCorrelationKey)) {
      return String.valueOf(item.recipientId) + '|' + baseCorrelationKey;
    }

    String changedAtKey = item.changeDate == null
      ? ''
      : String.valueOf(item.changeDate.getTime());

    return String.join(
      new List<String>{
        item.recipientId == null ? '' : String.valueOf(item.recipientId),
        item.sourceRecordId == null ? '' : item.sourceRecordId,
        item.sourceType == null ? '' : item.sourceType,
        changedAtKey,
        item.changeMade == null ? '' : item.changeMade
      },
      '|'
    );
  }

  public static void sortBatchItemsByChannelPreference(
    List<NotificationCenterModels.LogItem> items,
    Map<Id, Notification_Log__c> notificationById
  ) {
    if (items == null || items.size() < 2) {
      return;
    }

    items.sort(new LogItemChannelPreferenceComparator(notificationById));
  }

  private static String resolveBaseCorrelationKey(
    Notification_Log__c notification
  ) {
    if (
      notification == null ||
      !notification.getPopulatedFieldsAsMap().containsKey('Correlation_Key__c') ||
      String.isBlank(notification.Correlation_Key__c)
    ) {
      return null;
    }

    String correlationKey = notification.Correlation_Key__c;

    for (String channelName : NotificationConstants.CHANNEL_ORDER) {
      String suffix = '-' + channelName;

      if (correlationKey.endsWith(suffix)) {
        return correlationKey.substring(0, correlationKey.length() - suffix.length());
      }
    }

    return correlationKey;
  }

  private class LogItemChannelPreferenceComparator implements Comparator<NotificationCenterModels.LogItem> {
    private final Map<Id, Notification_Log__c> notificationById;

    private LogItemChannelPreferenceComparator(
      Map<Id, Notification_Log__c> notificationById
    ) {
      this.notificationById = notificationById;
    }

    public Integer compare(
      NotificationCenterModels.LogItem first,
      NotificationCenterModels.LogItem second
    ) {
      Integer firstRank = channelRank(first);
      Integer secondRank = channelRank(second);

      if (firstRank == secondRank) {
        return 0;
      }

      return firstRank < secondRank ? -1 : 1;
    }

    private Integer channelRank(NotificationCenterModels.LogItem item) {
      if (item == null || item.id == null || notificationById == null) {
        return 99;
      }

      Notification_Log__c notification = notificationById.get(item.id);

      if (
        notification != null &&
        notification.Channel__c == NotificationConstants.CHANNEL_IN_APP
      ) {
        return 0;
      }

      if (
        notification != null &&
        notification.Channel__c == NotificationConstants.CHANNEL_EMAIL
      ) {
        return 1;
      }

      return 2;
    }
  }

  private static Map<Id, NotificationCenterModels.LogPresentationFields> loadPresentationFieldsByLogId(
    List<Notification_Log__c> notifications
  ) {
    Map<Id, NotificationCenterModels.LogPresentationFields> presentationByLogId = new Map<Id, NotificationCenterModels.LogPresentationFields>();

    if (notifications == null || notifications.isEmpty()) {
      return presentationByLogId;
    }

    List<Notification_Log__c> caseLogs = new List<Notification_Log__c>();
    List<Notification_Log__c> taskLogs = new List<Notification_Log__c>();
    List<Notification_Log__c> eventLogs = new List<Notification_Log__c>();

    for (Notification_Log__c notification : notifications) {
      if (notification == null || notification.Id == null) {
        continue;
      }

      if (
        notification.Source_Type__c == NotificationConstants.OBJECT_TYPE_CASE
      ) {
        caseLogs.add(notification);
      } else if (
        notification.Source_Type__c == NotificationConstants.OBJECT_TYPE_TASK
      ) {
        taskLogs.add(notification);
      } else if (
        notification.Source_Type__c == NotificationConstants.OBJECT_TYPE_EVENT
      ) {
        eventLogs.add(notification);
      }
    }

    presentationByLogId.putAll(
      NotificationCaseEmailContentService.loadPresentationFieldsForLogs(caseLogs)
    );
    presentationByLogId.putAll(
      NotificationTaskEmailContentService.loadPresentationFieldsForLogs(taskLogs)
    );
    presentationByLogId.putAll(
      NotificationEventEmailContentService.loadPresentationFieldsForLogs(eventLogs)
    );

    return presentationByLogId;
  }

  private static void applyFallbackPresentation(
    NotificationCenterModels.LogItem item,
    Notification_Log__c notification
  ) {
    NotificationChangeModels.ChangeContext changeContext = NotificationChangeModels.fromJson(
      item.changeContext
    );

    item.changeMade = NotificationChangeSummaryBuilder.buildPlainTextSummary(
      changeContext,
      item.sourceType
    );
    item.changeDateLabel = NotificationChangeModels.formatChangedAtDisplay(
      changeContext,
      notification
    );
    item.changeDate = NotificationChangeModels.resolveChangedAtDatetime(
      changeContext,
      notification
    );
  }

  private static SourcePresentation resolveSourcePresentation(
    NotificationCenterModels.LogItem item,
    Map<Id, SourcePresentation> presentationBySourceId
  ) {
    if (item == null || String.isBlank(item.sourceRecordId)) {
      return null;
    }

    try {
      return presentationBySourceId.get((Id) item.sourceRecordId);
    } catch (Exception error) {
      return null;
    }
  }

  private static Map<Id, SourcePresentation> loadSourcePresentations(
    List<Notification_Log__c> notifications
  ) {
    Map<Id, SourcePresentation> presentationBySourceId = new Map<Id, SourcePresentation>();

    if (notifications == null || notifications.isEmpty()) {
      return presentationBySourceId;
    }

    Set<Id> caseIds = new Set<Id>();
    Set<Id> taskIds = new Set<Id>();
    Set<Id> eventIds = new Set<Id>();
    Set<Id> householdIds = new Set<Id>();

    for (Notification_Log__c notification : notifications) {
      if (String.isBlank(notification.Source_Record_Id__c)) {
        continue;
      }

      Id sourceRecordId;

      try {
        sourceRecordId = (Id) notification.Source_Record_Id__c;
      } catch (Exception error) {
        continue;
      }

      if (notification.Source_Type__c == NotificationConstants.OBJECT_TYPE_CASE) {
        caseIds.add(sourceRecordId);
      } else if (
        notification.Source_Type__c == NotificationConstants.OBJECT_TYPE_TASK
      ) {
        taskIds.add(sourceRecordId);
      } else if (
        notification.Source_Type__c == NotificationConstants.OBJECT_TYPE_EVENT
      ) {
        eventIds.add(sourceRecordId);
      }

      if (notification.Household__c != null) {
        householdIds.add(notification.Household__c);
      }
    }

    Map<Id, Account> householdById = queryHouseholdAccounts(householdIds);
    Map<Id, Case> caseById = queryCases(caseIds);
    Map<Id, Task> taskById = new Map<Id, Task>();

    if (!taskIds.isEmpty()) {
      Set<Id> relatedCaseIds = new Set<Id>();
      Set<Id> relatedHouseholdIds = new Set<Id>();

      for (Task taskRecord : [
        SELECT Id, Subject, Owner.Name, WhatId
        FROM Task
        WHERE Id IN :taskIds
      ]) {
        taskById.put(taskRecord.Id, taskRecord);

        if (taskRecord.WhatId == null) {
          continue;
        }

        String prefix = String.valueOf(taskRecord.WhatId).substring(0, 3);

        if (prefix == '500') {
          relatedCaseIds.add(taskRecord.WhatId);
        } else if (prefix == '001') {
          relatedHouseholdIds.add(taskRecord.WhatId);
        }
      }

      relatedCaseIds.removeAll(caseById.keySet());
      caseById.putAll(queryCases(relatedCaseIds));
      relatedHouseholdIds.removeAll(householdById.keySet());
      householdById.putAll(queryHouseholdAccounts(relatedHouseholdIds));

      for (Task taskRecord : taskById.values()) {
        Case relatedCase = null;
        Account relatedHousehold = null;

        if (taskRecord.WhatId != null) {
          String prefix = String.valueOf(taskRecord.WhatId).substring(0, 3);

          if (prefix == '500') {
            relatedCase = caseById.get(taskRecord.WhatId);
          } else if (prefix == '001') {
            relatedHousehold = householdById.get(taskRecord.WhatId);
          }
        }

        presentationBySourceId.put(
          taskRecord.Id,
          buildTaskPresentation(taskRecord, relatedCase, relatedHousehold)
        );
      }
    }

    if (!eventIds.isEmpty()) {
      Map<Id, Event> eventById = new Map<Id, Event>();
      Set<Id> eventHouseholdIds = new Set<Id>();

      for (Event eventRecord : [
        SELECT Id, Subject, Owner.Name, WhatId
        FROM Event
        WHERE Id IN :eventIds
      ]) {
        eventById.put(eventRecord.Id, eventRecord);

        if (
          eventRecord.WhatId != null &&
          String.valueOf(eventRecord.WhatId).substring(0, 3) == '001'
        ) {
          eventHouseholdIds.add(eventRecord.WhatId);
        }
      }

      eventHouseholdIds.removeAll(householdById.keySet());
      householdById.putAll(queryHouseholdAccounts(eventHouseholdIds));

      for (Event eventRecord : eventById.values()) {
        Account relatedHousehold = resolveEventHousehold(
          eventRecord,
          householdById
        );
        presentationBySourceId.put(
          eventRecord.Id,
          buildEventPresentation(eventRecord, relatedHousehold)
        );
      }
    }

    for (Id caseId : caseIds) {
      Case caseRecord = caseById.get(caseId);

      if (caseRecord != null) {
        presentationBySourceId.put(caseId, buildCasePresentation(caseRecord));
      }
    }

    return presentationBySourceId;
  }

  private static Map<Id, Case> queryCases(Set<Id> caseIds) {
    Map<Id, Case> caseById = new Map<Id, Case>();

    if (caseIds == null || caseIds.isEmpty()) {
      return caseById;
    }

    for (Case caseRecord : [
      SELECT
        Id,
        Subject,
        Owner.Name,
        Financial_Advisor_Team__r.Name,
        Financial_Advisor_Team__r.Advisor_Group__r.Name,
        Financial_Advisor_Team__r.Advisor_Group__r.Id
      FROM Case
      WHERE Id IN :caseIds
    ]) {
      caseById.put(caseRecord.Id, caseRecord);
    }

    return caseById;
  }

  private static Map<Id, Account> queryHouseholdAccounts(Set<Id> householdIds) {
    Map<Id, Account> householdById = new Map<Id, Account>();

    if (householdIds == null || householdIds.isEmpty()) {
      return householdById;
    }

    for (Account householdAccount : [
      SELECT
        Id,
        Name,
        Financial_Advisor_Team__r.Name,
        Financial_Advisor_Team__r.Advisor_Group__r.Name,
        Financial_Advisor_Team__r.Advisor_Group__r.Id
      FROM Account
      WHERE Id IN :householdIds
    ]) {
      householdById.put(householdAccount.Id, householdAccount);
    }

    return householdById;
  }

  private static Account resolveEventHousehold(
    Event eventRecord,
    Map<Id, Account> householdById
  ) {
    if (eventRecord == null || eventRecord.WhatId == null) {
      return null;
    }

    if (String.valueOf(eventRecord.WhatId).substring(0, 3) != '001') {
      return null;
    }

    Account relatedHousehold = householdById.get(eventRecord.WhatId);

    if (relatedHousehold != null) {
      return relatedHousehold;
    }

    return null;
  }

  private static SourcePresentation buildCasePresentation(Case caseRecord) {
    return buildPresentationFromTeamSource(
      caseRecord.Subject,
      caseRecord.Owner == null ? null : caseRecord.Owner.Name,
      caseRecord.Financial_Advisor_Team__r
    );
  }

  private static SourcePresentation buildTaskPresentation(
    Task taskRecord,
    Case relatedCase,
    Account relatedHousehold
  ) {
    Financial_Advisor_Team__c advisorTeam = relatedCase == null
      ? null
      : relatedCase.Financial_Advisor_Team__r;

    if (advisorTeam == null && relatedHousehold != null) {
      advisorTeam = relatedHousehold.Financial_Advisor_Team__r;
    }

    return buildPresentationFromTeamSource(
      taskRecord.Subject,
      taskRecord.Owner == null ? null : taskRecord.Owner.Name,
      advisorTeam
    );
  }

  private static SourcePresentation buildEventPresentation(
    Event eventRecord,
    Account relatedHousehold
  ) {
    return buildPresentationFromTeamSource(
      eventRecord.Subject,
      eventRecord.Owner == null ? null : eventRecord.Owner.Name,
      relatedHousehold == null ? null : relatedHousehold.Financial_Advisor_Team__r
    );
  }

  private static SourcePresentation buildPresentationFromTeamSource(
    String subject,
    String assignedTo,
    Financial_Advisor_Team__c advisorTeam
  ) {
    SourcePresentation presentation = new SourcePresentation();
    presentation.subject = subject;
    presentation.assignedTo = assignedTo;
    presentation.financialAdvisorTeamName = advisorTeam == null
      ? null
      : advisorTeam.Name;
    presentation.financialAdvisorTeamId = advisorTeam == null
      ? null
      : advisorTeam.Id;
    presentation.branchName = advisorTeam == null ||
      advisorTeam.Advisor_Group__r == null
      ? null
      : advisorTeam.Advisor_Group__r.Name;
    presentation.branchId = advisorTeam == null ||
      advisorTeam.Advisor_Group__r == null
      ? null
      : advisorTeam.Advisor_Group__r.Id;
    presentation.branchAffiliations = presentation.branchName;
    return presentation;
  }

  private static Boolean matchesChangeDateRange(
    Datetime changeDate,
    Date startDate,
    Date endDate
  ) {
    if (startDate == null && endDate == null) {
      return true;
    }

    if (changeDate == null) {
      return false;
    }

    Date changeDateValue = changeDate.date();

    if (startDate != null && changeDateValue < startDate) {
      return false;
    }

    if (endDate != null && changeDateValue > endDate) {
      return false;
    }

    return true;
  }

  private static Set<String> normalizeHouseholdFilter(List<String> selectedHouseholdIds) {
    Set<String> householdFilter = new Set<String>();

    if (selectedHouseholdIds == null || selectedHouseholdIds.isEmpty()) {
      return householdFilter;
    }

    for (String householdId : selectedHouseholdIds) {
      if (!String.isBlank(householdId)) {
        householdFilter.add(householdId.trim());
      }
    }

    return householdFilter;
  }

  private static Set<String> normalizeBranchNameFilter(
    List<String> selectedBranchNames
  ) {
    Set<String> branchFilter = new Set<String>();

    if (selectedBranchNames == null || selectedBranchNames.isEmpty()) {
      return branchFilter;
    }

    for (String branchName : selectedBranchNames) {
      if (!String.isBlank(branchName)) {
        branchFilter.add(branchName.trim().toLowerCase());
      }
    }

    return branchFilter;
  }

  private static Boolean matchesHouseholdFilter(
    NotificationCenterModels.LogItem item,
    Set<String> householdFilter
  ) {
    if (item == null || item.householdId == null) {
      return false;
    }

    return householdFilter.contains(String.valueOf(item.householdId));
  }

  private static Boolean matchesBranchNameFilter(
    NotificationCenterModels.LogItem item,
    Set<String> branchFilter
  ) {
    if (item == null || String.isBlank(item.branchName)) {
      return false;
    }

    if (item.branchName == NotificationConstants.DISPLAY_NOT_APPLICABLE) {
      return false;
    }

    return branchFilter.contains(item.branchName.trim().toLowerCase());
  }

  private static Boolean matchesSubjectSearchTerm(
    NotificationCenterModels.LogItem item,
    String normalizedSearchTerm
  ) {
    List<String> candidates = new List<String>{ item.subject, item.title };

    for (String candidate : candidates) {
      if (
        !String.isBlank(candidate) &&
        candidate.toLowerCase().contains(normalizedSearchTerm)
      ) {
        return true;
      }
    }

    return false;
  }

  private static Boolean matchesSearchTerm(
    NotificationCenterModels.LogItem item,
    String normalizedSearchTerm
  ) {
    return matchesSubjectSearchTerm(item, normalizedSearchTerm);
  }
}