/**
 * Author: Claude
 * Date: 2026-08-17
 *
 * Generic child-record list for Experience Cloud record pages: the records of
 * one object that point at the record on the page through one lookup.
 *
 * Conventions:
 * - Every part of the query that is not a bind variable is validated against
 *   the describe before it is concatenated. Object and field names cannot be
 *   bind variables, so an unrecognised name is rejected outright rather than
 *   escaped — an allowlist drawn from the schema itself.
 * - `with sharing`, plus explicit CRUD/FLS checks on top.
 * - One query, bounded by a named constant. No SOQL in a loop.
 */
public with sharing class ArcRelatedListController {
  /** A card on a record page, not a list view. */
  private static final Integer ROW_LIMIT = 10;

  /** One past the limit, so "10+" is known without a second COUNT() query. */
  private static final Integer FETCH_LIMIT = 11;

  /**
   * @param objectApiName child object, e.g. Check_Deposit__c
   * @param parentFieldApiName the child's lookup to the page's record
   * @param fieldApiNames ordered columns; dotted relationship paths allowed
   * @param linkFieldApiName the id a row navigates to; blank means the row's
   *        own Id. Files are queried through ContentDocumentLink, whose own Id
   *        is the join row rather than anything a reader can open, so that
   *        list points at ContentDocumentId instead.
   */
  @AuraEnabled(cacheable=true)
  public static RelatedRecords getRelatedRecords(
    Id recordId,
    String objectApiName,
    String parentFieldApiName,
    List<String> fieldApiNames,
    String linkFieldApiName
  ) {
    if (recordId == null) {
      throw new AuraHandledException('Record Id is required.');
    }
    if (String.isBlank(objectApiName) || String.isBlank(parentFieldApiName)) {
      throw new AuraHandledException(
        'An object and parent field are required.'
      );
    }

    Schema.SObjectType objectType = Schema.getGlobalDescribe()
      .get(objectApiName);
    if (objectType == null) {
      throw new AuraHandledException('Object not found: ' + objectApiName);
    }
    if (!objectType.getDescribe().isAccessible()) {
      return emptyResult();
    }

    Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe()
      .fields.getMap();
    if (!fieldMap.containsKey(parentFieldApiName)) {
      throw new AuraHandledException(
        'Unknown parent field: ' + parentFieldApiName
      );
    }

    List<String> selected = validateFieldPaths(fieldMap, fieldApiNames);
    if (selected.isEmpty()) {
      return emptyResult();
    }

    // Selected alongside the columns so a row can point somewhere other than
    // its own record without a second query.
    String linkField = String.isNotBlank(linkFieldApiName) &&
      fieldMap.containsKey(linkFieldApiName)
      ? linkFieldApiName
      : 'Id';

    List<String> selectList = new List<String>(selected);
    if (linkField != 'Id' && !selectList.contains(linkField)) {
      selectList.add(linkField);
    }

    // Every token below came from the describe map above, never from the
    // caller's string, so there is nothing here to inject through. The one
    // caller-supplied value is the record id, which is bound.
    String soql =
      'SELECT Id, ' +
      String.join(selectList, ', ') +
      ' FROM ' +
      objectType.getDescribe().getName() +
      ' WHERE ' +
      parentFieldApiName +
      ' = :recordId' +
      ' WITH USER_MODE' +
      ' ORDER BY ' +
      resolveSortField(fieldMap) +
      ' DESC' +
      ' LIMIT ' +
      FETCH_LIMIT;

    RelatedRecords result = new RelatedRecords();
    result.rows = new List<RelatedRow>();
    // The client formats currencies and dates for the reader's locale, which
    // it can only do knowing what each column holds.
    result.types = new List<String>();
    for (String path : selected) {
      result.types.add(resolvePathType(fieldMap, path));
    }
    result.currencyCode = UserInfo.getDefaultCurrency();

    for (SObject record : Database.query(soql)) {
      RelatedRow row = new RelatedRow();
      row.id = record.Id;
      row.linkId = linkField == 'Id'
        ? String.valueOf(record.Id)
        : String.valueOf(record.get(linkField));
      row.cells = new List<String>();
      for (String path : selected) {
        row.cells.add(readPath(record, path));
      }
      result.rows.add(row);
    }

    result.hasMore = result.rows.size() > ROW_LIMIT;
    if (result.hasMore) {
      result.rows.remove(ROW_LIMIT);
    }
    return result;
  }

  /**
   * The requested paths that actually exist and are readable, in order.
   *
   * A dotted path is walked hop by hop so a relationship name is resolved
   * against the object it belongs to, not the one it started on — otherwise a
   * mistyped path would reach the query and fail the whole card.
   */
  private static List<String> validateFieldPaths(
    Map<String, Schema.SObjectField> fieldMap,
    List<String> fieldApiNames
  ) {
    List<String> valid = new List<String>();
    if (fieldApiNames == null) {
      return valid;
    }

    for (String path : fieldApiNames) {
      if (String.isBlank(path)) {
        continue;
      }
      if (isReadablePath(fieldMap, path.trim())) {
        valid.add(path.trim());
      }
    }
    return valid;
  }

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

      // A relationship hop: Foo__r resolves through the Foo__c field, and a
      // standard relationship (Owner) through its own Id field.
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

  /**
   * Newest first, by whichever timestamp the object actually has.
   *
   * Not every object carries CreatedDate: ContentDocumentLink, which is how
   * the Files list is queried, has no such column and rejects the query
   * outright. Id is the last resort — on a Salesforce id, descending is
   * still newest-first.
   */
  private static String resolveSortField(
    Map<String, Schema.SObjectField> fieldMap
  ) {
    for (String candidate : new List<String>{ 'CreatedDate', 'SystemModstamp' }) {
      if (fieldMap.containsKey(candidate)) {
        return candidate;
      }
    }
    return 'Id';
  }

  /** The DisplayType of a validated path's final hop, e.g. CURRENCY. */
  private static String resolvePathType(
    Map<String, Schema.SObjectField> fieldMap,
    String path
  ) {
    List<String> hops = path.split('\\.');
    Map<String, Schema.SObjectField> current = fieldMap;

    for (Integer index = 0; index < hops.size(); index++) {
      String hop = hops[index];
      if (index == hops.size() - 1) {
        Schema.SObjectField token = current.get(hop);
        return token == null
          ? 'STRING'
          : String.valueOf(token.getDescribe().getType());
      }

      Schema.SObjectField token = current.get(hop.endsWith('__r')
        ? hop.removeEnd('__r') + '__c'
        : hop + 'Id');
      if (token == null) {
        return 'STRING';
      }
      current = token.getDescribe().getReferenceTo()[0].getDescribe()
        .fields.getMap();
    }

    return 'STRING';
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
    return value == null ? null : String.valueOf(value);
  }

  private static RelatedRecords emptyResult() {
    RelatedRecords result = new RelatedRecords();
    result.rows = new List<RelatedRow>();
    result.hasMore = false;
    return result;
  }

  // ---- Wrappers exposed to LWC ------------------------------------------

  public class RelatedRecords {
    @AuraEnabled
    public List<RelatedRow> rows;

    @AuraEnabled
    public Boolean hasMore;

    /** DisplayType per column, in the order the columns were requested. */
    @AuraEnabled
    public List<String> types;

    @AuraEnabled
    public String currencyCode;
  }

  public class RelatedRow {
    @AuraEnabled
    public Id id;

    /** The record a click on this row opens; usually the row itself. */
    @AuraEnabled
    public String linkId;

    /** Values in the same order as the requested columns. */
    @AuraEnabled
    public List<String> cells;
  }
}