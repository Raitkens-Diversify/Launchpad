/**
 * Author: Claude
 * Date: 2026-08-27
 *
 * Server-side search/pagination for arcRecordListView's opt-in "server search"
 * mode: a small keyset-paginated page of real, filtered rows on demand,
 * instead of arcRecordListView's default fetch-2000-then-filter-client-side
 * pattern (which silently truncates on any list view with more matches than
 * the fetch cap, and can't apply a user's filter/search server-side at all --
 * lightning/uiListsApi has no WHERE-clause parameter).
 *
 * Pagination is keyset (WHERE Id > :afterId ORDER BY Id), not OFFSET: SOQL's
 * own OFFSET clause is capped at 2000 regardless of who issues the query, so
 * it would only trade one 2000-row ceiling for another.
 *
 * The free-text search term itself routes through ArcSoslSearchHelper for
 * any object with Search enabled -- a maintained full-text index lookup
 * (fast, effectively fuzzy, uniform across field types) instead of a SOQL
 * LIKE scan -- falling back to LIKE only for objects Search is disabled on
 * or a term too short for SOSL to run. See that class for why it's kept
 * separate rather than folded in here.
 *
 * Conventions, matching ArcRelatedListController: every object/field name is
 * validated against the describe before it's concatenated into SOQL (an
 * allowlist drawn from the schema itself); values are always bind variables,
 * never concatenated; every query runs at AccessLevel.USER_MODE (this org's
 * API version rejects combining that with the older WITH SECURITY_ENFORCED
 * clause on a Database.queryWithBinds call, so USER_MODE alone is the
 * enforcement here).
 */
public with sharing class ArcRecordSearchController {
  private static final Integer DEFAULT_PAGE_SIZE = 100;
  private static final Integer MAX_PAGE_SIZE = 200;

  /** One filter chip's worth of criteria, mirroring arcRecordListView's own. */
  public class SearchFilter {
    @AuraEnabled
    public String fieldApiName;
    @AuraEnabled
    public String operator;
    @AuraEnabled
    public String operandValue;
  }

  public class SearchRow {
    @AuraEnabled
    public Id id;
    /** Values in the same order as the requested fieldApiNames. */
    @AuraEnabled
    public List<String> cells;
  }

  public class SearchResult {
    /**
     * The field paths actually selected, in the same order as each row's
     * cells -- not necessarily identical to the requested fieldApiNames.
     * Some requested paths (a UI-API-resolved column name that isn't a
     * plain SOQL-queryable field/relationship path) can fail validation and
     * get silently dropped; a caller that assumed positional alignment with
     * its own request would then read every later cell one column early.
     */
    @AuraEnabled
    public List<String> fieldApiNames;
    @AuraEnabled
    public List<SearchRow> rows;
    /** True if the query matched more rows than this page returned. */
    @AuraEnabled
    public Boolean hasMore;
  }

  // Not cacheable: this session hit real, repeated confusion from a stale
  // cached result surviving a fix that had already landed server-side --
  // the exact params (object/fields/filters/searchTerm/afterId/pageSize)
  // that returned an empty or wrong batch once keep being served back
  // unchanged from cache even after the underlying bug is fixed, with no
  // user-visible signal that what's on screen predates the fix. The
  // load-more chain also means each afterId is its own cache entry, so a
  // stale first page can silently pin an otherwise-fresh chain. A search
  // that always hits the query is the one that can't lie about being
  // out of date.
  /**
   * filters travels as a JSON string, not List<SearchFilter>, and is decoded
   * below with JSON.deserialize -- not a style choice. Confirmed live in
   * this org: the platform's own JSON-to-Apex parameter marshalling for an
   * AuraEnabled method correctly builds a List<SearchFilter> of the right
   * length, but leaves every field on each element (fieldApiName, operator,
   * operandValue) null, even though the client's own request payload has
   * real values -- while every sibling parameter of a plain type (String,
   * List<String>, Id, Integer) on the very same call arrives intact. A
   * blank-fielded filter is indistinguishable from an empty filter chip
   * (buildWhereClause already drops those, by design), so this silently
   * unfiltered every search on every tab that had a filter at all. Apex's
   * own JSON.deserialize onto the identical List<SearchFilter> type, run
   * over the identical JSON text, decodes correctly -- so the failure is
   * specific to the platform's automatic parameter marshalling for a
   * custom multi-field Apex type used as a list element, not to this type
   * or Apex's JSON support in general.
   */
  @AuraEnabled
  public static SearchResult searchRecords(
    String objectApiName,
    List<String> fieldApiNames,
    String filtersJson,
    String searchTerm,
    List<String> searchableFields,
    Id afterId,
    Integer pageSize
  ) {
    List<SearchFilter> filters = String.isNotBlank(filtersJson)
      ? (List<SearchFilter>) JSON.deserialize(filtersJson, List<SearchFilter>.class)
      : new List<SearchFilter>();

    List<String> diagLines = new List<String>();
    diagLines.add(
      '1/7 ENTRY objectApiName=' + objectApiName +
        ' fieldApiNames=' + fieldApiNames +
        ' filtersJson=' + filtersJson +
        ' filters=' + filters +
        ' searchTerm=' + searchTerm +
        ' afterId=' + afterId +
        ' pageSize=' + pageSize +
        ' runningUserId=' + UserInfo.getUserId() +
        ' profileId=' + UserInfo.getProfileId() +
        ' networkId=' + Network.getNetworkId()
    );

    try {
      SearchResult result = new SearchResult();
      result.rows = new List<SearchRow>();
      result.hasMore = false;

      Map<String, Schema.SObjectField> fieldMap = describeFields(objectApiName);
      diagLines.add('2/7 describeFields -> ' + (fieldMap == null ? 'null (object inaccessible)' : fieldMap.size() + ' fields'));
      if (fieldMap == null) {
        throw new AuraHandledException('ARC_DIAG_TRAIL ' + String.join(diagLines, ' || '));
      }

      List<String> selected = validateFieldPaths(fieldMap, fieldApiNames);
      result.fieldApiNames = selected;
      diagLines.add('3/7 validateFieldPaths -> ' + selected);
      if (selected.isEmpty()) {
        throw new AuraHandledException('ARC_DIAG_TRAIL ' + String.join(diagLines, ' || '));
      }

      Map<String, Object> binds = new Map<String, Object>();
      String whereClause = buildWhereClause(
        objectApiName,
        fieldMap,
        filters,
        searchTerm,
        searchableFields,
        binds
      );
      diagLines.add('4/7 buildWhereClause -> "' + whereClause + '" binds=' + binds);

      List<String> clauses = new List<String>();
      if (String.isNotBlank(whereClause)) {
        clauses.add(whereClause);
      }
      if (afterId != null) {
        binds.put('afterId', afterId);
        clauses.add('Id > :afterId');
      }

      Integer effectivePageSize = pageSize == null
        ? DEFAULT_PAGE_SIZE
        : Math.min(Math.max(pageSize, 1), MAX_PAGE_SIZE);
      // One extra row past the page, so "is there more" is known without a
      // second round trip.
      Integer fetchSize = effectivePageSize + 1;

      String soql =
        'SELECT Id, ' +
        String.join(selected, ', ') +
        ' FROM ' +
        objectApiName +
        (clauses.isEmpty() ? '' : ' WHERE ' + String.join(clauses, ' AND ')) +
        ' ORDER BY Id ASC' +
        ' LIMIT ' +
        fetchSize;

      diagLines.add('5/7 final soql=' + soql);

      List<SObject> records = Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);

      diagLines.add('6/7 query returned ' + records.size() + ' rows: ' + records);

      Integer take = Math.min(records.size(), effectivePageSize);
      for (Integer i = 0; i < take; i++) {
        SObject record = records[i];
        SearchRow row = new SearchRow();
        row.id = (Id) record.get('Id');
        row.cells = new List<String>();
        for (String path : selected) {
          // Never a raw null -- the Aura/LWR JSON encoder used for
          // @salesforce/apex imports can silently drop null entries out of a
          // List<String> rather than serializing them as null, which shifts
          // every later cell in the row one column early on the client (a
          // blank Role__pc, for instance, would make every cell after it
          // read as the previous field's value). Confirmed live: a 5-cell
          // response for an 8-field request, empty fields simply missing
          // rather than present-and-blank.
          String cellValue = readPath(record, path);
          row.cells.add(cellValue == null ? '' : cellValue);
        }
        result.rows.add(row);
      }
      result.hasMore = records.size() > effectivePageSize;
      diagLines.add('7/7 RETURN rows=' + result.rows.size() + ' hasMore=' + result.hasMore + ' fieldApiNames=' + result.fieldApiNames);
      throw new AuraHandledException('ARC_DIAG_TRAIL ' + String.join(diagLines, ' || '));
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      diagLines.add('UNHANDLED EXCEPTION: ' + e + ' | ' + e.getStackTraceString());
      throw new AuraHandledException('ARC_DIAG_TRAIL ' + String.join(diagLines, ' || '));
    }
  }

  private static Map<String, Schema.SObjectField> describeFields(String objectApiName) {
    if (String.isBlank(objectApiName)) {
      return null;
    }
    Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
    if (objectType == null || !objectType.getDescribe().isAccessible()) {
      return null;
    }
    return objectType.getDescribe().fields.getMap();
  }

  private static String buildWhereClause(
    String objectApiName,
    Map<String, Schema.SObjectField> fieldMap,
    List<SearchFilter> filters,
    String searchTerm,
    List<String> searchableFields,
    Map<String, Object> binds
  ) {
    List<String> clauses = new List<String>();
    Integer bindIndex = 0;

    if (filters != null) {
      for (SearchFilter filter : filters) {
        if (
          filter == null ||
          String.isBlank(filter.fieldApiName) ||
          String.isBlank(filter.operandValue) ||
          !isReadablePath(fieldMap, filter.fieldApiName)
        ) {
          continue;
        }
        String bindKey = 'v' + bindIndex++;
        String clause = buildFilterClause(
          objectApiName,
          fieldMap,
          filter.fieldApiName,
          filter.operator,
          bindKey,
          filter.operandValue,
          binds
        );
        if (clause != null) {
          clauses.add(clause);
        }
      }
    }

    if (String.isNotBlank(searchTerm)) {
      String trimmedTerm = searchTerm.trim();
      Boolean useSosl = trimmedTerm.length() >= ArcSoslSearchHelper.MIN_TERM_LENGTH &&
        ArcSoslSearchHelper.supportsSearch(objectApiName);

      if (useSosl) {
        // A maintained full-text index lookup: fast (not a column scan),
        // effectively fuzzy (tokenized, matches anywhere, not typed), and
        // works uniformly across every searchable field regardless of
        // type -- none of the LIKE-branch's caveats below apply. An empty
        // match list is authoritative (genuinely zero matches), not a
        // signal to fall through to LIKE as well.
        List<Id> soslIds = ArcSoslSearchHelper.findMatchingIds(objectApiName, trimmedTerm);
        String bindKey = 'soslIds';
        binds.put(bindKey, soslIds);
        clauses.add('Id IN :' + bindKey);
      } else if (searchableFields != null) {
        // Fallback for objects with Search disabled, or a term too short
        // for SOSL to run at all.
        List<String> searchClauses = new List<String>();
        String bindKey = 'searchTerm';
        binds.put(bindKey, '%' + escapeLike(trimmedTerm) + '%');
        for (String rawPath : searchableFields) {
          if (String.isBlank(rawPath)) {
            continue;
          }
          String path = rawPath.trim();
          // SOQL's LIKE operator only works on string-shaped fields -- a
          // displayed column can easily be a Date/Currency/etc, which
          // would otherwise throw "like operator only valid on string
          // field" and fail every search the moment such a column is on
          // screen.
          if (isReadablePath(fieldMap, path) && isLikeCompatibleType(fieldMap, path)) {
            searchClauses.add(path + ' LIKE :' + bindKey);
          }
        }
        if (!searchClauses.isEmpty()) {
          clauses.add('(' + String.join(searchClauses, ' OR ') + ')');
        }
      }
    }

    return clauses.isEmpty() ? '' : String.join(clauses, ' AND ');
  }

  /**
   * One comparison clause. Equals/NotEqual/GreaterThan/GreaterOrEqual/
   * LessThan/LessOrEqual bind a value coerced to the field's own type so a
   * numeric/date comparison works correctly instead of comparing as text;
   * everything else (Contains, StartsWith, NotContain, and any operator this
   * pilot doesn't recognise) falls back to a LIKE. An operand that can't be
   * coerced to the target field's type is skipped rather than failing the
   * whole search.
   */
  private static String buildFilterClause(
    String objectApiName,
    Map<String, Schema.SObjectField> fieldMap,
    String fieldApiName,
    String operatorKey,
    String bindKey,
    String operandValue,
    Map<String, Object> binds
  ) {
    String op = String.isBlank(operatorKey) ? 'Contains' : operatorKey;

    // A record-type filter adopted from a list view's own saved criteria
    // (adoptSavedFilters on the client) arrives as the record type's NAME
    // label (e.g. "Individual"), never its Id -- the UI API only ever
    // hands back operandLabels (confirmed against its own docs: "the
    // values (or label if one exists)"). Confirmed live against this org's
    // own UI API (ui-api/list-ui) that the field name it actually reports
    // for a list view's record-type filter is "RecordType.Name", not
    // "RecordTypeId" -- the RecordTypeId spelling below is kept as a
    // defensive alias in case some other list view surfaces it that way,
    // but every filter observed live used RecordType.Name. A view whose
    // own filter matches more than one record type (e.g. the Households
    // tab, which matches both a FinServ and a plain "Household" record
    // type) arrives as multiple labels joined with "; " by that same
    // client code -- also confirmed live (operandLabels: ["Household",
    // "Household"]). The output clause always targets the real
    // RecordTypeId column (never the input fieldApiName) since resolving
    // down to Ids either way -- comparing RecordType.Name to a List<Id>
    // would be a type mismatch.
    if (fieldApiName == 'RecordTypeId' || fieldApiName == 'RecordType.Name') {
      List<Id> recordTypeIds = resolveRecordTypeIds(objectApiName, operandValue);
      if (recordTypeIds.isEmpty()) {
        return null;
      }
      Boolean isNegative = op == 'NotEqual' || op == 'Excludes' || op == 'NotIn';
      binds.put(bindKey, recordTypeIds);
      return 'RecordTypeId' + (isNegative ? ' NOT IN :' : ' IN :') + bindKey;
    }

    Boolean isLikeOperator = op == 'StartsWith' || op == 'NotContain' ||
      (op != 'Equals' && op != 'NotEqual' && op != 'GreaterThan' &&
       op != 'GreaterOrEqual' && op != 'LessThan' && op != 'LessOrEqual');

    // Same constraint as the free-text search: LIKE only works on
    // string-shaped fields. A field the client offered a text-style
    // operator for anyway (its own operator list falls back to every text
    // operator when the object describe has no per-field metadata) is
    // skipped here rather than sent to SOQL and failing the whole search.
    if (isLikeOperator && !isLikeCompatibleType(fieldMap, fieldApiName)) {
      return null;
    }

    if (op == 'StartsWith') {
      binds.put(bindKey, escapeLike(operandValue) + '%');
      return fieldApiName + ' LIKE :' + bindKey;
    }
    if (op == 'NotContain') {
      binds.put(bindKey, '%' + escapeLike(operandValue) + '%');
      return '(NOT ' + fieldApiName + ' LIKE :' + bindKey + ')';
    }
    if (isLikeOperator) {
      binds.put(bindKey, '%' + escapeLike(operandValue) + '%');
      return fieldApiName + ' LIKE :' + bindKey;
    }

    Object coerced = coerceBindValue(objectApiName, fieldMap, fieldApiName, operandValue);
    if (coerced == null) {
      return null;
    }
    binds.put(bindKey, coerced);

    if (op == 'Equals') {
      return fieldApiName + ' = :' + bindKey;
    }
    if (op == 'NotEqual') {
      return fieldApiName + ' != :' + bindKey;
    }
    if (op == 'GreaterThan') {
      return fieldApiName + ' > :' + bindKey;
    }
    if (op == 'GreaterOrEqual') {
      return fieldApiName + ' >= :' + bindKey;
    }
    if (op == 'LessThan') {
      return fieldApiName + ' < :' + bindKey;
    }
    return fieldApiName + ' <= :' + bindKey;
  }

  /**
   * The RecordType Id(s) whose current Name matches operandValue -- a
   * single label, or several joined with "; " (see the RecordTypeId
   * branch in buildFilterClause for why).
   *
   * Resolved from the object describe's own getRecordTypeInfos() list, not
   * a live `SELECT Id FROM RecordType WHERE ...` query and not
   * Schema.getRecordTypeInfosByName() either:
   *
   * - The live SOQL form silently returns zero rows for some running
   *   users in some Experience Cloud site contexts even for a record type
   *   that demonstrably exists and is in active use -- confirmed directly
   *   against this org (Guest User context): the query found nothing for
   *   Name = 'Business', while Schema.SObjectType.Account.getRecordTypeInfos()
   *   found it immediately, correct Id included. That is exactly the bug
   *   this method used to cause: a RecordType-filtered tab (Businesses,
   *   Retirement Plans, Trusts & Estates) silently lost its WHERE clause
   *   for some site visitors and fell through to an unfiltered, wrong-type
   *   result set instead of failing loudly.
   * - getRecordTypeInfosByName() (a Map keyed by Name) isn't a safe
   *   replacement either: two record types can share an identical label
   *   (this org has that for both "Household" and "Business"), and a Map
   *   can only keep one entry per key, silently collapsing the other.
   *   Iterating the plain list form avoids that collapse the same way the
   *   old SOQL's own "Name IN (...)" did.
   * - Availability (RecordTypeInfo.isAvailable()) is deliberately not
   *   checked: that flag governs whether a user could pick this record
   *   type when creating a record, not whether existing records of that
   *   type may be read/filtered on, which is all this method is for.
   */
  private static List<Id> resolveRecordTypeIds(String objectApiName, String operandValue) {
    List<Id> ids = new List<Id>();
    if (String.isBlank(operandValue) || String.isBlank(objectApiName)) {
      return ids;
    }

    // The UI API hands back record-type labels HTML-entity-encoded when the
    // label itself contains a reserved character -- confirmed live: a
    // record type literally named "Trusts & Estates" comes back as
    // "Trusts &amp; Estates" in operandLabels. Decoding here (rather than
    // client-side) keeps every caller of this method working from the
    // real Name value regardless of where operandValue originated.
    Set<String> labels = new Set<String>();
    for (String label : operandValue.split(';')) {
      String trimmed = label.trim().unescapeHtml4();
      if (String.isNotBlank(trimmed)) {
        labels.add(trimmed);
      }
    }
    if (labels.isEmpty()) {
      return ids;
    }

    Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
    if (objectType == null) {
      return ids;
    }

    for (Schema.RecordTypeInfo info : objectType.getDescribe().getRecordTypeInfos()) {
      if (labels.contains(info.getName())) {
        ids.add(info.getRecordTypeId());
      }
    }
    return ids;
  }

  /** operandValue coerced to match the target field's own SOQL type. */
  private static Object coerceBindValue(
    String objectApiName,
    Map<String, Schema.SObjectField> fieldMap,
    String fieldApiName,
    String operandValue
  ) {
    Schema.DisplayType dataType = resolvePathType(fieldMap, fieldApiName);

    if (
      dataType == Schema.DisplayType.DOUBLE ||
      dataType == Schema.DisplayType.CURRENCY ||
      dataType == Schema.DisplayType.INTEGER ||
      dataType == Schema.DisplayType.PERCENT
    ) {
      try {
        return Decimal.valueOf(operandValue);
      } catch (Exception e) {
        return null;
      }
    }

    if (dataType == Schema.DisplayType.DATE) {
      try {
        return Date.valueOf(operandValue);
      } catch (Exception e) {
        return null;
      }
    }

    if (dataType == Schema.DisplayType.DATETIME) {
      try {
        return Datetime.valueOf(operandValue.replace('T', ' '));
      } catch (Exception e) {
        return null;
      }
    }

    // A list view's own saved filter on a checkbox field (e.g. IsClosed)
    // arrives from the UI API's filteredByInfo as the string "0"/"1", never
    // a real Boolean -- binding that string straight into a dynamic SOQL
    // comparison against a Boolean column throws "Invalid bind expression
    // type of String for column of type Boolean" (confirmed live). "0" and
    // "false" (either case) are the only falsy spellings seen from the UI
    // API or typed by a user; everything else -- "1", "true", anything
    // else -- is treated as true rather than silently dropping the filter.
    if (dataType == Schema.DisplayType.BOOLEAN) {
      String normalized = String.isBlank(operandValue)
        ? ''
        : operandValue.trim().toLowerCase();
      return normalized != '0' && normalized != 'false';
    }

    return operandValue;
  }

  private static String escapeLike(String value) {
    return value.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_');
  }

  /** The requested paths that actually exist and are readable, in order. */
  private static List<String> validateFieldPaths(
    Map<String, Schema.SObjectField> fieldMap,
    List<String> fieldApiNames
  ) {
    List<String> valid = new List<String>();
    if (fieldApiNames == null) {
      return valid;
    }
    for (String path : fieldApiNames) {
      if (String.isNotBlank(path)) {
        String trimmed = path.trim();
        if (isReadablePath(fieldMap, trimmed) && !valid.contains(trimmed)) {
          valid.add(trimmed);
        }
      }
    }
    return valid;
  }

  /**
   * Walks a dotted path hop by hop so a relationship name is resolved
   * against the object it belongs to, not the one it started on -- mirrors
   * ArcRelatedListController's own version of this check.
   */
  private static Boolean isReadablePath(
    Map<String, Schema.SObjectField> fieldMap,
    String path
  ) {
    return isReadablePathFrom(fieldMap, path.split('\\.'), 0);
  }

  /**
   * A polymorphic lookup (Task/Event's OwnerId -> User or Group, WhoId ->
   * Contact or Lead, WhatId -> a long list of object types) can resolve the
   * rest of the path through ANY of its possible target types -- Owner.Alias
   * exists on User but not Group, for instance. getReferenceTo()'s order
   * isn't something to rely on, so every candidate is tried in turn rather
   * than assuming the first one is the right one; a path is valid if any
   * candidate resolves it.
   */
  private static Boolean isReadablePathFrom(
    Map<String, Schema.SObjectField> fieldMap,
    List<String> hops,
    Integer index
  ) {
    String hop = hops[index];
    Boolean isLast = index == hops.size() - 1;

    if (isLast) {
      Schema.SObjectField token = fieldMap.get(hop);
      return token != null && token.getDescribe().isAccessible();
    }

    Schema.SObjectField token = fieldMap.get(hop.endsWith('__r')
      ? hop.removeEnd('__r') + '__c'
      : hop + 'Id');
    if (token == null) {
      return false;
    }

    Schema.DescribeFieldResult describe = token.getDescribe();
    if (!describe.isAccessible() || describe.getType() != Schema.DisplayType.REFERENCE) {
      return false;
    }

    for (Schema.SObjectType candidate : describe.getReferenceTo()) {
      if (isReadablePathFrom(candidate.getDescribe().fields.getMap(), hops, index + 1)) {
        return true;
      }
    }
    return false;
  }

  private static Schema.DisplayType resolvePathType(
    Map<String, Schema.SObjectField> fieldMap,
    String path
  ) {
    Schema.DisplayType resolved = resolvePathTypeFrom(fieldMap, path.split('\\.'), 0);
    return resolved == null ? Schema.DisplayType.STRING : resolved;
  }

  /** Same polymorphic-aware walk as isReadablePathFrom; null means "not found". */
  private static Schema.DisplayType resolvePathTypeFrom(
    Map<String, Schema.SObjectField> fieldMap,
    List<String> hops,
    Integer index
  ) {
    String hop = hops[index];
    if (index == hops.size() - 1) {
      Schema.SObjectField token = fieldMap.get(hop);
      return token == null ? null : token.getDescribe().getType();
    }

    Schema.SObjectField token = fieldMap.get(hop.endsWith('__r')
      ? hop.removeEnd('__r') + '__c'
      : hop + 'Id');
    if (token == null || token.getDescribe().getType() != Schema.DisplayType.REFERENCE) {
      return null;
    }

    for (Schema.SObjectType candidate : token.getDescribe().getReferenceTo()) {
      Schema.DisplayType resolved = resolvePathTypeFrom(
        candidate.getDescribe().fields.getMap(),
        hops,
        index + 1
      );
      if (resolved != null) {
        return resolved;
      }
    }
    return null;
  }

  /**
   * SOQL's LIKE operator only accepts string-shaped fields -- Date,
   * Datetime, number types, Boolean, and Reference (an Id) all throw "like
   * operator only valid on string field" if you try. Everything else
   * (String, TextArea, Email, Phone, Url, Picklist, MultiselectPicklist,
   * Id itself) is fine.
   */
  private static Boolean isLikeCompatibleType(
    Map<String, Schema.SObjectField> fieldMap,
    String path
  ) {
    Schema.DisplayType dataType = resolvePathType(fieldMap, path);
    return dataType != Schema.DisplayType.DATE &&
      dataType != Schema.DisplayType.DATETIME &&
      dataType != Schema.DisplayType.TIME &&
      dataType != Schema.DisplayType.DOUBLE &&
      dataType != Schema.DisplayType.CURRENCY &&
      dataType != Schema.DisplayType.PERCENT &&
      dataType != Schema.DisplayType.INTEGER &&
      dataType != Schema.DisplayType.BOOLEAN &&
      dataType != Schema.DisplayType.REFERENCE;
  }

  /** Walks a dotted path on a queried record; blank when any hop is null. */
  private static String readPath(SObject record, String path) {
    List<String> hops = path.split('\\.');
    SObject cursor = record;

    for (Integer index = 0; index < hops.size() - 1; index++) {
      if (cursor == null) {
        return null;
      }
      cursor = cursor.getSObject(hops[index]);
    }

    if (cursor == null) {
      return null;
    }

    Object value = cursor.get(hops[hops.size() - 1]);
    return formatCellValue(value);
  }

  /**
   * Date/Datetime need an explicit ISO 8601 string, not Apex's own
   * String.valueOf() format (locale/format-dependent, e.g. "2026-08-27
   * 00:00:00" with no "T" or zone) -- arcDataTable's date columns do
   * `new Date(value)` client-side and crash with "Invalid time value" on
   * anything that doesn't parse cleanly. Every other type already
   * stringifies to something Date-safe or isn't rendered as a date at all.
   */
  private static String formatCellValue(Object value) {
    if (value == null) {
      return null;
    }
    if (value instanceof Datetime) {
      return ((Datetime) value).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
    }
    if (value instanceof Date) {
      return Datetime.newInstanceGmt((Date) value, Time.newInstance(0, 0, 0, 0))
        .formatGmt('yyyy-MM-dd');
    }
    return String.valueOf(value);
  }
}