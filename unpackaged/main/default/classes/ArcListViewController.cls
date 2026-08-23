/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-18
 *
 * Resolves related record display labels for arcListView lookup columns.
 */
public with sharing class ArcListViewController {
  private static final Integer MAX_RECORD_IDS = 500;

  private static final Map<String, String> DISPLAY_FIELD_BY_OBJECT = new Map<String, String>{
    'Case' => 'CaseNumber',
    'Task' => 'Subject'
  };

  @AuraEnabled
  public static Map<String, String> resolveReferenceLabels(List<String> recordIds) {
    Map<String, String> labelsById = new Map<String, String>();

    if (recordIds == null || recordIds.isEmpty()) {
      return labelsById;
    }

    Map<Schema.SObjectType, Set<Id>> idsByObjectType = new Map<Schema.SObjectType, Set<Id>>();
    Integer acceptedCount = 0;

    for (String recordIdValue : recordIds) {
      if (acceptedCount >= MAX_RECORD_IDS) {
        break;
      }

      if (String.isBlank(recordIdValue)) {
        continue;
      }

      Id recordId;

      try {
        recordId = (Id) recordIdValue;
      } catch (Exception error) {
        continue;
      }

      Schema.SObjectType objectType = recordId.getSObjectType();

      if (objectType == null) {
        continue;
      }

      if (!idsByObjectType.containsKey(objectType)) {
        idsByObjectType.put(objectType, new Set<Id>());
      }

      idsByObjectType.get(objectType).add(recordId);
      acceptedCount++;
    }

    for (Schema.SObjectType objectType : idsByObjectType.keySet()) {
      labelsById.putAll(
        queryLabelsForObject(objectType, idsByObjectType.get(objectType))
      );
    }

    return labelsById;
  }

  private static Map<String, String> queryLabelsForObject(
    Schema.SObjectType objectType,
    Set<Id> recordIds
  ) {
    Map<String, String> labelsById = new Map<String, String>();

    if (objectType == null || recordIds == null || recordIds.isEmpty()) {
      return labelsById;
    }

    Schema.DescribeSObjectResult objectDescribe = objectType.getDescribe();

    if (!objectDescribe.isAccessible()) {
      return labelsById;
    }

    String objectApiName = objectDescribe.getName();
    String displayFieldApiName = resolveDisplayFieldApiName(objectDescribe);

    if (String.isBlank(displayFieldApiName)) {
      return labelsById;
    }

    Map<String, Schema.SObjectField> fieldMap = objectDescribe.fields.getMap();
    Schema.DescribeFieldResult displayFieldDescribe = fieldMap.get(
        displayFieldApiName
      )
      ?.getDescribe();

    if (displayFieldDescribe == null || !displayFieldDescribe.isAccessible()) {
      return labelsById;
    }

    String query =
      'SELECT Id, ' +
      String.escapeSingleQuotes(displayFieldApiName) +
      ' FROM ' +
      String.escapeSingleQuotes(objectApiName) +
      ' WHERE Id IN :recordIds WITH USER_MODE';

    for (SObject record : Database.query(query)) {
      Object displayValue = record.get(displayFieldApiName);

      if (displayValue != null) {
        labelsById.put((String) record.get('Id'), String.valueOf(displayValue));
      }
    }

    return labelsById;
  }

  private static String resolveDisplayFieldApiName(
    Schema.DescribeSObjectResult objectDescribe
  ) {
    String objectApiName = objectDescribe.getName();

    if (DISPLAY_FIELD_BY_OBJECT.containsKey(objectApiName)) {
      String configuredField = DISPLAY_FIELD_BY_OBJECT.get(objectApiName);
      Map<String, Schema.SObjectField> fieldMap = objectDescribe.fields.getMap();

      if (fieldMap.containsKey(configuredField)) {
        return configuredField;
      }
    }

    if (objectDescribe.fields.getMap().containsKey('Name')) {
      return 'Name';
    }

    return null;
  }

  @AuraEnabled
  public static Map<String, String> resolveRecordTypeLabels(
    String objectApiName,
    List<String> recordTypeIds
  ) {
    Map<String, String> labelsById = new Map<String, String>();

    if (String.isBlank(objectApiName) || recordTypeIds == null || recordTypeIds.isEmpty()) {
      return labelsById;
    }

    Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);

    if (objectType == null) {
      return labelsById;
    }

    Schema.DescribeSObjectResult objectDescribe = objectType.getDescribe();

    if (!objectDescribe.isAccessible()) {
      return labelsById;
    }

    Set<String> requestedIds = new Set<String>();

    for (String recordTypeIdValue : recordTypeIds) {
      if (String.isNotBlank(recordTypeIdValue)) {
        requestedIds.add(recordTypeIdValue);
      }
    }

    if (requestedIds.isEmpty()) {
      return labelsById;
    }

    for (Schema.RecordTypeInfo recordTypeInfo : objectDescribe.getRecordTypeInfos()) {
      if (recordTypeInfo == null) {
        continue;
      }

      Id recordTypeId = recordTypeInfo.getRecordTypeId();
      String recordTypeIdValue = recordTypeId == null
        ? null
        : String.valueOf(recordTypeId);

      if (recordTypeIdValue == null || !requestedIds.contains(recordTypeIdValue)) {
        continue;
      }

      labelsById.put(recordTypeIdValue, recordTypeInfo.getName());
    }

    return labelsById;
  }
}