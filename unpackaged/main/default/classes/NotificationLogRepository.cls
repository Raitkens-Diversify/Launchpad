/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-16
 *
 * Universal data access for Notification_Log__c. Composable query criteria power
 * inbox, log, dashboard, and future screens without duplicating SOQL filters.
 * Runs without sharing but always scopes reads and writes to supplied ids.
 */
public without sharing class NotificationLogRepository {
  private static final Integer DEFAULT_PAGE_SIZE = 50;
  private static final Integer MAX_PAGE_SIZE = 100;

  private static final String INBOX_FIELDS =
    'Id, Title__c, Body__c, Source_Type__c, Household__r.Name, ' +
    'Delivered_At__c, CreatedDate, Is_Read__c, Target_Record_Id__c, Source_Record_Id__c';

  private static final String LOG_FIELDS =
    'Id, Name, Title__c, Source_Type__c, Household__c, Household__r.Name, Recipient__c, Recipient__r.Name, ' +
    'Source_Record_Id__c, Target_Record_Id__c, Frequency__c, Channel__c, Status__c, Suppression_Reason__c, ' +
    'Delivered_At__c, CreatedDate, Notification_Rule__r.Priority__c, Legacy_Notification_Number__c, Error_Message__c, ' +
    'Change_Context__c, Correlation_Key__c';

  private static final String DELIVERY_LOG_FIELDS =
    'Id, Name, Recipient__c, Channel__c, Source_Type__c, Source_Record_Id__c, ' +
    'Target_Record_Id__c, Household__c, Title__c, Body__c, Change_Context__c, CreatedDate, Status__c, ' +
    'Frequency__c, Delivery_Attempt_Count__c, Error_Message__c, Suppression_Reason__c, Notification_Rule__c';

  public enum FieldSet {
    INBOX,
    LOG
  }

  public class NotificationLogQuery {
    public Id recipientId;
    public Id householdId;
    public Set<String> channels;
    public Set<String> statuses;
    public String sourceType;
    public Boolean unreadOnly;
    public String searchTerm;
    public String categoryFilter;
    public Integer pageSize;
    public Id lastSeenId;
    public Date startDate;
    public Date endDate;
    public String sortDirection = 'newest';
    public FieldSet fieldSet;
  }

  public List<Notification_Log__c> selectLogs(NotificationLogQuery query) {
    validateQuery(query);

    String sortDirection = query.sortDirection == 'oldest' ? 'ASC' : 'DESC';
    Integer safePageSize = resolvePageSize(query.pageSize);
    String fieldList = query.fieldSet == FieldSet.INBOX ? INBOX_FIELDS : LOG_FIELDS;

    Id recipientId = query.recipientId;
    Id householdId = query.householdId;
    Set<String> statuses = resolveStatuses(query.statuses);
    Set<String> channels = query.channels;
    String sourceType = query.sourceType;
    String searchPattern = '%' +
      String.escapeSingleQuotes(query.searchTerm == null ? '' : query.searchTerm.trim()) +
      '%';
    Decimal urgentMinPriority = NotificationConstants.CATEGORY_URGENT_MIN_PRIORITY;
    Decimal serviceMinPriority = NotificationConstants.CATEGORY_SERVICE_MIN_PRIORITY;
    Id lastSeenId = query.lastSeenId;
    Datetime cursorDeliveredAt;
    Datetime cursorCreatedDate;
    Datetime dateRangeStart = resolveDateRangeStart(query.startDate);
    Datetime dateRangeEndExclusive = resolveDateRangeEndExclusive(query.endDate);

    String soql = 'SELECT ' + fieldList + ' FROM Notification_Log__c WHERE ';
    soql += buildSharedFilterClause(
      query,
      statuses,
      channels,
      sourceType,
      searchPattern,
      urgentMinPriority,
      serviceMinPriority
    );

    if (query.lastSeenId != null) {
      Notification_Log__c cursor = [
        SELECT Delivered_At__c, CreatedDate
        FROM Notification_Log__c
        WHERE Id = :query.lastSeenId AND Recipient__c = :recipientId
        LIMIT 1
      ];

      cursorDeliveredAt = cursor.Delivered_At__c;
      cursorCreatedDate = cursor.CreatedDate;
      soql += buildPaginationClause(
        sortDirection,
        cursorDeliveredAt,
        cursorCreatedDate,
        lastSeenId
      );
    }

    soql += buildOrderByClause(sortDirection) + ' LIMIT :safePageSize';

    return Database.query(soql);
  }

  private static String buildOrderByClause(String sortDirection) {
    return ' ORDER BY Delivered_At__c ' +
      sortDirection +
      ' NULLS LAST, CreatedDate ' +
      sortDirection +
      ', Id ' +
      sortDirection;
  }

  private static String buildPaginationClause(
    String sortDirection,
    Datetime cursorDeliveredAt,
    Datetime cursorCreatedDate,
    Id lastSeenId
  ) {
    if (sortDirection == 'DESC') {
      if (cursorDeliveredAt != null) {
        return ' AND (' +
          'Delivered_At__c < :cursorDeliveredAt' +
          ' OR (Delivered_At__c = :cursorDeliveredAt AND CreatedDate < :cursorCreatedDate)' +
          ' OR (Delivered_At__c = :cursorDeliveredAt AND CreatedDate = :cursorCreatedDate AND Id < :lastSeenId)' +
          ' OR Delivered_At__c = NULL' +
          ')';
      }

      return ' AND Delivered_At__c = NULL AND (CreatedDate < :cursorCreatedDate' +
        ' OR (CreatedDate = :cursorCreatedDate AND Id < :lastSeenId))';
    }

    if (cursorDeliveredAt != null) {
      return ' AND (' +
        'Delivered_At__c > :cursorDeliveredAt' +
        ' OR (Delivered_At__c = :cursorDeliveredAt AND CreatedDate > :cursorCreatedDate)' +
        ' OR (Delivered_At__c = :cursorDeliveredAt AND CreatedDate = :cursorCreatedDate AND Id > :lastSeenId)' +
        ' OR Delivered_At__c = NULL' +
        ')';
    }

    return ' AND Delivered_At__c = NULL AND (CreatedDate > :cursorCreatedDate' +
      ' OR (CreatedDate = :cursorCreatedDate AND Id > :lastSeenId))';
  }

  public Integer countLogs(NotificationLogQuery query) {
    validateQuery(query);

    Id recipientId = query.recipientId;
    Id householdId = query.householdId;
    Set<String> statuses = resolveStatuses(query.statuses);
    Set<String> channels = query.channels;
    String sourceType = query.sourceType;
    String searchPattern = '%' +
      String.escapeSingleQuotes(query.searchTerm == null ? '' : query.searchTerm.trim()) +
      '%';
    Decimal urgentMinPriority = NotificationConstants.CATEGORY_URGENT_MIN_PRIORITY;
    Decimal serviceMinPriority = NotificationConstants.CATEGORY_SERVICE_MIN_PRIORITY;
    Datetime dateRangeStart = resolveDateRangeStart(query.startDate);
    Datetime dateRangeEndExclusive = resolveDateRangeEndExclusive(query.endDate);

    String soql = 'SELECT COUNT() FROM Notification_Log__c WHERE ';
    soql += buildSharedFilterClause(
      query,
      statuses,
      channels,
      sourceType,
      searchPattern,
      urgentMinPriority,
      serviceMinPriority
    );

    return Database.countQuery(soql);
  }

  public Integer countUnread(Id recipientId) {
    return [
      SELECT COUNT()
      FROM Notification_Log__c
      WHERE
        Recipient__c = :recipientId
        AND Channel__c = :NotificationConstants.CHANNEL_IN_APP
        AND Status__c = :NotificationConstants.STATUS_SENT
        AND Is_Read__c = FALSE
    ];
  }

  public NotificationCenterModels.InboxStats selectInboxStats(Id recipientId) {
    Datetime weekStart = Datetime.now().addDays(-7);

    AggregateResult totals = [
      SELECT COUNT(Id) totalCount
      FROM Notification_Log__c
      WHERE
        Recipient__c = :recipientId
        AND Channel__c = :NotificationConstants.CHANNEL_IN_APP
        AND Status__c = :NotificationConstants.STATUS_SENT
    ];

    AggregateResult unreadTotals = [
      SELECT COUNT(Id) unreadCount
      FROM Notification_Log__c
      WHERE
        Recipient__c = :recipientId
        AND Channel__c = :NotificationConstants.CHANNEL_IN_APP
        AND Status__c = :NotificationConstants.STATUS_SENT
        AND Is_Read__c = FALSE
    ];

    AggregateResult weekTotals = [
      SELECT COUNT(Id) weekCount
      FROM Notification_Log__c
      WHERE
        Recipient__c = :recipientId
        AND Channel__c = :NotificationConstants.CHANNEL_IN_APP
        AND Status__c = :NotificationConstants.STATUS_SENT
        AND Delivered_At__c >= :weekStart
    ];

    return new NotificationCenterModels.InboxStats(
      (Integer) totals.get('totalCount'),
      (Integer) unreadTotals.get('unreadCount'),
      (Integer) weekTotals.get('weekCount')
    );
  }

  public NotificationCenterModels.DashboardStats selectDashboardStats(Id recipientId) {
    Datetime todayStart = Datetime.newInstance(Date.today(), Time.newInstance(0, 0, 0, 0));
    String sentStatus = NotificationConstants.STATUS_SENT;
    String suppressedStatus = NotificationConstants.STATUS_SUPPRESSED;
    String queuedStatus = NotificationConstants.STATUS_QUEUED;

    AggregateResult deliveredToday = [
      SELECT COUNT(Id) deliveredCount
      FROM Notification_Log__c
      WHERE
        Recipient__c = :recipientId
        AND Status__c = :sentStatus
        AND Delivered_At__c >= :todayStart
    ];

    AggregateResult suppressedToday = [
      SELECT COUNT(Id) suppressedCount
      FROM Notification_Log__c
      WHERE
        Recipient__c = :recipientId
        AND Status__c = :suppressedStatus
        AND CreatedDate >= :todayStart
    ];

    AggregateResult queuedTotals = [
      SELECT COUNT(Id) queuedCount
      FROM Notification_Log__c
      WHERE Recipient__c = :recipientId AND Status__c = :queuedStatus
    ];

    AggregateResult householdTotals = [
      SELECT COUNT_DISTINCT(Household__c) activeHouseholdCount
      FROM Notification_Log__c
      WHERE Recipient__c = :recipientId AND Household__c != NULL
    ];

    return new NotificationCenterModels.DashboardStats(
      (Integer) deliveredToday.get('deliveredCount'),
      (Integer) suppressedToday.get('suppressedCount'),
      (Integer) queuedTotals.get('queuedCount'),
      (Integer) householdTotals.get('activeHouseholdCount')
    );
  }

  public List<NotificationCenterModels.ChannelDeliveryStat> selectTodayChannelDelivery(
    Id recipientId
  ) {
    Datetime todayStart = Datetime.newInstance(Date.today(), Time.newInstance(0, 0, 0, 0));
    String sentStatus = NotificationConstants.STATUS_SENT;

    Integer inAppCount = [
      SELECT COUNT()
      FROM Notification_Log__c
      WHERE
        Recipient__c = :recipientId
        AND Status__c = :sentStatus
        AND Delivered_At__c >= :todayStart
        AND Channel__c = :NotificationConstants.CHANNEL_IN_APP
    ];

    Integer emailCount = [
      SELECT COUNT()
      FROM Notification_Log__c
      WHERE
        Recipient__c = :recipientId
        AND Status__c = :sentStatus
        AND Delivered_At__c >= :todayStart
        AND Channel__c = :NotificationConstants.CHANNEL_EMAIL
    ];

    Integer totalDelivered = inAppCount + emailCount;

    return new List<NotificationCenterModels.ChannelDeliveryStat>{
      buildChannelDeliveryStat('In_App', 'In-App', inAppCount, totalDelivered),
      buildChannelDeliveryStat('Email', 'Email', emailCount, totalDelivered)
    };
  }

  public Integer markAsRead(Id recipientId, List<Id> notificationIds) {
    if (notificationIds == null || notificationIds.isEmpty()) {
      return 0;
    }

    List<Notification_Log__c> notifications = [
      SELECT Id, Is_Read__c
      FROM Notification_Log__c
      WHERE
        Id IN :notificationIds
        AND Recipient__c = :recipientId
        AND Channel__c = :NotificationConstants.CHANNEL_IN_APP
        AND Status__c = :NotificationConstants.STATUS_SENT
        AND Is_Read__c = FALSE
    ];

    Datetime readAt = System.now();
    for (Notification_Log__c notification : notifications) {
      notification.Is_Read__c = true;
      notification.Read_At__c = readAt;
    }

    update as system notifications;
    return notifications.size();
  }

  public Integer markAllAsRead(Id recipientId) {
    List<Notification_Log__c> notifications = [
      SELECT Id, Is_Read__c
      FROM Notification_Log__c
      WHERE
        Recipient__c = :recipientId
        AND Channel__c = :NotificationConstants.CHANNEL_IN_APP
        AND Status__c = :NotificationConstants.STATUS_SENT
        AND Is_Read__c = FALSE
    ];

    Datetime readAt = System.now();
    for (Notification_Log__c notification : notifications) {
      notification.Is_Read__c = true;
      notification.Read_At__c = readAt;
    }

    update as system notifications;
    return notifications.size();
  }

  public List<Notification_Log__c> selectLogsByIds(List<Id> logIds) {
    if (logIds == null || logIds.isEmpty()) {
      return new List<Notification_Log__c>();
    }

    return (List<Notification_Log__c>) Database.query(
      'SELECT ' +
      DELIVERY_LOG_FIELDS +
      ' FROM Notification_Log__c WHERE Id IN :logIds'
    );
  }

  public List<Notification_Log__c> promoteAndSelectPendingImmediateLogsByIds(
    List<Id> logIds
  ) {
    if (logIds == null || logIds.isEmpty()) {
      return new List<Notification_Log__c>();
    }

    List<Notification_Log__c> immediateLogs = [
      SELECT
        Id,
        Name,
        Recipient__c,
        Channel__c,
        Source_Type__c,
        Source_Record_Id__c,
        Target_Record_Id__c,
        Household__c,
        Title__c,
        Body__c,
        Change_Context__c,
        Status__c,
        Frequency__c,
        Delivery_Attempt_Count__c,
        Error_Message__c,
        Suppression_Reason__c,
        Notification_Rule__c
      FROM Notification_Log__c
      WHERE
        Id IN :logIds
        AND Frequency__c = :NotificationConstants.FREQUENCY_IMMEDIATE
        AND Status__c IN (
          :NotificationConstants.STATUS_QUEUED,
          :NotificationConstants.STATUS_PENDING
        )
    ];

    List<Notification_Log__c> deliverableLogs = new List<Notification_Log__c>();
    List<Notification_Log__c> logsToPromote = new List<Notification_Log__c>();

    for (Notification_Log__c logRecord : immediateLogs) {
      if (logRecord.Status__c == NotificationConstants.STATUS_PENDING) {
        deliverableLogs.add(logRecord);
        continue;
      }

      logRecord.Status__c = NotificationConstants.STATUS_PENDING;
      logsToPromote.add(logRecord);
    }

    if (!logsToPromote.isEmpty()) {
      update logsToPromote;
      deliverableLogs.addAll(logsToPromote);
    }

    return deliverableLogs;
  }

  public List<Notification_Log__c> selectQueuedDigestLogsByIds(List<Id> logIds) {
    if (logIds == null || logIds.isEmpty()) {
      return new List<Notification_Log__c>();
    }

    return [
      SELECT
        Id,
        Name,
        Recipient__c,
        Channel__c,
        Source_Type__c,
        Source_Record_Id__c,
        Target_Record_Id__c,
        Household__c,
        Title__c,
        Body__c,
        Change_Context__c,
        Status__c,
        Frequency__c,
        Delivery_Attempt_Count__c,
        Error_Message__c,
        Suppression_Reason__c,
        Notification_Rule__c
      FROM Notification_Log__c
      WHERE
        Id IN :logIds
        AND Status__c = :NotificationConstants.STATUS_QUEUED
        AND Frequency__c = :NotificationConstants.FREQUENCY_DIGEST
    ];
  }

  public List<Notification_Log__c> selectQueuedLogsForRules(Set<Id> ruleIds) {
    if (ruleIds == null || ruleIds.isEmpty()) {
      return new List<Notification_Log__c>();
    }

    return [
      SELECT
        Id,
        Name,
        Recipient__c,
        Channel__c,
        Source_Type__c,
        Notification_Rule__c,
        Title__c,
        Body__c,
        Change_Context__c,
        CreatedDate,
        Source_Record_Id__c,
        Target_Record_Id__c,
        Household__c,
        Status__c,
        Frequency__c,
        Delivery_Attempt_Count__c,
        Error_Message__c,
        Suppression_Reason__c
      FROM Notification_Log__c
      WHERE
        Status__c = :NotificationConstants.STATUS_QUEUED
        AND Frequency__c = :NotificationConstants.FREQUENCY_DIGEST
        AND Notification_Rule__c IN :ruleIds
    ];
  }

  public List<Notification_Log__c> selectQueuedLogsForDeliveryGroup(
    Notification_Log__c seedLog
  ) {
    return selectQueuedLogsForDeliveryGroup(seedLog, null);
  }

  public List<Notification_Log__c> selectQueuedLogsForDeliveryGroup(
    Notification_Log__c seedLog,
    String digestCadence
  ) {
    if (seedLog == null || seedLog.Recipient__c == null) {
      return new List<Notification_Log__c>();
    }

    String channel = NotificationChannelUtils.resolveSingleChannel(
      seedLog.Channel__c,
      null
    );

    if (String.isBlank(digestCadence)) {
      return [
        SELECT
          Id,
          Name,
          Recipient__c,
          Channel__c,
          Source_Type__c,
          Notification_Rule__c,
          Title__c,
          Body__c,
          Change_Context__c,
          CreatedDate,
          Source_Record_Id__c,
          Target_Record_Id__c,
          Household__c,
          Status__c,
          Frequency__c,
          Delivery_Attempt_Count__c,
          Error_Message__c,
          Suppression_Reason__c
        FROM Notification_Log__c
        WHERE
          Status__c = :NotificationConstants.STATUS_QUEUED
          AND Frequency__c = :NotificationConstants.FREQUENCY_DIGEST
          AND Recipient__c = :seedLog.Recipient__c
          AND Source_Type__c = :seedLog.Source_Type__c
          AND Channel__c INCLUDES (:channel)
      ];
    }

    return [
      SELECT
        Id,
        Name,
        Recipient__c,
        Channel__c,
        Source_Type__c,
        Notification_Rule__c,
        Title__c,
        Body__c,
        Change_Context__c,
        CreatedDate,
        Source_Record_Id__c,
        Target_Record_Id__c,
        Household__c,
        Status__c,
        Frequency__c,
        Delivery_Attempt_Count__c,
        Error_Message__c,
        Suppression_Reason__c
      FROM Notification_Log__c
      WHERE
        Status__c = :NotificationConstants.STATUS_QUEUED
        AND Frequency__c = :NotificationConstants.FREQUENCY_DIGEST
        AND Recipient__c = :seedLog.Recipient__c
        AND Source_Type__c = :seedLog.Source_Type__c
        AND Channel__c INCLUDES (:channel)
        AND Notification_Rule__r.Digest_Cadence__c = :digestCadence
    ];
  }

  public List<Notification_Log__c> selectLogsForRetry(List<Id> logIds) {
    if (logIds == null || logIds.isEmpty()) {
      return new List<Notification_Log__c>();
    }

    return [
      SELECT Id, Delivery_Attempt_Count__c, Frequency__c
      FROM Notification_Log__c
      WHERE Id IN :logIds
    ];
  }

  private static void validateQuery(NotificationLogQuery query) {
    if (query == null || query.recipientId == null) {
      throw new IllegalArgumentException('Recipient Id is required.');
    }
  }

  private static Integer resolvePageSize(Integer pageSize) {
    if (pageSize == null || pageSize < 1) {
      return DEFAULT_PAGE_SIZE;
    }

    return Math.min(pageSize, MAX_PAGE_SIZE);
  }

  private static Set<String> resolveStatuses(Set<String> statuses) {
    if (statuses == null || statuses.isEmpty()) {
      return NotificationConstants.allLogViewStatuses();
    }

    return statuses;
  }

  private static String buildSharedFilterClause(
    NotificationLogQuery query,
    Set<String> statuses,
    Set<String> channels,
    String sourceType,
    String searchPattern,
    Decimal urgentMinPriority,
    Decimal serviceMinPriority
  ) {
    String clause = 'Recipient__c = :recipientId';

    if (query.householdId != null) {
      clause += ' AND Household__c = :householdId';
    }

    clause += ' AND Status__c IN :statuses';

    if (channels != null && !channels.isEmpty()) {
      clause += ' AND Channel__c IN :channels';
    }

    if (!String.isBlank(sourceType)) {
      clause += ' AND Source_Type__c = :sourceType';
    }

    if (query.unreadOnly == true) {
      clause += ' AND Is_Read__c = false';
    }

    if (
      !String.isBlank(query.categoryFilter) &&
      query.categoryFilter != NotificationConstants.LOG_CATEGORY_ALL
    ) {
      if (query.categoryFilter == NotificationConstants.LOG_CATEGORY_URGENT) {
        clause += ' AND Notification_Rule__r.Priority__c >= :urgentMinPriority';
      } else if (query.categoryFilter == NotificationConstants.LOG_CATEGORY_SERVICE) {
        clause +=
          ' AND Notification_Rule__r.Priority__c >= :serviceMinPriority' +
          ' AND Notification_Rule__r.Priority__c < :urgentMinPriority';
      } else if (query.categoryFilter == NotificationConstants.LOG_CATEGORY_INFO) {
        clause +=
          ' AND (Notification_Rule__r.Priority__c = NULL' +
          ' OR Notification_Rule__r.Priority__c < :serviceMinPriority)';
      }
    }

    if (!String.isBlank(query.searchTerm)) {
      clause +=
        ' AND (Title__c LIKE :searchPattern OR Body__c LIKE :searchPattern OR Household__r.Name LIKE :searchPattern)';
    }

    clause += buildDateRangeClause(query);

    return clause;
  }

  private static String buildDateRangeClause(NotificationLogQuery query) {
    if (query.startDate == null && query.endDate == null) {
      return '';
    }

    if (query.startDate != null && query.endDate != null) {
      return ' AND ((Delivered_At__c != NULL AND Delivered_At__c >= :dateRangeStart AND Delivered_At__c < :dateRangeEndExclusive)' +
        ' OR (Delivered_At__c = NULL AND CreatedDate >= :dateRangeStart AND CreatedDate < :dateRangeEndExclusive))';
    }

    if (query.startDate != null) {
      return ' AND ((Delivered_At__c != NULL AND Delivered_At__c >= :dateRangeStart)' +
        ' OR (Delivered_At__c = NULL AND CreatedDate >= :dateRangeStart))';
    }

    return ' AND ((Delivered_At__c != NULL AND Delivered_At__c < :dateRangeEndExclusive)' +
      ' OR (Delivered_At__c = NULL AND CreatedDate < :dateRangeEndExclusive))';
  }

  private static Datetime resolveDateRangeStart(Date startDate) {
    if (startDate == null) {
      return null;
    }

    return Datetime.newInstance(startDate, Time.newInstance(0, 0, 0, 0));
  }

  private static Datetime resolveDateRangeEndExclusive(Date endDate) {
    if (endDate == null) {
      return null;
    }

    return Datetime.newInstance(endDate.addDays(1), Time.newInstance(0, 0, 0, 0));
  }

  private static NotificationCenterModels.ChannelDeliveryStat buildChannelDeliveryStat(
    String channelKey,
    String label,
    Integer count,
    Integer totalDelivered
  ) {
    Integer safeCount = count == null ? 0 : count;
    Integer safeTotal = totalDelivered == null || totalDelivered < 1 ? 0 : totalDelivered;
    Integer percent = safeTotal == 0
      ? 0
      : Math.round((Decimal.valueOf(safeCount) / Decimal.valueOf(safeTotal)) * 100);

    return new NotificationCenterModels.ChannelDeliveryStat(
      channelKey,
      label,
      safeCount,
      percent
    );
  }
}