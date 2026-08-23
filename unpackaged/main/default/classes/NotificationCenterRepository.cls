/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-16
 *
 * Data access for the notification center inbox. Runs without sharing but always
 * scopes queries and updates to the supplied recipient id.
 */
public without sharing class NotificationCenterRepository {
  public class InboxQuery {
    public Id recipientId;
    public String filterName;
    public String searchTerm;
    public Integer pageSize;
    public Id lastSeenId;
    public String sortDirection;
  }

  public class LogQuery {
    public Id recipientId;
    public String statusFilter;
    public String categoryFilter;
    public Integer pageSize;
    public Id lastSeenId;
  }

  public List<Notification_Log__c> selectInbox(InboxQuery query) {
    Integer safePageSize = query.pageSize == null || query.pageSize < 1
      ? 25
      : Math.min(query.pageSize, 100);

    String sortDirection = query.sortDirection == 'oldest' ? 'ASC' : 'DESC';
    String soql =
      'SELECT Id, Title__c, Body__c, Source_Type__c, Household__r.Name, ' +
      'Delivered_At__c, CreatedDate, Is_Read__c, Target_Record_Id__c, Source_Record_Id__c ' +
      'FROM Notification_Log__c ' +
      'WHERE Recipient__c = :recipientId ' +
      'AND Channel__c = :inAppChannel ' +
      'AND Status__c = :sentStatus';

    Id recipientId = query.recipientId;
    String inAppChannel = NotificationConstants.CHANNEL_IN_APP;
    String sentStatus = NotificationConstants.STATUS_SENT;
    String caseType = NotificationConstants.OBJECT_TYPE_CASE;
    String taskType = NotificationConstants.OBJECT_TYPE_TASK;
    String eventType = NotificationConstants.OBJECT_TYPE_EVENT;

    if (query.filterName == 'UNREAD') {
      soql += ' AND Is_Read__c = false';
    } else if (query.filterName == NotificationConstants.OBJECT_TYPE_CASE) {
      soql += ' AND Source_Type__c = :caseType';
    } else if (query.filterName == NotificationConstants.OBJECT_TYPE_TASK) {
      soql += ' AND Source_Type__c = :taskType';
    } else if (query.filterName == NotificationConstants.OBJECT_TYPE_EVENT) {
      soql += ' AND Source_Type__c = :eventType';
    }

    String searchPattern = '%' +
      String.escapeSingleQuotes(query.searchTerm == null ? '' : query.searchTerm.trim()) +
      '%';

    if (!String.isBlank(query.searchTerm)) {
      soql +=
        ' AND (Title__c LIKE :searchPattern OR Body__c LIKE :searchPattern OR Household__r.Name LIKE :searchPattern)';
    }

    Id lastSeenId = query.lastSeenId;
    Datetime cursorCreatedDate;

    if (query.lastSeenId != null) {
      Notification_Log__c cursor = [
        SELECT CreatedDate
        FROM Notification_Log__c
        WHERE Id = :query.lastSeenId AND Recipient__c = :recipientId
        LIMIT 1
      ];

      cursorCreatedDate = cursor.CreatedDate;

      if (sortDirection == 'DESC') {
        soql +=
          ' AND (CreatedDate < :cursorCreatedDate OR (CreatedDate = :cursorCreatedDate AND Id < :lastSeenId))';
      } else {
        soql +=
          ' AND (CreatedDate > :cursorCreatedDate OR (CreatedDate = :cursorCreatedDate AND Id > :lastSeenId))';
      }
    }

    soql +=
      ' ORDER BY CreatedDate ' +
      sortDirection +
      ', Id ' +
      sortDirection +
      ' LIMIT :safePageSize';

    return Database.query(soql);
  }

  public List<Notification_Log__c> selectLog(LogQuery query) {
    Integer safePageSize = query.pageSize == null || query.pageSize < 1
      ? 50
      : Math.min(query.pageSize, 100);

    String soql =
      'SELECT Id, Name, Title__c, Source_Type__c, Household__c, Household__r.Name, Recipient__c, Recipient__r.Name, ' +
      'Source_Record_Id__c, Target_Record_Id__c, Frequency__c, Channel__c, Status__c, Suppression_Reason__c, Delivered_At__c, CreatedDate, ' +
      'Notification_Rule__r.Priority__c, Legacy_Notification_Number__c ' +
      'FROM Notification_Log__c ' +
      'WHERE Recipient__c = :recipientId ' +
      'AND Status__c IN :logStatuses';

    Id recipientId = query.recipientId;
    Set<String> logStatuses = new Set<String>{
      NotificationConstants.STATUS_SENT,
      NotificationConstants.STATUS_SUPPRESSED,
      NotificationConstants.STATUS_QUEUED
    };

    if (query.statusFilter == NotificationConstants.LOG_STATUS_DELIVERED) {
      logStatuses = new Set<String>{ NotificationConstants.STATUS_SENT };
    } else if (query.statusFilter == NotificationConstants.LOG_STATUS_SUPPRESSED) {
      logStatuses = new Set<String>{ NotificationConstants.STATUS_SUPPRESSED };
    } else if (query.statusFilter == NotificationConstants.LOG_STATUS_QUEUED) {
      logStatuses = new Set<String>{ NotificationConstants.STATUS_QUEUED };
    }

    if (query.categoryFilter == NotificationConstants.LOG_CATEGORY_URGENT) {
      soql +=
        ' AND Notification_Rule__r.Priority__c >= :urgentMinPriority';
    } else if (query.categoryFilter == NotificationConstants.LOG_CATEGORY_SERVICE) {
      soql +=
        ' AND Notification_Rule__r.Priority__c >= :serviceMinPriority' +
        ' AND Notification_Rule__r.Priority__c < :urgentMinPriority';
    } else if (query.categoryFilter == NotificationConstants.LOG_CATEGORY_INFO) {
      soql +=
        ' AND (Notification_Rule__r.Priority__c = NULL' +
        ' OR Notification_Rule__r.Priority__c < :serviceMinPriority)';
    }

    Decimal urgentMinPriority = NotificationConstants.CATEGORY_URGENT_MIN_PRIORITY;
    Decimal serviceMinPriority = NotificationConstants.CATEGORY_SERVICE_MIN_PRIORITY;

    Id lastSeenId = query.lastSeenId;
    Datetime cursorCreatedDate;

    if (query.lastSeenId != null) {
      Notification_Log__c cursor = [
        SELECT CreatedDate
        FROM Notification_Log__c
        WHERE Id = :query.lastSeenId AND Recipient__c = :recipientId
        LIMIT 1
      ];

      cursorCreatedDate = cursor.CreatedDate;
      soql +=
        ' AND (CreatedDate < :cursorCreatedDate OR (CreatedDate = :cursorCreatedDate AND Id < :lastSeenId))';
    }

    soql += ' ORDER BY CreatedDate DESC, Id DESC LIMIT :safePageSize';

    return Database.query(soql);
  }

  public Integer countLog(LogQuery query) {
    String soql =
      'SELECT COUNT() ' +
      'FROM Notification_Log__c ' +
      'WHERE Recipient__c = :recipientId ' +
      'AND Status__c IN :logStatuses';

    Id recipientId = query.recipientId;
    Set<String> logStatuses = new Set<String>{
      NotificationConstants.STATUS_SENT,
      NotificationConstants.STATUS_SUPPRESSED,
      NotificationConstants.STATUS_QUEUED
    };

    if (query.statusFilter == NotificationConstants.LOG_STATUS_DELIVERED) {
      logStatuses = new Set<String>{ NotificationConstants.STATUS_SENT };
    } else if (query.statusFilter == NotificationConstants.LOG_STATUS_SUPPRESSED) {
      logStatuses = new Set<String>{ NotificationConstants.STATUS_SUPPRESSED };
    } else if (query.statusFilter == NotificationConstants.LOG_STATUS_QUEUED) {
      logStatuses = new Set<String>{ NotificationConstants.STATUS_QUEUED };
    }

    Decimal urgentMinPriority = NotificationConstants.CATEGORY_URGENT_MIN_PRIORITY;
    Decimal serviceMinPriority = NotificationConstants.CATEGORY_SERVICE_MIN_PRIORITY;

    if (query.categoryFilter == NotificationConstants.LOG_CATEGORY_URGENT) {
      soql +=
        ' AND Notification_Rule__r.Priority__c >= :urgentMinPriority';
    } else if (query.categoryFilter == NotificationConstants.LOG_CATEGORY_SERVICE) {
      soql +=
        ' AND Notification_Rule__r.Priority__c >= :serviceMinPriority' +
        ' AND Notification_Rule__r.Priority__c < :urgentMinPriority';
    } else if (query.categoryFilter == NotificationConstants.LOG_CATEGORY_INFO) {
      soql +=
        ' AND (Notification_Rule__r.Priority__c = NULL' +
        ' OR Notification_Rule__r.Priority__c < :serviceMinPriority)';
    }

    return Database.countQuery(soql);
  }

  public LogStats selectLogStats(Id recipientId) {
    AggregateResult deliveredTotals = [
      SELECT COUNT(Id) deliveredCount
      FROM Notification_Log__c
      WHERE
        Recipient__c = :recipientId
        AND Status__c = :NotificationConstants.STATUS_SENT
    ];

    AggregateResult suppressedTotals = [
      SELECT COUNT(Id) suppressedCount
      FROM Notification_Log__c
      WHERE
        Recipient__c = :recipientId
        AND Status__c = :NotificationConstants.STATUS_SUPPRESSED
    ];

    AggregateResult queuedTotals = [
      SELECT COUNT(Id) queuedCount
      FROM Notification_Log__c
      WHERE
        Recipient__c = :recipientId
        AND Status__c = :NotificationConstants.STATUS_QUEUED
    ];

    return new LogStats(
      (Integer) deliveredTotals.get('deliveredCount'),
      (Integer) suppressedTotals.get('suppressedCount'),
      (Integer) queuedTotals.get('queuedCount')
    );
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

  public InboxStats selectStats(Id recipientId) {
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

    return new InboxStats(
      (Integer) totals.get('totalCount'),
      (Integer) unreadTotals.get('unreadCount'),
      (Integer) weekTotals.get('weekCount')
    );
  }

  public List<Notification_Rule__c> selectUserDefaultPreferences(Id userId) {
    return [
      SELECT Id, Object_Type__c, Channel__c, Frequency__c, Is_Active__c, Priority__c
      FROM Notification_Rule__c
      WHERE User__c = :userId AND Household__c = NULL AND Is_Active__c = TRUE
      ORDER BY Object_Type__c
    ];
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

  public DashboardStats selectDashboardStats(Id recipientId) {
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

    return new DashboardStats(
      (Integer) deliveredToday.get('deliveredCount'),
      (Integer) suppressedToday.get('suppressedCount'),
      (Integer) queuedTotals.get('queuedCount'),
      (Integer) householdTotals.get('activeHouseholdCount')
    );
  }

  public List<ChannelDeliveryStat> selectTodayChannelDelivery(Id recipientId) {
    Datetime todayStart = Datetime.newInstance(Date.today(), Time.newInstance(0, 0, 0, 0));
    String sentStatus = NotificationConstants.STATUS_SENT;
    String inAppChannel = NotificationConstants.CHANNEL_IN_APP;
    String emailChannel = 'Email';
    // String zoomChannel = 'Zoom'; — temporarily disabled

    Integer inAppCount = [
      SELECT COUNT()
      FROM Notification_Log__c
      WHERE
        Recipient__c = :recipientId
        AND Status__c = :sentStatus
        AND Delivered_At__c >= :todayStart
        AND Channel__c = :inAppChannel
    ];

    Integer emailCount = [
      SELECT COUNT()
      FROM Notification_Log__c
      WHERE
        Recipient__c = :recipientId
        AND Status__c = :sentStatus
        AND Delivered_At__c >= :todayStart
        AND Channel__c = :emailChannel
    ];

    // Zoom channel temporarily disabled
    // Integer zoomCount = [
    //   SELECT COUNT()
    //   FROM Notification_Log__c
    //   WHERE
    //     Recipient__c = :recipientId
    //     AND Status__c = :sentStatus
    //     AND Delivered_At__c >= :todayStart
    //     AND Channel__c = :zoomChannel
    // ];

    Integer totalDelivered = inAppCount + emailCount; // + zoomCount

    return new List<ChannelDeliveryStat>{
      buildChannelDeliveryStat(
        'In_App',
        'In-App',
        inAppCount,
        totalDelivered
      ),
      buildChannelDeliveryStat('Email', 'Email', emailCount, totalDelivered)
      // buildChannelDeliveryStat('Zoom', 'Zoom', zoomCount, totalDelivered)
    };
  }

  private ChannelDeliveryStat buildChannelDeliveryStat(
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

    return new ChannelDeliveryStat(channelKey, label, safeCount, percent);
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

  public class LogStats {
    @AuraEnabled
    public Integer deliveredCount { get; private set; }
    @AuraEnabled
    public Integer suppressedCount { get; private set; }
    @AuraEnabled
    public Integer queuedCount { get; private set; }
    @AuraEnabled
    public Integer totalCount { get; private set; }

    public LogStats(
      Integer deliveredCount,
      Integer suppressedCount,
      Integer queuedCount
    ) {
      this.deliveredCount = deliveredCount;
      this.suppressedCount = suppressedCount;
      this.queuedCount = queuedCount;
      this.totalCount = deliveredCount + suppressedCount + queuedCount;
    }
  }

  public class InboxStats {
    @AuraEnabled
    public Integer totalCount { get; private set; }
    @AuraEnabled
    public Integer unreadCount { get; private set; }
    @AuraEnabled
    public Integer weekCount { get; private set; }

    public InboxStats(
      Integer totalCount,
      Integer unreadCount,
      Integer weekCount
    ) {
      this.totalCount = totalCount;
      this.unreadCount = unreadCount;
      this.weekCount = weekCount;
    }
  }

  public class DashboardStats {
    @AuraEnabled
    public Integer deliveredTodayCount { get; private set; }
    @AuraEnabled
    public Integer suppressedTodayCount { get; private set; }
    @AuraEnabled
    public Integer queuedCount { get; private set; }
    @AuraEnabled
    public Integer activeHouseholdCount { get; private set; }

    public DashboardStats(
      Integer deliveredTodayCount,
      Integer suppressedTodayCount,
      Integer queuedCount,
      Integer activeHouseholdCount
    ) {
      this.deliveredTodayCount = deliveredTodayCount;
      this.suppressedTodayCount = suppressedTodayCount;
      this.queuedCount = queuedCount;
      this.activeHouseholdCount = activeHouseholdCount;
    }
  }

  public class ChannelDeliveryStat {
    @AuraEnabled
    public String channelKey { get; private set; }
    @AuraEnabled
    public String label { get; private set; }
    @AuraEnabled
    public Integer count { get; private set; }
    @AuraEnabled
    public Integer percent { get; private set; }

    public ChannelDeliveryStat(
      String channelKey,
      String label,
      Integer count,
      Integer percent
    ) {
      this.channelKey = channelKey;
      this.label = label;
      this.count = count;
      this.percent = percent;
    }
  }
}