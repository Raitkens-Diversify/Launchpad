/**
 * NexSListViewController
 *
 * Tells nexSListView which list views on an object the running user saved from
 * the component, so its tab strip can put them back after the browser forgets.
 *
 * The component saves a view through the UI API's createListInfo, which makes a
 * real, private list view in the org — that part always persisted. What did not
 * was the strip's knowledge of which views were "mine": getListInfosByObjectName
 * returns only apiName, id, label and url for each view, with no `visibility`
 * (verified against this org's /ui-api/list-info/Case response), so the
 * component had nothing to recognise a saved view by and kept the list in
 * localStorage instead. A different browser, a cleared profile or a private
 * window and the views vanished from the strip while still existing in
 * Salesforce. The ListView sObject does carry CreatedById, which answers the
 * same question from the server and follows the user everywhere.
 *
 * Conventions:
 * - `with sharing`; every @AuraEnabled entry point asserts object access before
 *   it queries.
 * - Reads are `cacheable=true`; the component refreshes them through refreshApex
 *   after it creates or deletes a view.
 * - No SOQL in loops, and every query is bounded by a named constant.
 * - User-facing failures surface as AuraHandledException.
 */
public with sharing class NexSListViewController {
  /**
   * Views one user creates on one object from a list page. Well past any real
   * usage — the strip collapses everything after the fifth into a More menu —
   * and only there so the query cannot run away on an object someone has been
   * saving views against for years.
   */
  private static final Integer MAX_SAVED_VIEWS = 200;

  // ---- Entry points ------------------------------------------------------

  /**
   * The API names of list views on `objectApiName` that the running user
   * created. Ordered by name so the tab strip is stable across reloads rather
   * than following the org's own row order.
   *
   * Only returns views the user can already see: ListView is subject to sharing
   * and a private view belongs to its creator, so this cannot widen what the
   * UI API would have handed back anyway.
   *
   * An object name nothing matches — a typo, or an object with no views — comes
   * back empty rather than throwing, which is why there is no try/catch here to
   * turn into an AuraHandledException.
   */
  @AuraEnabled(cacheable=true)
  public static List<String> getMySavedListViewNames(String objectApiName) {
    if (String.isBlank(objectApiName)) {
      return new List<String>();
    }

    assertListViewAccessible();

    List<String> names = new List<String>();
    for (ListView view : [
      SELECT DeveloperName
      FROM ListView
      WHERE
        SobjectType = :objectApiName
        AND CreatedById = :UserInfo.getUserId()
      WITH USER_MODE
      ORDER BY DeveloperName
      LIMIT :MAX_SAVED_VIEWS
    ]) {
      names.add(view.DeveloperName);
    }
    return names;
  }

  // ---- Guards ------------------------------------------------------------

  private static void assertListViewAccessible() {
    if (!Schema.sObjectType.ListView.isAccessible()) {
      throw new AuraHandledException(
        'You do not have access to list view definitions.'
      );
    }
  }
}