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
    @AuraEnabled
    public List<SearchRow> rows;
    /** True if the query matched more rows than this page returned. */
    @AuraEnabled
    public Boolean hasMore;
  }

  @AuraEnabled(cacheable=true)
  public static SearchResult searchRecords(
    String objectApiName,
    List<String> fieldApiNames,
    List<SearchFilter> filters,
    String searchTerm,
    List<String> searchableFields,
    Id afterId,
    Integer pageSize
  ) {
    SearchResult result = new SearchResult();
    result.rows = new List<SearchRow>();
    result.hasMore = false;

    Map<String, Schema.SObjectField> fieldMap = describeFields(objectApiName);
    if (fieldMap == null) {
      return result;
    }

    List<String> selected = validateFieldPaths(fieldMap, fieldApiNames);
    if (selected.isEmpty()) {
      return result;
    }

    Map<String, Object> binds = new Map<String, Object>();
    String whereClause = buildWhereClause(
      fieldMap,
      filters,
      searchTerm,
      searchableFields,
      binds
    );

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

    List<SObject> records;
    try {
      records = Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);
    } catch (Exception e) {
      System.debug(LoggingLevel.ERROR, 'ArcRecordSearchController.searchRecords failed: ' + e);
      throw new AuraHandledException('Could not run that search: ' + e.getMessage());
    }

    Integer take = Math.min(records.size(), effectivePageSize);
    for (Integer i = 0; i < take; i++) {
      SObject record = records[i];
      SearchRow row = new SearchRow();
      row.id = (Id) record.get('Id');
      row.cells = new List<String>();
      for (String path : selected) {
        row.cells.add(readPath(record, path));
      }
      result.rows.add(row);
    }
    result.hasMore = records.size() > effectivePageSize;
    return result;
  }

  @AuraEnabled(cacheable=true)
  public static Integer countRecords(
    String objectApiName,
    List<SearchFilter> filters,
    String searchTerm,
    List<String> searchableFields
  ) {
    Map<String, Schema.SObjectField> fieldMap = describeFields(objectApiName);
    if (fieldMap == null) {
      return 0;
    }

    Map<String, Object> binds = new Map<String, Object>();
    String whereClause = buildWhereClause(
      fieldMap,
      filters,
      searchTerm,
      searchableFields,
      binds
    );

    String soql =
      'SELECT COUNT() FROM ' +
      objectApiName +
      (String.isBlank(whereClause) ? '' : ' WHERE ' + whereClause);

    try {
      return Database.countQueryWithBinds(soql, binds, AccessLevel.USER_MODE);
    } catch (Exception e) {
      System.debug(LoggingLevel.ERROR, 'ArcRecordSearchController.countRecords failed: ' + e);
      return 0;
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

    if (String.isNotBlank(searchTerm) && searchableFields != null) {
      List<String> searchClauses = new List<String>();
      String bindKey = 'searchTerm';
      binds.put(bindKey, '%' + escapeLike(searchTerm.trim()) + '%');
      for (String path : searchableFields) {
        if (String.isNotBlank(path) && isReadablePath(fieldMap, path.trim())) {
          searchClauses.add(path.trim() + ' LIKE :' + bindKey);
        }
      }
      if (!searchClauses.isEmpty()) {
        clauses.add('(' + String.join(searchClauses, ' OR ') + ')');
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
    Map<String, Schema.SObjectField> fieldMap,
    String fieldApiName,
    String operatorKey,
    String bindKey,
    String operandValue,
    Map<String, Object> binds
  ) {
    String op = String.isBlank(operatorKey) ? 'Contains' : operatorKey;

    if (op == 'StartsWith') {
      binds.put(bindKey, escapeLike(operandValue) + '%');
      return fieldApiName + ' LIKE :' + bindKey;
    }
    if (op == 'NotContain') {
      binds.put(bindKey, '%' + escapeLike(operandValue) + '%');
      return '(NOT ' + fieldApiName + ' LIKE :' + bindKey + ')';
    }
    if (op != 'Equals' && op != 'NotEqual' && op != 'GreaterThan' &&
        op != 'GreaterOrEqual' && op != 'LessThan' && op != 'LessOrEqual') {
      binds.put(bindKey, '%' + escapeLike(operandValue) + '%');
      return fieldApiName + ' LIKE :' + bindKey;
    }

    Object coerced = coerceBindValue(fieldMap, fieldApiName, operandValue);
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

  /** operandValue coerced to match the target field's own SOQL type. */
  private static Object coerceBindValue(
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
    List<String> hops = path.split('\\.');
    Map<String, Schema.SObjectField> current = fieldMap;

    for (Integer index = 0; index < hops.size(); index++) {
      String hop = hops[index];
      Boolean isLast = index == hops.size() - 1;

      if (isLast) {
        Schema.SObjectField token = current.get(hop);
        return token != null && token.getDescribe().isAccessible();
      }

      Schema.SObjectField token = current.get(hop.endsWith('__r')
        ? hop.removeEnd('__r') + '__c'
        : hop + 'Id');
      if (token == null) {
        return false;
      }

      Schema.DescribeFieldResult describe = token.getDescribe();
      if (
        !describe.isAccessible() ||
        describe.getType() != Schema.DisplayType.REFERENCE ||
        describe.getReferenceTo().isEmpty()
      ) {
        return false;
      }

      current = describe.getReferenceTo()[0].getDescribe().fields.getMap();
    }

    return false;
  }

  private static Schema.DisplayType resolvePathType(
    Map<String, Schema.SObjectField> fieldMap,
    String path
  ) {
    List<String> hops = path.split('\\.');
    Map<String, Schema.SObjectField> current = fieldMap;

    for (Integer index = 0; index < hops.size(); index++) {
      String hop = hops[index];
      if (index == hops.size() - 1) {
        Schema.SObjectField token = current.get(hop);
        return token == null ? Schema.DisplayType.STRING : token.getDescribe().getType();
      }

      Schema.SObjectField token = current.get(hop.endsWith('__r')
        ? hop.removeEnd('__r') + '__c'
        : hop + 'Id');
      if (token == null) {
        return Schema.DisplayType.STRING;
      }
      current = token.getDescribe().getReferenceTo()[0].getDescribe().fields.getMap();
    }

    return Schema.DisplayType.STRING;
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