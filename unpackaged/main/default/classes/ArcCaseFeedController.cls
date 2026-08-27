/**
 * Read-only record feed for ARC.
 *
 * Backs c/arcCaseFeedTabs' Feed tab. Returns the same content Lightning's own
 * Chatter feed shows on a record — who, when, and for a creation or field-change
 * post the field-by-field detail — reshaped so a client can render it without
 * knowing anything about FeedItem.
 *
 * WHY NOT ConnectApi. ConnectApi.ChatterFeeds.getFeedElementsFromFeed returns
 * pre-rendered feed elements and would need no reshaping here, but its
 * signatures move between API versions, it is awkward to mock in tests, and it
 * is not callable from a cacheable method. FeedItem with its FeedTrackedChanges
 * child gives the same content from plain SOQL, which is cacheable and testable.
 *
 * Additive: nothing existing calls this and this calls nothing existing.
 *
 * Not Case-specific despite the name — the parent object is taken from the
 * tracked-change field names, so this works on any feed-enabled object. The name
 * records where it is used today.
 */
public with sharing class ArcCaseFeedController {
  private static final Integer DEFAULT_PAGE_SIZE = 10;
  private static final Integer MAX_PAGE_SIZE = 50;

  /**
   * Bookkeeping row the platform attaches to every creation post. It carries no
   * field and no value, and Lightning does not show it.
   */
  private static final String FEED_EVENT_FIELD = 'feedEvent';

  /**
   * History's pseudo-field for "the record was created". Lightning renders it as
   * "Created." rather than looking for a field of that name.
   */
  private static final String HISTORY_CREATED_FIELD = 'created';
  private static final String HISTORY_CREATED_LABEL = 'Created.';

  /**
   * History DataType for the row that carries record IDs. A reference field
   * writes TWO rows per change: this one, and a Text row carrying the readable
   * names. Lightning shows the Text row.
   */
  private static final String DATA_TYPE_ENTITY_ID = 'EntityId';

  /** Describe results are per-transaction; caching keeps repeat lookups cheap. */
  private static Map<String, Map<String, Schema.SObjectField>> fieldsByObject = new Map<String, Map<String, Schema.SObjectField>>();

  /**
   * @param recordId the record whose feed to read
   * @param pageSize how many posts to return; defaults to 10, capped at 50
   */
  @AuraEnabled(cacheable=true)
  public static FeedResult getRecordFeed(Id recordId, Integer pageSize) {
    FeedResult result = new FeedResult();
    result.entries = new List<FeedEntry>();
    result.hasMore = false;

    if (recordId == null) {
      return result;
    }

    Integer size = pageSize == null || pageSize <= 0
      ? DEFAULT_PAGE_SIZE
      : Math.min(pageSize, MAX_PAGE_SIZE);

    // One more than asked for, so hasMore is known without a second query.
    Integer fetchLimit = size + 1;

    List<FeedItem> items = [
      SELECT
        Id,
        Type,
        Title,
        Body,
        CreatedDate,
        CreatedById,
        CreatedBy.Name,
        (SELECT FieldName, OldValue, NewValue FROM FeedTrackedChanges)
      FROM FeedItem
      WHERE ParentId = :recordId
      WITH USER_MODE
      ORDER BY CreatedDate DESC
      LIMIT :fetchLimit
    ];

    result.hasMore = items.size() > size;

    Integer taken = 0;
    for (FeedItem item : items) {
      if (taken == size) {
        break;
      }
      result.entries.add(toEntry(item));
      taken++;
    }

    return result;
  }

  /**
   * Field-change history for a record, shaped the way Lightning's history card
   * renders it: date, field label, who, old value, new value.
   *
   * Why this exists when ArcRelatedListController could already query
   * CaseHistory generically: that returns raw SOQL values, and raw history is
   * not what the page shows. Field comes back as "created" where Lightning shows
   * "Created.", a changed field comes back as its API name where Lightning shows
   * its label, and a reference field arrives as a duplicated pair of rows where
   * Lightning shows one. All three need describe access and dedupe logic, which
   * belong here next to the feed code that already does the same job.
   *
   * @param recordId the record whose history to read
   * @param objectApiName that record's object, used to find the history object
   *        and to resolve field labels
   * @param pageSize how many entries to return; defaults to 10, capped at 50
   */
  @AuraEnabled(cacheable=true)
  public static HistoryResult getRecordHistory(
    Id recordId,
    String objectApiName,
    Integer pageSize
  ) {
    return queryRecordHistory(recordId, objectApiName, 0, pageSize);
  }

  /**
   * Same history as getRecordHistory, but offset/pageSize are caller-
   * controlled instead of always starting at the top -- for a full paginated
   * table (Advertising Item Detail's History section) rather than a fixed
   * first-page rail card. A separate method rather than an optional param on
   * getRecordHistory, same reason ArcRelatedListController.getRelatedRecordsPage
   * is its own method: both are @AuraEnabled(cacheable=true), and Apex
   * overloading on a name LWC imports by string risks the wrong overload.
   *
   * The offset is approximate, not exact: a reference-field change writes two
   * raw history rows (an EntityId row and the Text row Lightning actually
   * shows) that collapseHistory folds into one logical entry, so a flat SOQL
   * OFFSET on the raw object can't be trusted to land on a collapsed-entry
   * boundary. Doubling it keeps every page's raw window comfortably past the
   * true boundary; the same over-fetch-then-truncate collapseHistory already
   * does for page one covers the rest. A logical entry that happens to
   * straddle exactly one page/fetch boundary could in principle be missed --
   * accepted here, same as the single-page method's existing approximation.
   */
  @AuraEnabled(cacheable=true)
  public static HistoryResult getRecordHistoryPage(
    Id recordId,
    String objectApiName,
    Integer offsetValue,
    Integer pageSize
  ) {
    Integer effectiveOffset = offsetValue == null
      ? 0
      : Math.max(offsetValue, 0);
    return queryRecordHistory(recordId, objectApiName, effectiveOffset, pageSize);
  }

  private static HistoryResult queryRecordHistory(
    Id recordId,
    String objectApiName,
    Integer offsetValue,
    Integer pageSize
  ) {
    HistoryResult result = new HistoryResult();
    result.entries = new List<HistoryEntry>();
    result.hasMore = false;

    if (recordId == null || String.isBlank(objectApiName)) {
      return result;
    }

    // Resolved through describe, never interpolated from the caller's string,
    // so there is nothing to inject through. The record id is bound.
    Schema.SObjectType parentType = Schema.getGlobalDescribe().get(objectApiName);

    if (parentType == null) {
      return result;
    }

    String parentName = parentType.getDescribe().getName();
    String historyObject = historyObjectFor(parentName);
    String parentField = historyParentFieldFor(parentName);

    Schema.SObjectType historyType = Schema.getGlobalDescribe().get(historyObject);

    if (historyType == null || !historyType.getDescribe().isAccessible()) {
      // Field history tracking is off for this object, or the user cannot read
      // it. An empty list is the honest answer; a thrown exception would put an
      // error where the page simply has nothing to show.
      return result;
    }

    Integer size = pageSize == null || pageSize <= 0
      ? DEFAULT_PAGE_SIZE
      : Math.min(pageSize, MAX_PAGE_SIZE);

    // Deliberately generous: the raw rows get collapsed below, so asking for
    // exactly one page would come back short whenever reference fields are
    // involved. Two per wanted entry covers the id/name pairing, plus one to
    // detect that more exist.
    Integer fetchLimit = (size * 2) + 1;
    Integer rawOffset = (offsetValue == null ? 0 : offsetValue) * 2;

    String soql =
      'SELECT Id, CreatedDate, CreatedById, CreatedBy.Name, Field, DataType,' +
      ' OldValue, NewValue' +
      ' FROM ' +
      historyType.getDescribe().getName() +
      ' WHERE ' +
      parentField +
      ' = :recordId' +
      ' WITH USER_MODE' +
      ' ORDER BY CreatedDate DESC' +
      ' LIMIT ' +
      fetchLimit +
      ' OFFSET ' +
      rawOffset;

    List<SObject> rows;

    try {
      rows = Database.query(soql);
    } catch (Exception e) {
      // A missing DataType field on an older history object, or an
      // inaccessible parent field, should leave the card empty rather than
      // breaking the page.
      System.debug(
        LoggingLevel.ERROR,
        'ArcCaseFeedController.queryRecordHistory failed for ' +
          historyObject +
          ': ' +
          e
      );
      return result;
    }

    List<HistoryEntry> collapsed = collapseHistory(rows, parentName);

    result.hasMore = collapsed.size() > size;

    Integer taken = 0;
    for (HistoryEntry entry : collapsed) {
      if (taken == size) {
        break;
      }
      result.entries.add(entry);
      taken++;
    }

    return result;
  }

  /**
   * Collapses the duplicated rows a reference-field change produces.
   *
   * A lookup change writes an EntityId row carrying record ids and a Text row
   * carrying their names, at the same instant and by the same user. Rendering
   * both gives a doubled line, one of them showing raw 18-character ids.
   *
   * The key includes the user, not just time and field: the same field really
   * can change twice in one second by different actors -- there is a case in
   * this org where four rows share a timestamp, two logical changes each with
   * its id/name pair -- and keying on time and field alone would silently throw
   * one of them away.
   */
  @TestVisible
  private static List<HistoryEntry> collapseHistory(
    List<SObject> rows,
    String parentName
  ) {
    Map<String, HistoryEntry> byChange = new Map<String, HistoryEntry>();

    if (rows == null) {
      return new List<HistoryEntry>();
    }

    for (SObject row : rows) {
      String field = (String) row.get('Field');

      if (String.isBlank(field)) {
        continue;
      }

      Datetime created = (Datetime) row.get('CreatedDate');
      Id actorId = (Id) row.get('CreatedById');
      String dataType = (String) row.get('DataType');

      String key =
        String.valueOf(created) +
        '|' +
        field +
        '|' +
        String.valueOf(actorId);

      Boolean isCreation = field == HISTORY_CREATED_FIELD;

      HistoryEntry candidate = new HistoryEntry();
      candidate.id = (Id) row.get('Id');
      candidate.createdDate = created;
      candidate.actorId = actorId;
      candidate.actorName = actorNameOf(row);
      candidate.isCreation = isCreation;
      candidate.fieldLabel = isCreation
        ? HISTORY_CREATED_LABEL
        : resolveFieldLabel(parentName, field);
      candidate.oldValue = stringify(row.get('OldValue'));
      candidate.newValue = stringify(row.get('NewValue'));

      HistoryEntry existing = byChange.get(key);

      if (existing == null) {
        byChange.put(key, candidate);
        continue;
      }

      // Keep the readable row. Preferring "not EntityId" rather than "is Text"
      // so a future DataType the platform adds is not thrown away in favour of
      // a row of ids.
      if (dataType != DATA_TYPE_ENTITY_ID) {
        byChange.put(key, candidate);
      }
    }

    return byChange.values();
  }

  /** CaseHistory for a standard object, Foo__History for a custom one. */
  @TestVisible
  private static String historyObjectFor(String objectApiName) {
    return objectApiName.endsWith('__c')
      ? objectApiName.removeEnd('__c') + '__History'
      : objectApiName + 'History';
  }

  /**
   * A custom object's history points at its parent through ParentId; a standard
   * object's uses the object's own name, e.g. CaseHistory.CaseId.
   */
  @TestVisible
  private static String historyParentFieldFor(String objectApiName) {
    return objectApiName.endsWith('__c') ? 'ParentId' : objectApiName + 'Id';
  }

  private static String actorNameOf(SObject row) {
    SObject actor = row.getSObject('CreatedBy');
    return actor == null ? null : (String) actor.get('Name');
  }

  private static FeedEntry toEntry(FeedItem item) {
    FeedEntry entry = new FeedEntry();
    entry.id = item.Id;
    entry.type = item.Type;
    entry.title = item.Title;
    entry.body = item.Body;
    entry.createdDate = item.CreatedDate;
    entry.actorId = item.CreatedById;
    entry.actorName = item.CreatedBy == null ? null : item.CreatedBy.Name;
    entry.changes = toChanges(item.FeedTrackedChanges);
    return entry;
  }

  /**
   * Reshapes the tracked changes of one post.
   *
   * Two things have to be dealt with, both of which show as visible defects if
   * they are not. The platform emits a bare feedEvent row that names no field.
   * And a reference field arrives TWICE — once carrying the record id and once
   * carrying its display name — so rendering the rows as they come gives a
   * duplicated line, one of them showing a raw 18-character id where a person's
   * name belongs.
   */
  private static List<FieldChange> toChanges(List<FeedTrackedChange> raw) {
    List<FieldChange> changes = new List<FieldChange>();

    if (raw == null || raw.isEmpty()) {
      return changes;
    }

    // Insertion-ordered, so the fields keep the order the platform reported.
    Map<String, FieldChange> byField = new Map<String, FieldChange>();

    for (FeedTrackedChange row : raw) {
      String fieldName = row.FieldName;

      if (String.isBlank(fieldName) || fieldName == FEED_EVENT_FIELD) {
        continue;
      }

      String objectName = null;
      String field = fieldName;
      Integer dot = fieldName.indexOf('.');

      if (dot > 0) {
        objectName = fieldName.substring(0, dot);
        field = fieldName.substring(dot + 1);
      }

      FieldChange candidate = new FieldChange();
      candidate.label = resolveFieldLabel(objectName, field);
      candidate.oldValue = stringify(row.OldValue);
      candidate.newValue = stringify(row.NewValue);

      FieldChange existing = byField.get(field);

      if (existing == null) {
        byField.put(field, candidate);
        continue;
      }

      // Same field twice: keep whichever side reads as a name rather than an id.
      // Deliberately not "keep the last one" — that happens to be right for the
      // rows the platform emits today, but it is ordering luck, not a rule.
      if (looksLikeId(existing.newValue) && !looksLikeId(candidate.newValue)) {
        byField.put(field, candidate);
      }
    }

    changes.addAll(byField.values());
    return changes;
  }

  /**
   * Field label as Lightning shows it, which is not the API name: Case.Account
   * is labelled "Account Name" and Case.Owner is "Case Owner".
   *
   * A tracked change names the RELATIONSHIP (Account, Owner) while the field
   * that carries the label is the id field (AccountId, OwnerId), so a miss is
   * retried with an Id suffix before giving up and humanising the API name.
   */
  @TestVisible
  private static String resolveFieldLabel(String objectName, String fieldName) {
    if (String.isBlank(fieldName)) {
      return '';
    }

    Map<String, Schema.SObjectField> fields = describeFields(objectName);

    if (fields != null) {
      Schema.SObjectField token = fields.get(fieldName.toLowerCase());

      if (token == null) {
        token = fields.get(fieldName.toLowerCase() + 'id');
      }

      if (token != null) {
        return token.getDescribe().getLabel();
      }
    }

    return humanise(fieldName);
  }

  private static Map<String, Schema.SObjectField> describeFields(
    String objectName
  ) {
    if (String.isBlank(objectName)) {
      return null;
    }

    if (fieldsByObject.containsKey(objectName)) {
      return fieldsByObject.get(objectName);
    }

    Schema.SObjectType sobjType = Schema.getGlobalDescribe().get(objectName);
    Map<String, Schema.SObjectField> fields = sobjType == null
      ? null
      : sobjType.getDescribe().fields.getMap();

    fieldsByObject.put(objectName, fields);
    return fields;
  }

  /** Last resort when describe cannot place the field: Case_Number__c -> Case Number. */
  @TestVisible
  private static String humanise(String fieldName) {
    String cleaned = fieldName.removeEnd('__c').removeEnd('__r').replace('_', ' ');
    return cleaned.trim();
  }

  /**
   * Whether a value is a record id rather than something worth showing. Length
   * plus alphanumeric is what distinguishes them; Id.valueOf in a try/catch was
   * the alternative, but a 15-character surname would slip through it.
   */
  @TestVisible
  private static Boolean looksLikeId(String value) {
    if (String.isBlank(value)) {
      return false;
    }

    if (value.length() != 15 && value.length() != 18) {
      return false;
    }

    return Pattern.matches('^[a-zA-Z0-9]+$', value);
  }

  private static String stringify(Object value) {
    return value == null ? null : String.valueOf(value);
  }

  // ---- Shapes returned to LWC ---------------------------------------------

  public class FeedResult {
    @AuraEnabled
    public List<FeedEntry> entries;

    /** True when the record has older posts than the page returned. */
    @AuraEnabled
    public Boolean hasMore;
  }

  public class FeedEntry {
    @AuraEnabled
    public Id id;

    /** FeedItem.Type, e.g. CreateRecordEvent, TrackedChange, TextPost. */
    @AuraEnabled
    public String type;

    @AuraEnabled
    public String title;

    @AuraEnabled
    public String body;

    @AuraEnabled
    public Datetime createdDate;

    @AuraEnabled
    public Id actorId;

    @AuraEnabled
    public String actorName;

    /** Empty for a plain text post. */
    @AuraEnabled
    public List<FieldChange> changes;
  }

  public class HistoryResult {
    @AuraEnabled
    public List<HistoryEntry> entries;

    @AuraEnabled
    public Boolean hasMore;
  }

  public class HistoryEntry {
    @AuraEnabled
    public Id id;

    @AuraEnabled
    public Datetime createdDate;

    @AuraEnabled
    public Id actorId;

    @AuraEnabled
    public String actorName;

    /** Field label, or "Created." for the record-created entry. */
    @AuraEnabled
    public String fieldLabel;

    /** True for the record-created entry, which carries no values. */
    @AuraEnabled
    public Boolean isCreation;

    @AuraEnabled
    public String oldValue;

    @AuraEnabled
    public String newValue;
  }

  public class FieldChange {
    /** Field label as Lightning shows it. */
    @AuraEnabled
    public String label;

    /** Null on a creation post — there was no previous value. */
    @AuraEnabled
    public String oldValue;

    @AuraEnabled
    public String newValue;
  }
}