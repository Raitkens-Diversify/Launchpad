/**
 * Activity panel for ARC.
 *
 * Backs c/arcActivityPanel, which redraws the Activity | Chatter panel from the
 * right rail of the Lightning account record page. Everything this returns was
 * shaped against the live panel on
 * /lightning/r/Account/<id>/view, not guessed: the four filter groups, the
 * activity types and the Upcoming & Overdue / past split below all come from
 * that panel's own Timeline Settings dialog.
 *
 * WHAT FEEDS THE TIMELINE. Task and Event, and nothing else. That is not a
 * simplification -- on an Account, a sent email lands as a Task with
 * TaskSubtype = 'Email', a logged call as TaskSubtype = 'Call', a list email as
 * 'ListEmail'. The subtype IS the activity type, which is why one query per
 * object covers all six types the settings dialog offers. EmailMessage is
 * deliberately not queried: its RelatedToId is a Case-shaped relationship and
 * the Account timeline does not read it.
 *
 * PERSON ACCOUNTS. A Task or Event may NOT carry a person account in WhatId --
 * the platform rejects it -- so activities on a person account hang off WhoId
 * pointing at PersonContactId. Reads therefore match on AccountId as well as
 * WhatId, and writes choose WhoId or WhatId from the record. See describeScope.
 *
 * Additive: nothing existing calls this, and the only existing thing it leans on
 * is the platform. The Chatter tab's post list comes from
 * ArcCaseFeedController.getRecordFeed, which already exists and is untouched;
 * this class supplies only what that method does not return (comments) and the
 * writes.
 */
public with sharing class ArcActivityPanelController {
  private static final Integer DEFAULT_PAGE_SIZE = 25;
  private static final Integer MAX_PAGE_SIZE = 200;

  /** Date ranges, verbatim from the Timeline Settings dialog's DATE RANGE group. */
  @TestVisible
  private static final String RANGE_NEXT_7 = 'next7';
  @TestVisible
  private static final String RANGE_LAST_7 = 'last7';
  @TestVisible
  private static final String RANGE_LAST_30 = 'last30';

  /** ACTIVITIES TO SHOW: "My activities" narrows to the running user. */
  private static final String SCOPE_MINE = 'mine';

  private static final String KIND_TASK = 'Task';
  private static final String KIND_EVENT = 'Event';

  private static final String TYPE_EVENT = 'event';

  /**
   * ACTIVITY TYPE filter key -> the TaskSubtype values it selects.
   *
   * 'Web' is listed by the dialog and has no matching subtype in every org. A
   * SOQL IN clause against a picklist value that is not in use is still valid
   * and simply matches nothing, so this needs no describe call to stay safe.
   */
  private static final Map<String, String> TASK_SUBTYPE_BY_TYPE = new Map<String, String>{
    'task' => 'Task',
    'email' => 'Email',
    'call' => 'Call',
    'listemail' => 'ListEmail',
    'web' => 'Web'
  };

  /** Type key -> the label the Lightning timeline puts on the row. */
  private static final Map<String, String> LABEL_BY_TYPE = new Map<String, String>{
    'task' => 'Task',
    'email' => 'Email',
    'call' => 'Logged Call',
    'listemail' => 'List Email',
    'web' => 'Web',
    'event' => 'Event'
  };

  /** Type key -> SLDS icon, matching what the Lightning timeline draws. */
  private static final Map<String, String> ICON_BY_TYPE = new Map<String, String>{
    'task' => 'standard:task',
    'email' => 'standard:email',
    'call' => 'standard:log_a_call',
    'listemail' => 'standard:email',
    'web' => 'standard:link',
    'event' => 'standard:event'
  };

  // ==========================================================================
  // Read
  // ==========================================================================

  /**
   * Every activity on a record, split the way the Lightning panel splits it.
   *
   * @param recordId   the record the panel sits on
   * @param dateRange  'all' (default), 'next7', 'last7' or 'last30'
   * @param scope      'all' (default) or 'mine'
   * @param types      any of task, email, call, listemail, web, event; null or
   *                   empty means all of them
   * @param pageSize   how many PAST activities to return; upcoming and overdue
   *                   are never truncated, because the panel shows all of them
   */
  @AuraEnabled(cacheable=true)
  public static ActivityResult getActivities(
    Id recordId,
    String dateRange,
    String scope,
    List<String> types,
    Integer pageSize
  ) {
    ActivityResult result = new ActivityResult();
    result.upcoming = new List<ActivityEntry>();
    result.past = new List<ActivityEntry>();
    result.hasMore = false;
    result.totalCount = 0;

    if (recordId == null) {
      return result;
    }

    Integer size = pageSize == null || pageSize <= 0
      ? DEFAULT_PAGE_SIZE
      : Math.min(pageSize, MAX_PAGE_SIZE);

    Set<String> wanted = normaliseTypes(types);
    RecordScope rs = describeScope(recordId);

    List<ActivityEntry> all = new List<ActivityEntry>();

    if (wantsAnyTaskType(wanted)) {
      all.addAll(queryTasks(rs, dateRange, scope, wanted));
    }
    if (wanted.contains(TYPE_EVENT)) {
      all.addAll(queryEvents(rs, dateRange, scope));
    }

    all.sort();

    /*
     * Upcoming & Overdue is everything still open or still to happen; the rest
     * is past. Both are built from the same sorted list so a single activity can
     * never appear in both.
     */
    List<ActivityEntry> past = new List<ActivityEntry>();
    for (ActivityEntry entry : all) {
      if (entry.isUpcoming) {
        result.upcoming.add(entry);
      } else {
        past.add(entry);
      }
    }

    // Ascending out of sort(); the panel shows the nearest upcoming date first
    // and the most recent past date first.
    result.past = reversed(past);

    result.hasMore = result.past.size() > size;
    if (result.hasMore) {
      List<ActivityEntry> trimmed = new List<ActivityEntry>();
      for (Integer i = 0; i < size; i++) {
        trimmed.add(result.past[i]);
      }
      result.past = trimmed;
    }

    result.totalCount = result.upcoming.size() + result.past.size();
    return result;
  }

  /**
   * Comments on a set of feed posts.
   *
   * Exists because ArcCaseFeedController.getRecordFeed returns the posts and
   * their tracked changes but not their comments, and that class is not being
   * modified. Called with the ids the feed already returned, so it adds one
   * query rather than a second feed read.
   */
  @AuraEnabled(cacheable=true)
  public static List<FeedComment> getFeedComments(List<Id> feedItemIds) {
    if (feedItemIds == null || feedItemIds.isEmpty()) {
      return new List<FeedComment>();
    }

    return [
      SELECT Id, FeedItemId, CommentBody, CreatedDate, CreatedById, CreatedBy.Name
      FROM FeedComment
      WHERE FeedItemId IN :feedItemIds
      WITH USER_MODE
      ORDER BY CreatedDate ASC
      LIMIT 500
    ];
  }

  // ==========================================================================
  // Write
  // ==========================================================================

  /**
   * The panel's New Event action.
   *
   * All-day events are stored differently from timed ones: the platform wants
   * IsAllDayEvent with a date and a duration, not a start and an end, and
   * rejects the pair. Both shapes are built here so the client can send one
   * flag instead of knowing that.
   */
  @AuraEnabled
  public static Id createEvent(
    Id recordId,
    String subject,
    Datetime startDateTime,
    Datetime endDateTime,
    Boolean allDay,
    String location,
    String description
  ) {
    if (recordId == null) {
      throw fail('A record is required.');
    }
    if (String.isBlank(subject)) {
      throw fail('Subject is required.');
    }
    if (startDateTime == null) {
      throw fail('A start date and time is required.');
    }

    Event record = new Event(Subject = subject.trim());
    record.Description = description;
    record.Location = location;

    if (allDay == true) {
      record.IsAllDayEvent = true;
      record.ActivityDateTime = startDateTime;
      record.DurationInMinutes = 1440;
    } else {
      if (endDateTime == null || endDateTime <= startDateTime) {
        throw fail('The end must be after the start.');
      }
      record.StartDateTime = startDateTime;
      record.EndDateTime = endDateTime;
    }

    applyRelationship(record, describeScope(recordId));
    insertAsUser(record);
    return record.Id;
  }

  /**
   * The panel's Email action, which LOGS an email against the record.
   *
   * It does not send one. The Lightning composer sends through the org's email
   * relay and its own deliverability settings; reproducing that from a portal
   * would be sending real mail to real clients from a button, so this writes the
   * activity only. The record it writes is the same one a send produces -- a
   * completed Task with TaskSubtype 'Email' -- so it lands on the timeline
   * looking exactly like a sent email, and wiring a real send later means adding
   * the send, not reshaping the activity.
   */
  @AuraEnabled
  public static Id logEmail(
    Id recordId,
    String subject,
    String toAddress,
    String body
  ) {
    if (recordId == null) {
      throw fail('A record is required.');
    }
    if (String.isBlank(subject)) {
      throw fail('Subject is required.');
    }

    Task record = new Task(
      Subject = subject.trim(),
      Status = 'Completed',
      ActivityDate = Date.today(),
      TaskSubtype = 'Email'
    );

    // The recipient is part of the record of what happened, and Task has no
    // field for it, so it is kept at the top of the description the way a logged
    // email reads in Lightning.
    List<String> lines = new List<String>();
    if (String.isNotBlank(toAddress)) {
      lines.add('To: ' + toAddress.trim());
    }
    if (String.isNotBlank(body)) {
      lines.add(body);
    }
    record.Description = String.join(lines, '\n\n');

    applyRelationship(record, describeScope(recordId));
    insertAsUser(record);
    return record.Id;
  }

  /** The Chatter publisher's Share action. */
  @AuraEnabled
  public static Id postToFeed(Id recordId, String body) {
    if (recordId == null) {
      throw fail('A record is required.');
    }
    if (String.isBlank(body)) {
      throw fail('There is nothing to post.');
    }

    FeedItem post = new FeedItem(ParentId = recordId, Body = body.trim());
    insertAsUser(post);
    return post.Id;
  }

  /** The Comment action under a Chatter post. */
  @AuraEnabled
  public static Id addFeedComment(Id feedItemId, String body) {
    if (feedItemId == null) {
      throw fail('A post is required.');
    }
    if (String.isBlank(body)) {
      throw fail('There is nothing to post.');
    }

    FeedComment comment = new FeedComment(
      FeedItemId = feedItemId,
      CommentBody = body.trim()
    );
    insertAsUser(comment);
    return comment.Id;
  }

  // ==========================================================================
  // Queries
  // ==========================================================================

  private static List<ActivityEntry> queryTasks(
    RecordScope rs,
    String dateRange,
    String scope,
    Set<String> wanted
  ) {
    List<String> subtypes = new List<String>();
    for (String type : wanted) {
      if (TASK_SUBTYPE_BY_TYPE.containsKey(type)) {
        subtypes.add(TASK_SUBTYPE_BY_TYPE.get(type));
      }
    }

    List<String> clauses = new List<String>{ relationshipClause(rs) };
    Map<String, Object> binds = relationshipBinds(rs);

    // Only constrain the subtype when the user has narrowed it. Selecting every
    // type is the default, and an unconstrained query also picks up rows whose
    // subtype is blank -- older data, which the Lightning panel still lists.
    if (subtypes.size() < TASK_SUBTYPE_BY_TYPE.size()) {
      clauses.add('TaskSubtype IN :subtypes');
      binds.put('subtypes', subtypes);
    }

    addDateClause(clauses, binds, dateRange);
    addScopeClause(clauses, binds, scope);

    String soql =
      'SELECT Id, Subject, Status, ActivityDate, TaskSubtype, IsClosed, ' +
      'Description, OwnerId, Owner.Name, WhatId, What.Name, WhoId, Who.Name, CreatedDate ' +
      'FROM Task WHERE ' +
      String.join(clauses, ' AND ') +
      ' ORDER BY ActivityDate DESC NULLS LAST LIMIT ' +
      String.valueOf(MAX_PAGE_SIZE * 2);

    List<ActivityEntry> entries = new List<ActivityEntry>();
    Date today = Date.today();

    for (Task record : (List<Task>) Database.queryWithBinds(
      soql,
      binds,
      AccessLevel.USER_MODE
    )) {
      entries.add(toEntry(record, today));
    }
    return entries;
  }

  private static List<ActivityEntry> queryEvents(
    RecordScope rs,
    String dateRange,
    String scope
  ) {
    List<String> clauses = new List<String>{ relationshipClause(rs) };
    Map<String, Object> binds = relationshipBinds(rs);

    addDateClause(clauses, binds, dateRange);
    addScopeClause(clauses, binds, scope);

    String soql =
      'SELECT Id, Subject, ActivityDate, ActivityDateTime, StartDateTime, EndDateTime, ' +
      'DurationInMinutes, IsAllDayEvent, Description, Location, OwnerId, Owner.Name, ' +
      'WhatId, What.Name, WhoId, Who.Name, CreatedDate ' +
      'FROM Event WHERE ' +
      String.join(clauses, ' AND ') +
      ' ORDER BY ActivityDate DESC NULLS LAST LIMIT ' +
      String.valueOf(MAX_PAGE_SIZE * 2);

    List<ActivityEntry> entries = new List<ActivityEntry>();
    Datetime now = Datetime.now();

    for (Event record : (List<Event>) Database.queryWithBinds(
      soql,
      binds,
      AccessLevel.USER_MODE
    )) {
      entries.add(toEntry(record, now));
    }
    return entries;
  }

  /**
   * How an activity reaches this record.
   *
   * AccountId is included for an Account because it is the only field that
   * catches an activity logged against a person account's contact, and WhatId is
   * kept alongside it because a household or business account carries activities
   * there directly.
   */
  @TestVisible
  private static String relationshipClause(RecordScope rs) {
    if (rs.isAccount) {
      return rs.personContactId == null
        ? '(AccountId = :recordId OR WhatId = :recordId)'
        : '(AccountId = :recordId OR WhatId = :recordId OR WhoId = :personContactId)';
    }
    return rs.isPerson ? 'WhoId = :recordId' : 'WhatId = :recordId';
  }

  private static Map<String, Object> relationshipBinds(RecordScope rs) {
    Map<String, Object> binds = new Map<String, Object>{
      'recordId' => rs.recordId
    };
    if (rs.personContactId != null) {
      binds.put('personContactId', rs.personContactId);
    }
    return binds;
  }

  /**
   * DATE RANGE. Both objects are filtered on ActivityDate: Event carries it as
   * well as StartDateTime, and using the same Date field on both keeps one bind
   * type across the two queries. An all-day event has no StartDateTime at all,
   * so ActivityDate is the more reliable of the two anyway.
   */
  @TestVisible
  private static void addDateClause(
    List<String> clauses,
    Map<String, Object> binds,
    String dateRange
  ) {
    Date today = Date.today();
    Date fromDate;
    Date toDate;

    if (RANGE_NEXT_7.equals(dateRange)) {
      fromDate = today;
      toDate = today.addDays(7);
    } else if (RANGE_LAST_7.equals(dateRange)) {
      fromDate = today.addDays(-7);
      toDate = today;
    } else if (RANGE_LAST_30.equals(dateRange)) {
      fromDate = today.addDays(-30);
      toDate = today;
    } else {
      return; // All time
    }

    clauses.add('ActivityDate >= :fromDate');
    clauses.add('ActivityDate <= :toDate');
    binds.put('fromDate', fromDate);
    binds.put('toDate', toDate);
  }

  /** ACTIVITIES TO SHOW. */
  private static void addScopeClause(
    List<String> clauses,
    Map<String, Object> binds,
    String scope
  ) {
    if (!SCOPE_MINE.equals(scope)) {
      return;
    }
    clauses.add('OwnerId = :ownerId');
    binds.put('ownerId', UserInfo.getUserId());
  }

  // ==========================================================================
  // Shaping
  // ==========================================================================

  @TestVisible
  private static ActivityEntry toEntry(Task record, Date today) {
    ActivityEntry entry = new ActivityEntry();
    entry.id = record.Id;
    entry.kind = KIND_TASK;
    entry.typeKey = typeKeyForSubtype(record.TaskSubtype);
    entry.typeLabel = LABEL_BY_TYPE.get(entry.typeKey);
    entry.iconName = ICON_BY_TYPE.get(entry.typeKey);
    entry.title = String.isBlank(record.Subject)
      ? '[No subject]'
      : record.Subject;
    entry.description = record.Description;
    entry.status = record.Status;
    entry.ownerName = record.Owner == null ? null : record.Owner.Name;
    entry.relatedName = relatedNameFor(record.What, record.Who);
    entry.activityDate = record.ActivityDate;
    entry.isAllDay = false;
    entry.isClosed = record.IsClosed == true;

    /*
     * The panel's split. An open task is upcoming whether or not it has a due
     * date -- a task with no date is still outstanding work, and Lightning lists
     * it under Upcoming & Overdue rather than hiding it in the past.
     */
    entry.isUpcoming = !entry.isClosed;
    entry.isOverdue =
      !entry.isClosed &&
      record.ActivityDate != null &&
      record.ActivityDate < today;

    entry.sortDate = record.ActivityDate == null
      ? record.CreatedDate
      : startOfDay(record.ActivityDate);
    return entry;
  }

  @TestVisible
  private static ActivityEntry toEntry(Event record, Datetime now) {
    ActivityEntry entry = new ActivityEntry();
    entry.id = record.Id;
    entry.kind = KIND_EVENT;
    entry.typeKey = TYPE_EVENT;
    entry.typeLabel = LABEL_BY_TYPE.get(TYPE_EVENT);
    entry.iconName = ICON_BY_TYPE.get(TYPE_EVENT);
    entry.title = String.isBlank(record.Subject)
      ? '[No subject]'
      : record.Subject;
    entry.description = record.Description;
    entry.location = record.Location;
    entry.ownerName = record.Owner == null ? null : record.Owner.Name;
    entry.relatedName = relatedNameFor(record.What, record.Who);
    entry.activityDate = record.ActivityDate;
    entry.startDateTime = record.StartDateTime;
    entry.endDateTime = record.EndDateTime;
    entry.isAllDay = record.IsAllDayEvent == true;
    entry.isClosed = false;

    /*
     * An event is upcoming until it has finished. An all-day event has no
     * EndDateTime, so its own day counts as still to come.
     */
    Datetime ends = record.EndDateTime;
    if (ends == null && record.ActivityDate != null) {
      ends = startOfDay(record.ActivityDate).addDays(1);
    }
    entry.isUpcoming = ends == null || ends >= now;
    entry.isOverdue = false;

    entry.sortDate = record.StartDateTime != null
      ? record.StartDateTime
      : (record.ActivityDate == null
          ? record.CreatedDate
          : startOfDay(record.ActivityDate));
    return entry;
  }

  /**
   * A blank or unrecognised TaskSubtype is treated as a plain task, which is how
   * Lightning draws it -- older rows predate subtypes entirely.
   */
  @TestVisible
  private static String typeKeyForSubtype(String subtype) {
    if (String.isBlank(subtype)) {
      return 'task';
    }
    String lowered = subtype.toLowerCase();
    return LABEL_BY_TYPE.containsKey(lowered) ? lowered : 'task';
  }

  private static String relatedNameFor(SObject what, SObject who) {
    if (what != null) {
      Object name = what.get('Name');
      if (name != null) {
        return String.valueOf(name);
      }
    }
    if (who != null) {
      Object name = who.get('Name');
      if (name != null) {
        return String.valueOf(name);
      }
    }
    return null;
  }

  private static Datetime startOfDay(Date value) {
    return Datetime.newInstance(value, Time.newInstance(0, 0, 0, 0));
  }

  @TestVisible
  private static List<ActivityEntry> reversed(List<ActivityEntry> entries) {
    List<ActivityEntry> out = new List<ActivityEntry>();
    for (Integer i = entries.size() - 1; i >= 0; i--) {
      out.add(entries[i]);
    }
    return out;
  }

  /** Null or empty means every type, which is the panel's default. */
  @TestVisible
  private static Set<String> normaliseTypes(List<String> types) {
    Set<String> wanted = new Set<String>();
    if (types != null) {
      for (String type : types) {
        if (String.isNotBlank(type)) {
          wanted.add(type.trim().toLowerCase());
        }
      }
    }
    if (wanted.isEmpty()) {
      wanted.addAll(TASK_SUBTYPE_BY_TYPE.keySet());
      wanted.add(TYPE_EVENT);
    }
    return wanted;
  }

  private static Boolean wantsAnyTaskType(Set<String> wanted) {
    for (String type : TASK_SUBTYPE_BY_TYPE.keySet()) {
      if (wanted.contains(type)) {
        return true;
      }
    }
    return false;
  }

  // ==========================================================================
  // Record context
  // ==========================================================================

  /**
   * What kind of record this is, and therefore how an activity attaches to it.
   *
   * The person-account lookup is one query and only for Accounts; every other
   * object needs nothing but its own id.
   */
  @TestVisible
  private static RecordScope describeScope(Id recordId) {
    RecordScope rs = new RecordScope();
    rs.recordId = recordId;

    Schema.SObjectType sobjectType = recordId.getSObjectType();
    String name = String.valueOf(sobjectType);

    rs.isAccount = 'Account'.equalsIgnoreCase(name);
    rs.isPerson = 'Contact'.equalsIgnoreCase(name) || 'Lead'.equalsIgnoreCase(name);

    if (rs.isAccount) {
      List<Account> accounts = [
        SELECT Id, IsPersonAccount, PersonContactId
        FROM Account
        WHERE Id = :recordId
        WITH USER_MODE
        LIMIT 1
      ];
      if (!accounts.isEmpty() && accounts[0].IsPersonAccount == true) {
        rs.personContactId = accounts[0].PersonContactId;
      }
    }

    return rs;
  }

  /**
   * Points a new activity at the record.
   *
   * WhatId cannot hold a person account, so a person account's activities go on
   * its contact instead. Getting this wrong is not a cosmetic problem: the
   * platform rejects the insert outright.
   */
  private static void applyRelationship(SObject record, RecordScope rs) {
    if (rs.personContactId != null) {
      record.put('WhoId', rs.personContactId);
      return;
    }
    if (rs.isPerson) {
      record.put('WhoId', rs.recordId);
      return;
    }
    record.put('WhatId', rs.recordId);
  }

  /**
   * Raises a message the client can actually display.
   *
   * new AuraHandledException(text) alone does not always carry its message
   * through to error.body.message; the client sees "Script-thrown exception".
   * setMessage is what makes the text survive the trip.
   */
  private static AuraHandledException fail(String message) {
    AuraHandledException error = new AuraHandledException(message);
    error.setMessage(message);
    return error;
  }

  /**
   * Inserts in user mode so the portal user's own create permission and sharing
   * decide the outcome, and reports a failure as a message the panel can show
   * rather than an unhandled exception.
   */
  private static void insertAsUser(SObject record) {
    try {
      Database.insert(record, true, AccessLevel.USER_MODE);
    } catch (Exception e) {
      throw fail(e.getMessage());
    }
  }

  // ==========================================================================
  // Wire types
  // ==========================================================================

  @TestVisible
  private class RecordScope {
    public Id recordId;
    public Boolean isAccount = false;
    public Boolean isPerson = false;
    public Id personContactId;
  }

  public class ActivityResult {
    /** Open tasks and events still to happen. Never truncated. */
    @AuraEnabled
    public List<ActivityEntry> upcoming;

    /** Completed tasks and finished events, most recent first. */
    @AuraEnabled
    public List<ActivityEntry> past;

    /** True when the record has older activities than the page returned. */
    @AuraEnabled
    public Boolean hasMore;

    @AuraEnabled
    public Integer totalCount;
  }

  /**
   * Sorts ascending by the date the panel groups on, so the caller reverses once
   * for the past list rather than sorting twice.
   */
  public class ActivityEntry implements Comparable {
    @AuraEnabled
    public Id id;

    /** Task or Event. */
    @AuraEnabled
    public String kind;

    /** task, email, call, listemail, web or event. */
    @AuraEnabled
    public String typeKey;

    @AuraEnabled
    public String typeLabel;

    @AuraEnabled
    public String iconName;

    @AuraEnabled
    public String title;

    @AuraEnabled
    public String description;

    @AuraEnabled
    public String status;

    @AuraEnabled
    public String location;

    @AuraEnabled
    public String ownerName;

    /** The What or Who the activity hangs off, for the row's second line. */
    @AuraEnabled
    public String relatedName;

    @AuraEnabled
    public Date activityDate;

    @AuraEnabled
    public Datetime startDateTime;

    @AuraEnabled
    public Datetime endDateTime;

    @AuraEnabled
    public Boolean isAllDay;

    @AuraEnabled
    public Boolean isClosed;

    @AuraEnabled
    public Boolean isUpcoming;

    @AuraEnabled
    public Boolean isOverdue;

    @AuraEnabled
    public Datetime sortDate;

    public Integer compareTo(Object other) {
      ActivityEntry that = (ActivityEntry) other;

      if (this.sortDate == null && that.sortDate == null) {
        return 0;
      }
      // A dateless row sorts last either way round, the way ActivityDate DESC
      // NULLS LAST puts it at the bottom in SOQL.
      if (this.sortDate == null) {
        return 1;
      }
      if (that.sortDate == null) {
        return -1;
      }
      if (this.sortDate == that.sortDate) {
        return 0;
      }
      return this.sortDate < that.sortDate ? -1 : 1;
    }
  }
}