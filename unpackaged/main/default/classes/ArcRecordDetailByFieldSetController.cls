/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-13
 *
 * Loads field-set metadata and live record values for arcRecordDetailByFieldSet.
 */
public with sharing class ArcRecordDetailByFieldSetController {

  @AuraEnabled
  public static LoadResult load(
    Id recordId,
    String objectApiName,
    String fieldSetApiName
  ) {
    validateInputs(recordId, objectApiName, fieldSetApiName);

    List<FieldSetController.FieldMetadata> fields = FieldSetController.getFieldSetFields(
      objectApiName,
      fieldSetApiName
    );

    LoadResult result = new LoadResult();
    result.objectApiName = objectApiName;
    result.fieldSetApiName = fieldSetApiName;
    result.fields = fields;
    result.values = readRecordValues(recordId, objectApiName, fields);
    return result;
  }

  @AuraEnabled
  public static void save(
    Id recordId,
    String objectApiName,
    String fieldSetApiName,
    Map<String, Object> fields
  ) {
    validateInputs(recordId, objectApiName, fieldSetApiName);

    if (fields == null || fields.isEmpty()) {
      return;
    }

    Set<String> allowedFields = collectEditableFieldPaths(
      FieldSetController.getFieldSetFields(objectApiName, fieldSetApiName)
    );
    Map<String, Object> filtered = filterToAllowedFields(fields, allowedFields);

    if (filtered.isEmpty()) {
      throw new AuraHandledException(
        'There are no editable fields to update in this section.'
      );
    }

    saveRecordFields(recordId, objectApiName, filtered);
  }

  @AuraEnabled
  public static void saveRecordFields(
    Id recordId,
    String objectApiName,
    Map<String, Object> fields
  ) {
    if (fields == null || fields.isEmpty()) {
      return;
    }

    Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
    if (objectType == null) {
      throw new AuraHandledException('Object not found: ' + objectApiName);
    }

    if (!objectType.getDescribe().isUpdateable()) {
      throw new AuraHandledException('You do not have permission to update this record.');
    }

    SObject record = objectType.newSObject(recordId);
    Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();

    for (String fieldApiName : fields.keySet()) {
      if (!fieldMap.containsKey(fieldApiName)) {
        continue;
      }

      record.put(fieldApiName, normalizeSaveValue(fieldMap.get(fieldApiName), fields.get(fieldApiName)));
    }

    SObjectAccessDecision decision = Security.stripInaccessible(
      AccessType.UPDATABLE,
      new List<SObject>{ record }
    );
    update decision.getRecords();
  }

  private static Object normalizeSaveValue(Schema.SObjectField fieldToken, Object value) {
    if (fieldToken == null || value == null) {
      return value;
    }

    Schema.DisplayType fieldType = fieldToken.getDescribe().getType();
    if (fieldType == Schema.DisplayType.MULTIPICKLIST && value instanceof List<Object>) {
      List<String> parts = new List<String>();
      for (Object item : (List<Object>) value) {
        if (item != null) {
          parts.add(String.valueOf(item));
        }
      }
      return String.join(parts, ';');
    }

    return value;
  }

  private static Set<String> collectEditableFieldPaths(
    List<FieldSetController.FieldMetadata> fields
  ) {
    Set<String> allowedFields = new Set<String>();
    for (FieldSetController.FieldMetadata field : fields) {
      if (
        field != null &&
        String.isNotBlank(field.fieldPath) &&
        !field.fieldPath.contains('.') &&
        field.disabled != true
      ) {
        allowedFields.add(field.fieldPath);
      }
    }
    return allowedFields;
  }

  private static Map<String, Object> filterToAllowedFields(
    Map<String, Object> fields,
    Set<String> allowedFields
  ) {
    Map<String, Object> filtered = new Map<String, Object>();
    for (String key : fields.keySet()) {
      if (allowedFields.contains(key)) {
        filtered.put(key, fields.get(key));
      }
    }
    return filtered;
  }

  private static void validateInputs(
    Id recordId,
    String objectApiName,
    String fieldSetApiName
  ) {
    if (recordId == null) {
      throw new AuraHandledException('Record Id is required.');
    }
    if (String.isBlank(objectApiName)) {
      throw new AuraHandledException('Object API Name is required.');
    }
    if (String.isBlank(fieldSetApiName)) {
      throw new AuraHandledException('Field Set API Name is required.');
    }
  }

    @TestVisible
  private static Map<String, Object> readRecordValues(
    Id recordId,
    String objectApiName,
    List<FieldSetController.FieldMetadata> fields
  ) {
    Map<String, Object> values = new Map<String, Object>();
    if (fields == null || fields.isEmpty()) {
      return values;
    }

    Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
    if (objectType == null) {
      return values;
    }

    Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();
    Set<String> queryFieldPaths = buildQueryFieldPaths(fields, fieldMap);

    if (queryFieldPaths.isEmpty()) {
      return values;
    }

    String soql =
      'SELECT ' +
      String.join(new List<String>(queryFieldPaths), ', ') +
      ' FROM ' +
      String.escapeSingleQuotes(objectApiName) +
      ' WHERE Id = :recordId' +
      ' WITH USER_MODE' +
      ' LIMIT 1';

    List<SObject> records = Database.query(soql);
    if (records.isEmpty()) {
      return values;
    }

    SObject record = records[0];
    for (FieldSetController.FieldMetadata field : fields) {
      if (String.isBlank(field.fieldPath)) {
        continue;
      }

      Object value = extractFieldValue(record, field.fieldPath);
      if (value != null) {
        values.put(field.fieldPath, value);
      }
    }

    enrichReferenceFieldMetadata(fields, fieldMap, record, values);
    return values;
  }

  private static Set<String> buildQueryFieldPaths(
    List<FieldSetController.FieldMetadata> fields,
    Map<String, Schema.SObjectField> fieldMap
  ) {
    Set<String> paths = new Set<String>();

    for (FieldSetController.FieldMetadata field : fields) {
      if (String.isBlank(field.fieldPath)) {
        continue;
      }

      if (field.fieldPath.contains('.')) {
        paths.add(field.fieldPath);
        continue;
      }

      Schema.SObjectField fieldToken = fieldMap.get(field.fieldPath);
      if (fieldToken == null) {
        paths.add(field.fieldPath);
        continue;
      }

      Schema.DescribeFieldResult describe = fieldToken.getDescribe();
      paths.add(field.fieldPath);

      String referenceNamePath = buildReferenceNamePath(describe);
      if (String.isNotBlank(referenceNamePath)) {
        paths.add(referenceNamePath);
      }
    }

    return paths;
  }

  private static String buildReferenceNamePath(Schema.DescribeFieldResult describe) {
    if (describe.getType() != Schema.DisplayType.REFERENCE) {
      return null;
    }

    String relationshipName = describe.getRelationshipName();
    if (String.isBlank(relationshipName)) {
      return null;
    }

    List<Schema.SObjectType> references = describe.getReferenceTo();
    if (references == null || references.isEmpty()) {
      return null;
    }

    if (references.size() == 1) {
      String objectApiName = references[0].getDescribe().getName();
      String nameFieldApiName = resolveRelatedDisplayFieldApiName(objectApiName);
      return relationshipName + '.' + nameFieldApiName;
    }

    return relationshipName + '.Name';
  }

  private static void enrichReferenceFieldMetadata(
    List<FieldSetController.FieldMetadata> fields,
    Map<String, Schema.SObjectField> fieldMap,
    SObject record,
    Map<String, Object> values
  ) {
    for (FieldSetController.FieldMetadata field : fields) {
      if (
        field == null ||
        String.isBlank(field.fieldPath) ||
        field.fieldPath.contains('.')
      ) {
        continue;
      }

      Schema.SObjectField fieldToken = fieldMap.get(field.fieldPath);
      if (fieldToken == null) {
        continue;
      }

      Schema.DescribeFieldResult describe = fieldToken.getDescribe();
      if (describe.getType() != Schema.DisplayType.REFERENCE) {
        continue;
      }

      Object idValue = values.get(field.fieldPath);
      if (idValue == null) {
        continue;
      }

      Id relatedId;
      try {
        relatedId = (Id) idValue;
      } catch (Exception error) {
        continue;
      }

      String displayName = resolveReferenceDisplayName(record, describe, relatedId);
      if (String.isBlank(displayName)) {
        continue;
      }

      field.picklistOptions = new List<FieldSetController.PicklistOption>{
        new FieldSetController.PicklistOption(displayName, String.valueOf(relatedId))
      };
      field.referenceTo = relatedId.getSObjectType().getDescribe().getName();
      field.type = 'PICKLIST';
      field.inputType = 'select';
    }
  }

  private static String resolveReferenceDisplayName(
    SObject record,
    Schema.DescribeFieldResult describe,
    Id relatedId
  ) {
    String relationshipName = describe.getRelationshipName();
    if (String.isNotBlank(relationshipName)) {
      SObject relatedRecord = record.getSObject(relationshipName);
      if (relatedRecord != null) {
        String objectApiName = relatedRecord.getSObjectType().getDescribe().getName();
        String displayFieldApiName = resolveRelatedDisplayFieldApiName(objectApiName);
        Object displayValue = relatedRecord.get(displayFieldApiName);
        if (displayValue == null && displayFieldApiName != 'Name') {
          displayValue = relatedRecord.get('Name');
        }
        if (displayValue != null) {
          String displayName = String.valueOf(displayValue).trim();
          if (!String.isBlank(displayName)) {
            return displayName;
          }
        }
      }
    }

    return queryDisplayNameForId(relatedId);
  }

  private static String queryDisplayNameForId(Id relatedId) {
    if (relatedId == null) {
      return null;
    }

    Schema.SObjectType objectType = relatedId.getSObjectType();
    if (objectType == null) {
      return null;
    }

    String objectApiName = objectType.getDescribe().getName();
    String displayFieldApiName = resolveRelatedDisplayFieldApiName(objectApiName);
    Map<String, Schema.SObjectField> relatedFieldMap = objectType.getDescribe().fields.getMap();
    if (!relatedFieldMap.containsKey(displayFieldApiName)) {
      displayFieldApiName = 'Name';
    }

    String soql =
      'SELECT ' +
      displayFieldApiName +
      ' FROM ' +
      String.escapeSingleQuotes(objectApiName) +
      ' WHERE Id = :relatedId' +
      ' WITH USER_MODE' +
      ' LIMIT 1';

    List<SObject> relatedRecords = Database.query(soql);
    if (relatedRecords.isEmpty()) {
      return null;
    }

    Object displayValue = relatedRecords[0].get(displayFieldApiName);
    return displayValue == null ? null : String.valueOf(displayValue).trim();
  }

  private static String resolveRelatedDisplayFieldApiName(String objectApiName) {
    return objectApiName == 'Case' ? 'CaseNumber' : 'Name';
  }

  private static Object extractFieldValue(SObject record, String fieldPath) {
    if (record == null || String.isBlank(fieldPath)) {
      return null;
    }

    if (!fieldPath.contains('.')) {
      return record.get(fieldPath);
    }

    List<String> parts = fieldPath.split('\\.');
    SObject current = record;
    for (Integer index = 0; index < parts.size() - 1; index++) {
      current = current.getSObject(parts[index]);
      if (current == null) {
        return null;
      }
    }

    return current.get(parts[parts.size() - 1]);
  }

  public class LoadResult {
    @AuraEnabled
    public String objectApiName;

    @AuraEnabled
    public String fieldSetApiName;

    @AuraEnabled
    public List<FieldSetController.FieldMetadata> fields;

    @AuraEnabled
    public Map<String, Object> values;
  }
}