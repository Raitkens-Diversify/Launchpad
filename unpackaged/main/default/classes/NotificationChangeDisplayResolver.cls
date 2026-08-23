/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-24
 *
 * Resolves Salesforce record Ids to human-readable display values for change context.
 */
public without sharing class NotificationChangeDisplayResolver {
  private static final String CASE_OBJECT = 'Case';
  private static final String CASE_DISPLAY_FIELD = 'CaseNumber';
  private static final String DEFAULT_DISPLAY_FIELD = 'Name';

  public static void enrichChangeContext(
    NotificationChangeModels.ChangeContext changeContext
  ) {
    if (
      changeContext == null ||
      changeContext.changedFields == null ||
      changeContext.changedFields.isEmpty()
    ) {
      return;
    }

    Map<Id, String> idToDisplay = resolveRecordDisplays(
      collectUnresolvedRecordIds(changeContext)
    );

    for (
      NotificationChangeModels.FieldChange fieldChange : changeContext.changedFields
    ) {
      fieldChange.oldDisplay = resolveDisplayValue(
        fieldChange.oldDisplay,
        fieldChange.oldValue,
        idToDisplay
      );
      fieldChange.newDisplay = resolveDisplayValue(
        fieldChange.newDisplay,
        fieldChange.newValue,
        idToDisplay
      );
    }
  }

  public static Map<Id, String> resolveRecordDisplays(Set<Id> recordIds) {
    Map<Id, String> idToDisplay = new Map<Id, String>();

    if (recordIds == null || recordIds.isEmpty()) {
      return idToDisplay;
    }

    Map<String, Set<Id>> objectApiNameToRecordIds = groupRecordIdsByObjectApiName(
      recordIds
    );

    for (String objectApiName : objectApiNameToRecordIds.keySet()) {
      Set<Id> idsForObject = objectApiNameToRecordIds.get(objectApiName);

      if (idsForObject == null || idsForObject.isEmpty()) {
        continue;
      }

      idToDisplay.putAll(queryRecordDisplays(objectApiName, idsForObject));
    }

    return idToDisplay;
  }

  @TestVisible
  static String resolveDisplayFieldApiName(String objectApiName) {
    return objectApiName == CASE_OBJECT
      ? CASE_DISPLAY_FIELD
      : DEFAULT_DISPLAY_FIELD;
  }

  private static Set<Id> collectUnresolvedRecordIds(
    NotificationChangeModels.ChangeContext changeContext
  ) {
    Set<Id> recordIds = new Set<Id>();

    for (
      NotificationChangeModels.FieldChange fieldChange : changeContext.changedFields
    ) {
      queueUnresolvedRecordId(fieldChange.oldDisplay, fieldChange.oldValue, recordIds);
      queueUnresolvedRecordId(fieldChange.newDisplay, fieldChange.newValue, recordIds);
    }

    return recordIds;
  }

  private static void queueUnresolvedRecordId(
    String displayValue,
    String rawValue,
    Set<Id> recordIds
  ) {
    String unresolvedId = resolveUnresolvedReferenceId(displayValue, rawValue);

    if (String.isBlank(unresolvedId)) {
      return;
    }

    recordIds.add((Id) unresolvedId);
  }

  @TestVisible
  static String resolveUnresolvedReferenceId(
    String displayValue,
    String rawValue
  ) {
    if (String.isBlank(rawValue)) {
      return null;
    }

    if (String.isBlank(displayValue) || displayValue == rawValue) {
      return looksLikeSalesforceId(rawValue) ? rawValue : null;
    }

    return null;
  }

  @TestVisible
  static Boolean looksLikeSalesforceId(String value) {
    if (String.isBlank(value)) {
      return false;
    }

    Integer length = value.length();
    if (length != 15 && length != 18) {
      return false;
    }

    return Pattern.matches('[a-zA-Z0-9]{15}|[a-zA-Z0-9]{18}', value);
  }

  private static String resolveDisplayValue(
    String displayValue,
    String rawValue,
    Map<Id, String> idToDisplay
  ) {
    String unresolvedId = resolveUnresolvedReferenceId(displayValue, rawValue);

    if (String.isBlank(unresolvedId)) {
      return displayValue;
    }

    Id recordId = (Id) unresolvedId;
    return idToDisplay.containsKey(recordId)
      ? idToDisplay.get(recordId)
      : displayValue;
  }

  private static Map<String, Set<Id>> groupRecordIdsByObjectApiName(Set<Id> recordIds) {
    Map<String, Set<Id>> objectApiNameToRecordIds = new Map<String, Set<Id>>();

    for (Id recordId : recordIds) {
      if (recordId == null) {
        continue;
      }

      String objectApiName = recordId.getSObjectType().getDescribe().getName();

      if (!objectApiNameToRecordIds.containsKey(objectApiName)) {
        objectApiNameToRecordIds.put(objectApiName, new Set<Id>());
      }

      objectApiNameToRecordIds.get(objectApiName).add(recordId);
    }

    return objectApiNameToRecordIds;
  }

  private static Map<Id, String> queryRecordDisplays(
    String objectApiName,
    Set<Id> recordIds
  ) {
    Map<Id, String> idToDisplay = new Map<Id, String>();
    String displayFieldApiName = resolveDisplayFieldApiName(objectApiName);
    String query =
      'SELECT Id, ' +
      displayFieldApiName +
      ' FROM ' +
      objectApiName +
      ' WHERE Id IN :recordIds';

    try {
      for (SObject record : Database.query(query)) {
        Object displayValue = record.get(displayFieldApiName);
        idToDisplay.put(
          record.Id,
          displayValue == null
            ? String.valueOf(record.Id)
            : String.valueOf(displayValue)
        );
      }
    } catch (Exception error) {
      return idToDisplay;
    }

    return idToDisplay;
  }
}