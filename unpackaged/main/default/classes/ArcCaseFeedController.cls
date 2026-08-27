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