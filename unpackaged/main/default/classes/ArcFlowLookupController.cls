/**
 * Search backend for c/arcFlowLookup, the LWR-compatible flow-screen lookup
 * used by the ARC-site flow copies (ARC_Log_a_Check). The standard
 * flowruntime:lookup renders in LWR but its inline TypeAhead comes back empty
 * for these objects, leaving users a detour through "Show more results"; this
 * search returns the top name matches directly, the way the launchpad lookup
 * shows them inline.
 */
public with sharing class ArcFlowLookupController {
  /** Objects the lookup may search, with the field shown under the name. */
  private static final Map<String, String> SUBLABEL_BY_OBJECT = new Map<String, String>{
    'Financial_Account__c' => 'Household__r.Name',
    'Account' => null,
    'Contact' => 'Account.Name',
    'Case' => 'Subject'
  };

  @AuraEnabled
  public static List<Map<String, String>> search(String objectApiName, String searchTerm) {
    if (
      String.isBlank(searchTerm) ||
      !SUBLABEL_BY_OBJECT.containsKey(objectApiName)
    ) {
      return new List<Map<String, String>>();
    }

    String sublabelField = SUBLABEL_BY_OBJECT.get(objectApiName);
    String nameField = objectApiName == 'Case' ? 'CaseNumber' : 'Name';
    String term = '%' + String.escapeSingleQuotes(searchTerm) + '%';

    String soql =
      'SELECT Id, ' + nameField +
      (sublabelField != null ? ', ' + sublabelField : '') +
      ' FROM ' + objectApiName +
      ' WHERE ' + nameField + ' LIKE :term' +
      ' ORDER BY ' + nameField + ' LIMIT 5';

    List<Map<String, String>> results = new List<Map<String, String>>();
    for (SObject row : Database.queryWithBinds(
      soql,
      new Map<String, Object>{ 'term' => term },
      AccessLevel.USER_MODE
    )) {
      results.add(
        new Map<String, String>{
          'value' => String.valueOf(row.get('Id')),
          'label' => String.valueOf(row.get(nameField)),
          'sublabel' => resolveSublabel(row, sublabelField)
        }
      );
    }
    return results;
  }

  /** Name of one record, for seeding the box when the flow passes a default. */
  @AuraEnabled
  public static String getRecordLabel(String objectApiName, Id recordId) {
    if (recordId == null || !SUBLABEL_BY_OBJECT.containsKey(objectApiName)) {
      return null;
    }
    String nameField = objectApiName == 'Case' ? 'CaseNumber' : 'Name';
    List<SObject> rows = Database.queryWithBinds(
      'SELECT ' + nameField + ' FROM ' + objectApiName + ' WHERE Id = :recordId LIMIT 1',
      new Map<String, Object>{ 'recordId' => recordId },
      AccessLevel.USER_MODE
    );
    return rows.isEmpty() ? null : String.valueOf(rows[0].get(nameField));
  }

  private static String resolveSublabel(SObject row, String sublabelField) {
    if (sublabelField == null) {
      return null;
    }
    Object value;
    if (sublabelField.contains('.')) {
      List<String> path = sublabelField.split('\\.');
      SObject parent = row.getSObject(path[0]);
      value = parent == null ? null : parent.get(path[1]);
    } else {
      value = row.get(sublabelField);
    }
    return value == null ? null : String.valueOf(value);
  }
}