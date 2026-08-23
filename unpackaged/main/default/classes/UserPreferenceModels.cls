/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-14
 *
 * Contract for app-level user preference state persisted on User_Preference__c.
 *
 * One row per user + Application_Name__c stores State__c as a versioned JSON
 * document. The root object is an open map: each feature area owns a section
 * key and defines the nested shape for its entries. Writers merge into their
 * section only and must not replace unrelated sections on the same record.
 *
 * {
 *   "version": 1,
 *   "updatedAt": "2026-08-14T12:00:00.000Z",
 *   "<sectionKey>": {
 *     "<entryKey>": { ... arbitrary entry payload ... }
 *   }
 * }
 *
 * Known sections today (add constants here as new features ship):
 * - contexts: chart/table saved views keyed by record Id or "global"
 * - listViews: pinned Salesforce list views keyed by arcListView tableId
 *
 * Use UserPreferenceService.getStateEntry / saveStateEntry for new sections.
 */
public with sharing class UserPreferenceModels {
  public static final Integer STATE_VERSION = 1;
  public static final Integer MAX_STATE_LENGTH = 131072;

  public static final String VERSION_KEY = 'version';
  public static final String UPDATED_AT_KEY = 'updatedAt';

  public static final String CONTEXTS_SECTION_KEY = 'contexts';
  public static final String LIST_VIEWS_SECTION_KEY = 'listViews';

  public static final String GLOBAL_CONTEXT_KEY = 'global';

  public class PreferenceResult {
    @AuraEnabled
    public Id preferenceId { get; set; }
    @AuraEnabled
    public String viewsJson { get; set; }
    @AuraEnabled
    public String lastSelectedViewId { get; set; }

    public PreferenceResult() {
      this.viewsJson = '[]';
      this.lastSelectedViewId = '';
    }

    public PreferenceResult(Id preferenceId, String viewsJson) {
      this(preferenceId, viewsJson, '');
    }

    public PreferenceResult(
      Id preferenceId,
      String viewsJson,
      String lastSelectedViewId
    ) {
      this.preferenceId = preferenceId;
      this.viewsJson = String.isBlank(viewsJson) ? '[]' : viewsJson;
      this.lastSelectedViewId = String.isBlank(lastSelectedViewId)
        ? ''
        : lastSelectedViewId;
    }
  }

  public class StateEntryResult {
    @AuraEnabled
    public Id preferenceId { get; set; }
    @AuraEnabled
    public String entryJson { get; set; }

    public StateEntryResult() {
      this.entryJson = '{}';
    }

    public StateEntryResult(Id preferenceId, String entryJson) {
      this.preferenceId = preferenceId;
      this.entryJson = String.isBlank(entryJson) ? '{}' : entryJson;
    }
  }
}