/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-16
 *
 * Service layer for notification center reads and writes. Accepts an explicit
 * recipient id so dashboard, log, inbox, and future screens can share the same
 * logic for any user context.
 */
public with sharing class NotificationCenterService {
  private static final Integer DEFAULT_INBOX_PAGE_SIZE = 25;
  private static final Integer DEFAULT_LOG_PAGE_SIZE = 50;
  private static final Integer MAX_PAGE_SIZE = 100;
  private static final Integer DASHBOARD_RECENT_EVENT_LIMIT = 5;
  private static final Integer MAX_PRESENTATION_SCAN_BATCHES = 15;
  private static final Integer PRESENTATION_SOQL_GUARD = 85;

  private final NotificationLogRepository logRepository;
  private final NotificationPreferenceRepository preferenceRepository;

  public NotificationCenterService() {
    this(new NotificationLogRepository(), new NotificationPreferenceRepository());
  }

  @TestVisible
  private NotificationCenterService(
    NotificationLogRepository logRepository,
    NotificationPreferenceRepository preferenceRepository
  ) {
    this.logRepository = logRepository;
    this.preferenceRepository = preferenceRepository;
  }

  public NotificationCenterModels.InboxPageResult getInbox(
    Id recipientId,
    String filterName,
    String searchTerm,
    Integer pageSize,
    Id lastSeenId,
    String sortDirection
  ) {
    Id resolvedRecipientId = resolveRecipientId(recipientId);
    Integer limitSize = resolvePageSize(pageSize, DEFAULT_INBOX_PAGE_SIZE);
    NotificationLogRepository.NotificationLogQuery query = buildInboxQuery(
      resolvedRecipientId,
      filterName,
      searchTerm,
      limitSize,
      lastSeenId,
      sortDirection
    );

    List<NotificationCenterModels.InboxItem> items = new List<NotificationCenterModels.InboxItem>();
    for (Notification_Log__c notification : logRepository.selectLogs(query)) {
      items.add(toInboxItem(notification));
    }

    NotificationCenterModels.InboxPageResult result = new NotificationCenterModels.InboxPageResult();
    result.items = items;
    result.stats = logRepository.selectInboxStats(resolvedRecipientId);
    result.hasMore = items.size() >= limitSize;
    return result;
  }

  public NotificationCenterModels.LogPageResult getNotificationLog(
    Id recipientId,
    String statusFilter,
    String categoryFilter,
    Integer pageSize,
    Id lastSeenId,
    Date startDate,
    Date endDate,
    String searchTerm,
    String sourceTypeFilter,
    List<String> selectedHouseholdIds,
    List<String> selectedBranchNames,
    Boolean presentationMode
  ) {
    Id resolvedRecipientId = resolveRecipientId(recipientId);
    Integer limitSize = resolvePageSize(pageSize, DEFAULT_LOG_PAGE_SIZE);
    Boolean usePresentationMode = presentationMode == true;

    if (usePresentationMode) {
      return getPresentationLogPage(
        resolvedRecipientId,
        statusFilter,
        categoryFilter,
        limitSize,
        lastSeenId,
        startDate,
        endDate,
        searchTerm,
        sourceTypeFilter,
        selectedHouseholdIds,
        selectedBranchNames
      );
    }

    NotificationLogRepository.NotificationLogQuery query = buildLogQuery(
      resolvedRecipientId,
      statusFilter,
      categoryFilter,
      limitSize,
      lastSeenId,
      startDate,
      endDate,
      searchTerm,
      sourceTypeFilter,
      'newest'
    );

    List<Notification_Log__c> notifications = logRepository.selectLogs(query);
    Map<Id, String> changeContextByLogId = NotificationChangeModels.enrichChangeContextsForDisplay(
      notifications
    );

    List<NotificationCenterModels.LogItem> items = new List<NotificationCenterModels.LogItem>();
    for (Notification_Log__c notification : notifications) {
      items.add(toLogItem(notification, changeContextByLogId));
    }

    NotificationCenterModels.LogPageResult result = new NotificationCenterModels.LogPageResult();
    result.items = items;
    result.filteredTotalCount = logRepository.countLogs(query);
    result.hasMore = notifications.size() >= limitSize;
    return result;
  }

  private NotificationCenterModels.LogPageResult getPresentationLogPage(
    Id recipientId,
    String statusFilter,
    String categoryFilter,
    Integer pageSize,
    Id lastSeenId,
    Date startDate,
    Date endDate,
    String searchTerm,
    String sourceTypeFilter,
    List<String> selectedHouseholdIds,
    List<String> selectedBranchNames
  ) {
    List<NotificationCenterModels.LogItem> filteredItems = new List<NotificationCenterModels.LogItem>();
    Id cursorLastSeenId = lastSeenId;
    Id nextLastSeenId = null;
    Boolean hasMoreBatches = false;
    Integer scanCount = 0;
    Set<String> seenPresentationKeys = new Set<String>();
    Map<String, NotificationCenterModels.FilterOption> householdOptionsByValue = new Map<String, NotificationCenterModels.FilterOption>();
    Map<String, NotificationCenterModels.FilterOption> branchOptionsByValue = new Map<String, NotificationCenterModels.FilterOption>();

    while (scanCount < MAX_PRESENTATION_SCAN_BATCHES) {
      if (Limits.getQueries() >= PRESENTATION_SOQL_GUARD) {
        hasMoreBatches = true;
        break;
      }

      NotificationLogRepository.NotificationLogQuery query = buildLogQuery(
        recipientId,
        statusFilter,
        categoryFilter,
        pageSize,
        cursorLastSeenId,
        null,
        null,
        null,
        sourceTypeFilter,
        'newest'
      );

      List<Notification_Log__c> notifications = logRepository.selectLogs(query);

      if (notifications.isEmpty()) {
        hasMoreBatches = false;
        break;
      }

      List<Notification_Log__c> notificationsToEnrich = NotificationCenterLogItemEnricher.filterLogsByChangeDateRange(
        notifications,
        startDate,
        endDate
      );

      if (!notificationsToEnrich.isEmpty()) {
        Map<Id, Notification_Log__c> notificationById = new Map<Id, Notification_Log__c>(
          notificationsToEnrich
        );
        List<NotificationCenterModels.LogItem> batchItems = buildPresentationBatchItems(
          notificationsToEnrich
        );

        NotificationCenterLogItemEnricher.enrichItems(
          batchItems,
          notificationsToEnrich
        );
        List<NotificationCenterModels.LogItem> contextFilteredItems = NotificationCenterLogItemEnricher.applyContextFilters(
          batchItems,
          startDate,
          endDate,
          searchTerm
        );
        NotificationCenterLogItemEnricher.collectFilterOptions(
          contextFilteredItems,
          householdOptionsByValue,
          branchOptionsByValue
        );
        batchItems = NotificationCenterLogItemEnricher.applyFacetFilters(
          contextFilteredItems,
          selectedHouseholdIds,
          selectedBranchNames
        );
        NotificationCenterLogItemEnricher.sortBatchItemsByChannelPreference(
          batchItems,
          notificationById
        );

        for (NotificationCenterModels.LogItem batchItem : batchItems) {
          String dedupKey = NotificationCenterLogItemEnricher.buildPresentationDedupKey(
            batchItem,
            notificationById.get(batchItem.id)
          );

          if (seenPresentationKeys.contains(dedupKey)) {
            continue;
          }

          seenPresentationKeys.add(dedupKey);

          if (filteredItems.size() < pageSize) {
            filteredItems.add(batchItem);
          }
        }
      }

      nextLastSeenId = notifications[notifications.size() - 1].Id;
      cursorLastSeenId = nextLastSeenId;
      scanCount++;
      hasMoreBatches = notifications.size() >= pageSize;

      if (!hasMoreBatches) {
        break;
      }
    }

    sortLogItemsByChangeDateAscending(filteredItems);

    NotificationCenterModels.LogPageResult result = new NotificationCenterModels.LogPageResult();
    result.items = filteredItems;
    result.filteredTotalCount = seenPresentationKeys.size();
    result.hasMore = hasMoreBatches;
    result.nextLastSeenId = hasMoreBatches ? nextLastSeenId : null;
    result.householdOptions = sortFilterOptions(householdOptionsByValue);
    result.branchOptions = sortFilterOptions(branchOptionsByValue);
    return result;
  }

  private static List<NotificationCenterModels.FilterOption> sortFilterOptions(
    Map<String, NotificationCenterModels.FilterOption> optionsByValue
  ) {
    List<NotificationCenterModels.FilterOption> options = optionsByValue == null
      ? new List<NotificationCenterModels.FilterOption>()
      : optionsByValue.values();

    options.sort(new FilterOptionLabelComparator());
    return options;
  }

  private class FilterOptionLabelComparator implements Comparator<NotificationCenterModels.FilterOption> {
    public Integer compare(
      NotificationCenterModels.FilterOption first,
      NotificationCenterModels.FilterOption second
    ) {
      String firstLabel = first == null || first.label == null ? '' : first.label;
      String secondLabel = second == null || second.label == null
        ? ''
        : second.label;
      return firstLabel.toLowerCase().compareTo(secondLabel.toLowerCase());
    }
  }

  private List<NotificationCenterModels.LogItem> buildPresentationBatchItems(
    List<Notification_Log__c> notifications
  ) {
    List<NotificationCenterModels.LogItem> batchItems = new List<NotificationCenterModels.LogItem>();

    for (Notification_Log__c notification : notifications) {
      batchItems.add(toLogItem(notification, null));
    }

    return batchItems;
  }

  public NotificationCenterModels.DashboardResult getDashboard(Id recipientId) {
    Id resolvedRecipientId = resolveRecipientId(recipientId);

    NotificationLogRepository.NotificationLogQuery query = buildLogQuery(
      resolvedRecipientId,
      NotificationConstants.LOG_STATUS_ALL,
      NotificationConstants.LOG_CATEGORY_ALL,
      DASHBOARD_RECENT_EVENT_LIMIT,
      null,
      null,
      null,
      null,
      null,
      'newest'
    );

    List<Notification_Log__c> notifications = logRepository.selectLogs(query);
    Map<Id, String> changeContextByLogId = NotificationChangeModels.enrichChangeContextsForDisplay(
      notifications
    );

    List<NotificationCenterModels.LogItem> recentEvents = new List<NotificationCenterModels.LogItem>();
    for (Notification_Log__c notification : notifications) {
      recentEvents.add(toLogItem(notification, changeContextByLogId));
    }

    NotificationCenterModels.DashboardStats stats = logRepository.selectDashboardStats(
      resolvedRecipientId
    );
    stats.nextDigestRunLabel = NotificationDigestScheduleService.resolveNextDigestRunLabel(
      resolvedRecipientId,
      stats.queuedCount
    );
    stats.digestTimezoneLabel = NotificationDigestTimezoneService.getDigestTimezoneLabel();
    stats.digestTimezoneAbbreviation = NotificationDigestTimezoneService.getDigestTimezoneAbbreviation();

    NotificationCenterModels.DashboardResult result = new NotificationCenterModels.DashboardResult();
    result.stats = stats;
    result.channelDelivery = logRepository.selectTodayChannelDelivery(resolvedRecipientId);
    result.recentEvents = recentEvents;
    result.upcomingDigests = buildUpcomingDigests(resolvedRecipientId, stats);
    return result;
  }

  public Integer getUnreadCount(Id recipientId) {
    return logRepository.countUnread(resolveRecipientId(recipientId));
  }

  public Integer markAsRead(Id recipientId, List<Id> notificationIds) {
    return logRepository.markAsRead(resolveRecipientId(recipientId), notificationIds);
  }

  public Integer markAllAsRead(Id recipientId) {
    return logRepository.markAllAsRead(resolveRecipientId(recipientId));
  }

  public List<Notification_Rule__c> getUserDefaultPreferences(Id userId) {
    return preferenceRepository.selectUserDefaultPreferences(resolveRecipientId(userId));
  }

  public List<NotificationCenterModels.RuleItem> getNotificationRules(Id userId) {
    return getNotificationRules(userId, null);
  }

  public List<NotificationCenterModels.RuleItem> getNotificationRules(
    Id userId,
    Id householdId
  ) {
    Id resolvedUserId = resolveRecipientId(userId);
    List<NotificationCenterModels.RuleItem> items = new List<NotificationCenterModels.RuleItem>();

    if (householdId != null) {
      for (Notification_Rule__c rule : preferenceRepository.selectRulesForUserAndHousehold(
        resolvedUserId,
        householdId
      )) {
        items.add(toRuleItem(rule, false));
      }

      return items;
    }

    List<Notification_Rule__c> userRules = preferenceRepository.selectRulesForUser(
      resolvedUserId
    );

    for (Notification_Rule__c rule : userRules) {
      items.add(toRuleItem(rule, false));
    }

    for (Notification_Rule__c systemRule : preferenceRepository.selectSystemDefaultRules()) {
      items.add(toRuleItem(systemRule, true));
    }

    return items;
  }

  public List<NotificationCenterModels.RuleItem> getSystemDefaultRules() {
    assertAdminAccess();

    List<NotificationCenterModels.RuleItem> items = new List<NotificationCenterModels.RuleItem>();

    for (Notification_Rule__c rule : preferenceRepository.selectSystemDefaultRules()) {
      items.add(toRuleItem(rule, false));
    }

    return items;
  }

  public NotificationCenterModels.RuleItem saveSystemDefaultRule(
    NotificationCenterModels.RuleInput input
  ) {
    assertAdminAccess();

    if (input == null) {
      throw new IllegalArgumentException('Rule input is required.');
    }

    NotificationPreferenceAdminService adminService = new NotificationPreferenceAdminService();
    Notification_Rule__c rule = buildSystemDefaultFromInput(input);
    Notification_Rule__c savedRule = adminService.saveSystemDefault(
      rule,
      input.id != null
    );
    Notification_Rule__c hydratedRule = preferenceRepository.selectSystemDefaultRule(
      savedRule.Id
    );

    return toRuleItem(hydratedRule, false);
  }

  public void deleteSystemDefaultRule(Id ruleId) {
    assertAdminAccess();

    Notification_Rule__c rule = preferenceRepository.selectSystemDefaultRule(ruleId);

    if (rule == null) {
      throw new IllegalArgumentException('System default rule was not found.');
    }

    delete rule;
  }

  public NotificationCenterModels.RuleItem saveNotificationRule(
    Id userId,
    NotificationCenterModels.RuleInput input
  ) {
    if (input == null) {
      throw new IllegalArgumentException('Rule input is required.');
    }

    Id resolvedUserId = resolveRecipientId(userId);
    NotificationPreferenceAdminService adminService = new NotificationPreferenceAdminService();
    Notification_Rule__c rule = buildRuleFromInput(resolvedUserId, input);

    if (input.id != null) {
      Notification_Rule__c existingRule = preferenceRepository.selectRuleById(input.id);

      if (existingRule != null && existingRule.Is_System_Default__c == true) {
        throw new IllegalArgumentException('System default rules cannot be edited.');
      }
    }

    Notification_Rule__c savedRule = adminService.saveScopedPreference(
      rule,
      input.id != null
    );
    Notification_Rule__c hydratedRule = preferenceRepository.selectRuleForUser(
      savedRule.Id,
      resolvedUserId
    );

    return toRuleItem(hydratedRule, false);
  }

  public NotificationCenterModels.RuleItem toggleNotificationRule(
    Id userId,
    Id ruleId,
    Boolean isActive
  ) {
    Id resolvedUserId = resolveRecipientId(userId);
    Notification_Rule__c rule = preferenceRepository.selectRuleById(ruleId);

    if (rule == null) {
      throw new IllegalArgumentException('Notification rule was not found.');
    }

    if (rule.Is_System_Default__c == true) {
      if (!hasAdminAccess()) {
        throw new IllegalArgumentException(
          'System default rules cannot be modified by users.'
        );
      }

      rule.Is_Active__c = isActive == true;
      update rule;

      return toRuleItem(
        preferenceRepository.selectSystemDefaultRule(rule.Id),
        false
      );
    }

    Notification_Rule__c userRule = preferenceRepository.selectRuleForUser(
      ruleId,
      resolvedUserId
    );

    if (userRule == null) {
      throw new IllegalArgumentException('Notification rule was not found.');
    }

    userRule.Is_Active__c = isActive == true;
    update userRule;

    return toRuleItem(
      preferenceRepository.selectRuleForUser(ruleId, resolvedUserId),
      false
    );
  }

  public void deleteNotificationRule(Id userId, Id ruleId) {
    Id resolvedUserId = resolveRecipientId(userId);
    Notification_Rule__c rule = preferenceRepository.selectRuleById(ruleId);

    if (rule != null && rule.Is_System_Default__c == true) {
      throw new IllegalArgumentException('System default rules cannot be deleted.');
    }

    Notification_Rule__c userRule = preferenceRepository.selectRuleForUser(
      ruleId,
      resolvedUserId
    );

    if (userRule == null) {
      throw new IllegalArgumentException('Notification rule was not found.');
    }

    delete userRule;
  }

  private static Boolean hasAdminAccess() {
    return NotificationConstants.isRunningUserSystemAdministrator();
  }

  private static void assertAdminAccess() {
    if (!hasAdminAccess()) {
      throw new AuraHandledException(
        'Only System Administrators can manage system default notification rules.'
      );
    }
  }

  private static Id resolveRecipientId(Id recipientId) {
    if (recipientId == null) {
      throw new IllegalArgumentException('Recipient Id is required.');
    }

    return recipientId;
  }

  private static Integer resolvePageSize(Integer pageSize, Integer defaultPageSize) {
    if (pageSize == null || pageSize < 1) {
      return defaultPageSize;
    }

    return Math.min(pageSize, MAX_PAGE_SIZE);
  }

  private static NotificationLogRepository.NotificationLogQuery buildInboxQuery(
    Id recipientId,
    String filterName,
    String searchTerm,
    Integer pageSize,
    Id lastSeenId,
    String sortDirection
  ) {
    NotificationLogRepository.NotificationLogQuery query = new NotificationLogRepository.NotificationLogQuery();
    query.recipientId = recipientId;
    query.channels = new Set<String>{ NotificationConstants.CHANNEL_IN_APP };
    query.statuses = new Set<String>{ NotificationConstants.STATUS_SENT };
    query.searchTerm = searchTerm;
    query.pageSize = pageSize;
    query.lastSeenId = lastSeenId;
    query.sortDirection = sortDirection;
    query.fieldSet = NotificationLogRepository.FieldSet.INBOX;

    String normalizedFilter = normalizeInboxFilter(filterName);
    if (normalizedFilter == 'UNREAD') {
      query.unreadOnly = true;
    } else if (normalizedFilter != 'ALL') {
      query.sourceType = normalizedFilter;
    }

    return query;
  }

  private static NotificationLogRepository.NotificationLogQuery buildLogQuery(
    Id recipientId,
    String statusFilter,
    String categoryFilter,
    Integer pageSize,
    Id lastSeenId,
    Date startDate,
    Date endDate,
    String searchTerm,
    String sourceTypeFilter,
    String sortDirection
  ) {
    NotificationLogRepository.NotificationLogQuery query = new NotificationLogRepository.NotificationLogQuery();
    query.recipientId = recipientId;
    query.statuses = resolveLogStatuses(statusFilter);
    query.categoryFilter = normalizeLogCategoryFilter(categoryFilter);
    query.pageSize = pageSize;
    query.lastSeenId = lastSeenId;
    query.startDate = startDate;
    query.endDate = endDate;
    query.searchTerm = searchTerm;
    query.sortDirection = String.isBlank(sortDirection) ? 'newest' : sortDirection;
    query.fieldSet = NotificationLogRepository.FieldSet.LOG;

    if (
      !String.isBlank(sourceTypeFilter) &&
      sourceTypeFilter != NotificationConstants.LOG_CATEGORY_ALL &&
      sourceTypeFilter != 'ALL'
    ) {
      query.sourceType = sourceTypeFilter;
    }

    return query;
  }

  private static void sortLogItemsByChangeDateAscending(
    List<NotificationCenterModels.LogItem> items
  ) {
    items.sort(new LogItemChangeDateComparator());
  }

  private class LogItemChangeDateComparator implements Comparator<NotificationCenterModels.LogItem> {
    public Integer compare(
      NotificationCenterModels.LogItem first,
      NotificationCenterModels.LogItem second
    ) {
      Datetime firstChangeDate = first.changeDate;
      Datetime secondChangeDate = second.changeDate;

      if (firstChangeDate == null && secondChangeDate == null) {
        return compareIds(first, second);
      }

      if (firstChangeDate == null) {
        return 1;
      }

      if (secondChangeDate == null) {
        return -1;
      }

      if (firstChangeDate == secondChangeDate) {
        return compareIds(first, second);
      }

      return firstChangeDate < secondChangeDate ? -1 : 1;
    }

    private Integer compareIds(
      NotificationCenterModels.LogItem first,
      NotificationCenterModels.LogItem second
    ) {
      String firstId = first.id == null ? '' : String.valueOf(first.id);
      String secondId = second.id == null ? '' : String.valueOf(second.id);
      return firstId.compareTo(secondId);
    }
  }

  private static Set<String> resolveLogStatuses(String statusFilter) {
    if (String.isBlank(statusFilter) || statusFilter == NotificationConstants.LOG_STATUS_ALL) {
      return NotificationConstants.allLogViewStatuses();
    }

    if (statusFilter == NotificationConstants.LOG_STATUS_DELIVERED) {
      return new Set<String>{ NotificationConstants.STATUS_SENT };
    }

    if (statusFilter == NotificationConstants.LOG_STATUS_SUPPRESSED) {
      return new Set<String>{ NotificationConstants.STATUS_SUPPRESSED };
    }

    if (statusFilter == NotificationConstants.LOG_STATUS_QUEUED) {
      return new Set<String>{ NotificationConstants.STATUS_QUEUED };
    }

    if (statusFilter == NotificationConstants.LOG_STATUS_PENDING) {
      return new Set<String>{ NotificationConstants.STATUS_PENDING };
    }

    if (statusFilter == NotificationConstants.LOG_STATUS_FAILED) {
      return new Set<String>{ NotificationConstants.STATUS_FAILED };
    }

    return NotificationConstants.allLogViewStatuses();
  }

  private static String normalizeInboxFilter(String filterName) {
    if (String.isBlank(filterName) || filterName == 'ALL') {
      return 'ALL';
    }

    return filterName;
  }

  private static String normalizeLogCategoryFilter(String categoryFilter) {
    if (
      String.isBlank(categoryFilter) ||
      categoryFilter == NotificationConstants.LOG_CATEGORY_ALL
    ) {
      return NotificationConstants.LOG_CATEGORY_ALL;
    }

    return categoryFilter;
  }

  private static NotificationCenterModels.LogItem toLogItem(
    Notification_Log__c notification,
    Map<Id, String> changeContextByLogId
  ) {
    NotificationCenterModels.LogItem item = new NotificationCenterModels.LogItem();
    item.id = notification.Id;
    item.notificationNumber = !String.isBlank(notification.Name)
      ? notification.Name
      : notification.Legacy_Notification_Number__c;
    item.householdName = notification.Household__r == null
      ? null
      : notification.Household__r.Name;
    item.householdId = notification.Household__c;
    item.sourceType = notification.Source_Type__c;
    item.title = notification.Title__c;
    item.recipientName = notification.Recipient__r == null
      ? null
      : notification.Recipient__r.Name;
    item.recipientId = notification.Recipient__c;
    item.sourceRecordId = notification.Source_Record_Id__c;
    item.targetRecordId = notification.Target_Record_Id__c;
    item.frequency = notification.Frequency__c;
    item.channel = notification.Channel__c;
    item.status = notification.Status__c;
    item.suppressionReason = notification.Suppression_Reason__c;
    item.errorMessage = notification.Error_Message__c;
    item.priority = notification.Notification_Rule__r == null
      ? null
      : notification.Notification_Rule__r.Priority__c;
    item.category = resolveCategory(item.priority);
    item.eventAt = notification.Delivered_At__c != null
      ? notification.Delivered_At__c
      : notification.CreatedDate;
    item.changeContext = changeContextByLogId != null &&
      changeContextByLogId.containsKey(notification.Id)
      ? changeContextByLogId.get(notification.Id)
      : NotificationChangeModels.enrichChangeContextForDisplay(
          notification.Change_Context__c,
          notification,
          null
        );
    return item;
  }

  private static String resolveCategory(Decimal priority) {
    if (priority == null) {
      return 'Info';
    }

    if (priority >= NotificationConstants.CATEGORY_URGENT_MIN_PRIORITY) {
      return 'Urgent';
    }

    if (priority >= NotificationConstants.CATEGORY_SERVICE_MIN_PRIORITY) {
      return 'Service';
    }

    return 'Info';
  }

  private static List<NotificationCenterModels.DigestScheduleItem> buildUpcomingDigests(
    Id recipientId,
    NotificationCenterModels.DashboardStats stats
  ) {
    if (stats == null || stats.queuedCount == null || stats.queuedCount <= 0) {
      return new List<NotificationCenterModels.DigestScheduleItem>();
    }

    Datetime nextRun = NotificationDigestScheduleService.resolveNextDigestRun(recipientId);

    if (nextRun == null) {
      return new List<NotificationCenterModels.DigestScheduleItem>();
    }

    NotificationCenterModels.DigestScheduleItem nextDigest = new NotificationCenterModels.DigestScheduleItem();
    nextDigest.name = 'Next Digest Run';
    nextDigest.timeLabel = NotificationDigestScheduleService.formatTimeLabel(nextRun);
    nextDigest.queuedCount = stats.queuedCount;
    nextDigest.channelTags = new List<String>{
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.CHANNEL_EMAIL
    };

    return new List<NotificationCenterModels.DigestScheduleItem>{ nextDigest };
  }

  private static Notification_Rule__c buildSystemDefaultFromInput(
    NotificationCenterModels.RuleInput input
  ) {
    Notification_Rule__c rule = buildRuleFromInput(null, input);
    rule.User__c = null;
    rule.Household__c = null;
    rule.Is_System_Default__c = true;
    return rule;
  }

  private static Notification_Rule__c buildRuleFromInput(
    Id userId,
    NotificationCenterModels.RuleInput input
  ) {
    if (String.isBlank(input.objectType)) {
      throw new IllegalArgumentException('Object Type is required.');
    }

    if (String.isBlank(input.category)) {
      throw new IllegalArgumentException('Category is required.');
    }

    if (input.channels == null || input.channels.isEmpty()) {
      throw new IllegalArgumentException('At least one channel is required.');
    }

    Notification_Rule__c rule = new Notification_Rule__c();
    rule.Id = input.id;
    rule.Object_Type__c = input.objectType;
    rule.Frequency__c = String.isBlank(input.frequency)
      ? NotificationConstants.FREQUENCY_IMMEDIATE
      : input.frequency;
    rule.Digest_Cadence__c = resolveDigestCadence(input.frequency, input.digestFrequency);
    rule.Digest_Frequency_Hour__c = resolveDigestFrequencyHour(
      input.frequency,
      input.digestFrequency,
      input.digestFrequencyHour
    );
    rule.Channel__c = String.join(
      normalizeChannels(input.channels, rule.Frequency__c),
      ';'
    );
    rule.Is_Active__c = input.isActive != false;
    rule.User__c = userId;
    rule.Household__c = input.householdId;
    rule.Priority__c = resolvePriority(input.category);
    rule.Rule_Name__c = String.isBlank(input.ruleName) ? null : input.ruleName.trim();
    return rule;
  }

  private static String resolveDigestCadence(
    String frequency,
    String digestFrequency
  ) {
    if (frequency != NotificationConstants.FREQUENCY_DIGEST) {
      return null;
    }

    if (digestFrequency == NotificationConstants.DIGEST_FREQUENCY_WEEKLY) {
      return NotificationConstants.DIGEST_FREQUENCY_WEEKLY;
    }

    if (digestFrequency == NotificationConstants.DIGEST_FREQUENCY_HOURLY) {
      return NotificationConstants.DIGEST_FREQUENCY_HOURLY;
    }

    return NotificationConstants.DIGEST_FREQUENCY_DAILY;
  }

  private static String resolveDigestFrequencyHour(
    String frequency,
    String digestFrequency,
    String digestFrequencyHour
  ) {
    if (
      frequency != NotificationConstants.FREQUENCY_DIGEST ||
      digestFrequency != NotificationConstants.DIGEST_FREQUENCY_DAILY
    ) {
      return null;
    }

    if (String.isBlank(digestFrequencyHour)) {
      throw new IllegalArgumentException(
        'Delivery Hour is required when Digest Frequency is Daily.'
      );
    }

    return digestFrequencyHour;
  }

  private static List<String> normalizeChannels(
    List<String> channels,
    String frequency
  ) {
    if (frequency == NotificationConstants.FREQUENCY_DIGEST) {
      return new List<String>{ NotificationConstants.CHANNEL_EMAIL };
    }

    List<String> normalizedChannels = new List<String>();
    Set<String> activeChannels = NotificationChannelService.getActiveChannelApiNames();

    for (String channel : channels) {
      if (String.isBlank(channel) || !activeChannels.contains(channel)) {
        continue;
      }

      if (!normalizedChannels.contains(channel)) {
        normalizedChannels.add(channel);
      }
    }

    if (normalizedChannels.isEmpty()) {
      throw new IllegalArgumentException('At least one valid channel is required.');
    }

    return NotificationChannelUtils.sortChannels(normalizedChannels);
  }

  private static Decimal resolvePriority(String category) {
    if (category == 'Urgent') {
      return NotificationConstants.CATEGORY_URGENT_MIN_PRIORITY;
    }

    if (category == 'Service') {
      return NotificationConstants.CATEGORY_SERVICE_MIN_PRIORITY;
    }

    return 0;
  }

  private static NotificationCenterModels.RuleItem toRuleItem(
    Notification_Rule__c rule,
    Boolean markAsReadOnlyForUser
  ) {
    if (rule == null) {
      return null;
    }

    String category = resolveCategory(rule.Priority__c);
    Boolean isSystemDefault = rule.Is_System_Default__c == true;
    NotificationCenterModels.RuleItem item = new NotificationCenterModels.RuleItem();
    item.id = rule.Id;
    item.ruleNumber = rule.Name;
    item.ruleName = rule.Rule_Name__c;
    item.name = resolveRuleDisplayName(
      rule.Rule_Name__c,
      rule.Object_Type__c,
      rule.Frequency__c
    );
    item.category = category;
    item.objectType = rule.Object_Type__c;
    item.frequency = rule.Frequency__c;
    item.digestFrequency = rule.Digest_Cadence__c;
    item.digestFrequencyHour = rule.Digest_Frequency_Hour__c;
    item.channels = parseChannels(rule.Channel__c);
    item.isActive = rule.Is_Active__c == true;
    item.householdScoped = rule.Household__c != null;
    item.householdId = rule.Household__c;
    item.householdName = rule.Household__r == null ? null : rule.Household__r.Name;
    item.respectQuietHours = category != 'Urgent';
    item.priority = rule.Priority__c;
    item.isSystemDefault = isSystemDefault;
    item.isReadOnly = markAsReadOnlyForUser == true && isSystemDefault;
    return item;
  }

  private static String buildRuleName(String objectType, String frequency) {
    String safeObjectType = String.isBlank(objectType) ? 'Case' : objectType.trim();
    String safeFrequency = String.isBlank(frequency)
      ? NotificationConstants.FREQUENCY_IMMEDIATE
      : frequency.trim();
    return safeObjectType + ' ' + safeFrequency;
  }

  private static String resolveRuleDisplayName(
    String ruleName,
    String objectType,
    String frequency
  ) {
    if (!String.isBlank(ruleName)) {
      return ruleName.trim();
    }

    return buildRuleName(objectType, frequency);
  }

  private static List<String> parseChannels(String channelValue) {
    List<String> channels = new List<String>();

    if (String.isBlank(channelValue)) {
      return channels;
    }

    for (String channel : channelValue.split(';')) {
      if (!String.isBlank(channel)) {
        channels.add(channel.trim());
      }
    }

    return NotificationChannelUtils.sortChannels(channels);
  }

  private static NotificationCenterModels.InboxItem toInboxItem(
    Notification_Log__c notification
  ) {
    NotificationCenterModels.InboxItem item = new NotificationCenterModels.InboxItem();
    item.id = notification.Id;
    item.title = notification.Title__c;
    item.body = notification.Body__c;
    item.sourceType = notification.Source_Type__c;
    item.householdName = notification.Household__r == null
      ? null
      : notification.Household__r.Name;
    item.deliveredAt = notification.Delivered_At__c != null
      ? notification.Delivered_At__c
      : notification.CreatedDate;
    item.isRead = notification.Is_Read__c == true;
    item.targetRecordId = !String.isBlank(notification.Target_Record_Id__c)
      ? notification.Target_Record_Id__c
      : notification.Source_Record_Id__c;
    return item;
  }
}