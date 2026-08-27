/**
 * Author: Claude
 * Date: 2026-08-27
 *
 * SOSL free-text lookup for ArcRecordSearchController's server-search mode.
 * For any object with search enabled, a SOSL FIND is a maintained full-text
 * index lookup -- fast and effectively fuzzy (tokenized, matches anywhere in
 * the field, not typed) -- instead of a raw SOQL LIKE scan, which forces a
 * real column scan (a leading wildcard can't use a standard index) and
 * errors outright on a non-string field. Mirrors the header search's own
 * proven pattern (ArcGlobalSearchController.sanitizeSearch) rather than
 * inventing a new one.
 *
 * Deliberately its own class, not folded into ArcRecordSearchController:
 * the two concerns (building/paginating a SOQL query vs. a SOSL text-match
 * lookup) don't share logic, and keeping SOSL isolated here means any
 * future consumer that needs "does this object support search" / "which
 * ids match this term" can reuse it without depending on the SOQL engine
 * at all.
 */
public with sharing class ArcSoslSearchHelper {
  private static final Integer SOSL_ID_LOOKUP_LIMIT = 2000;
  /** Public so a caller can decide whether a term even qualifies for SOSL
   *  before calling findMatchingIds, e.g. to fall back to a LIKE-based
   *  search for a too-short term instead of getting an empty result back. */
  public static final Integer MIN_TERM_LENGTH = 2;

  /**
   * True when objectApiName has Search enabled. Standard objects (Account,
   * Case, Task, ...) almost always do; custom objects default to Search
   * disabled unless explicitly turned on (Financial_Account__c and
   * Check_Deposit__c are off in this org; Check_Log__c, Product__c, and
   * Advertising_Item__c are on -- confirmed live, not assumed). Checked via
   * describe rather than a hardcoded list, so this stays correct if an
   * object's search setting ever changes.
   */
  public static Boolean supportsSearch(String objectApiName) {
    if (String.isBlank(objectApiName)) {
      return false;
    }
    Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
    return objectType != null && objectType.getDescribe().isSearchable();
  }

  /**
   * The Ids of objectApiName records whose indexed text matches searchTerm
   * anywhere (contains, not just prefix) via the platform's maintained
   * search index -- not a live scan. Always returns a list (never null),
   * empty for a blank/too-short term or an unsearchable object, so a
   * caller can safely AND the result into a SOQL WHERE Id IN (...) without
   * a separate guard.
   */
  public static List<Id> findMatchingIds(String objectApiName, String searchTerm) {
    List<Id> ids = new List<Id>();
    String cleanTerm = sanitizeSearchTerm(searchTerm);
    if (cleanTerm.length() < MIN_TERM_LENGTH || !supportsSearch(objectApiName)) {
      return ids;
    }

    String findExpr = '*' + cleanTerm + '*';
    String sosl =
      'FIND \'' +
      findExpr +
      '\' IN ALL FIELDS RETURNING ' +
      objectApiName +
      '(Id LIMIT ' +
      SOSL_ID_LOOKUP_LIMIT +
      ')';

    List<List<SObject>> results;
    try {
      results = Search.query(sosl);
    } catch (Exception e) {
      System.debug(LoggingLevel.ERROR, 'ArcSoslSearchHelper.findMatchingIds failed: ' + e);
      return ids;
    }

    if (!results.isEmpty()) {
      for (SObject record : results[0]) {
        ids.add(record.Id);
      }
    }
    return ids;
  }

  /**
   * Strips everything except alphanumerics and spaces (replaced with a
   * space, not dropped, so word boundaries survive -- "O'Brien" becomes
   * "O Brien", not "OBrien"), removing every SOSL reserved character and
   * quote so there is nothing left to inject with. Mirrors
   * ArcGlobalSearchController.sanitizeSearch, the pattern already proven
   * live behind the header search bar.
   */
  private static String sanitizeSearchTerm(String term) {
    if (term == null) {
      return '';
    }
    return term.replaceAll('[^a-zA-Z0-9 ]', ' ').trim();
  }
}