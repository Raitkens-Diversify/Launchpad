/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-24
 *
 * Detects insert and tracked-field updates for any supported notification object.
 */
public with sharing class NotificationChangeDetector {
  private final NotificationTrackedFieldRepository trackedFieldRepository;

  public NotificationChangeDetector() {
    this(new NotificationTrackedFieldRepository());
  }

  @TestVisible
  private NotificationChangeDetector(
    NotificationTrackedFieldRepository trackedFieldRepository
  ) {
    this.trackedFieldRepository = trackedFieldRepository;
  }

  public Map<Id, NotificationChangeModels.ChangeContext> detectInserts(
    String objectType,
    List<SObject> newRecords
  ) {
    Map<Id, NotificationChangeModels.ChangeContext> contextByRecordId = new Map<Id, NotificationChangeModels.ChangeContext>();

    if (String.isBlank(objectType) || newRecords == null || newRecords.isEmpty()) {
      return contextByRecordId;
    }

    for (SObject record : newRecords) {
      if (record.Id == null) {
        continue;
      }

      contextByRecordId.put(
        record.Id,
        new NotificationChangeModels.ChangeContext(
          objectType,
          NotificationConstants.CHANGE_TYPE_INSERT
        )
      );
    }

    return contextByRecordId;
  }

  public Map<Id, NotificationChangeModels.ChangeContext> detectUpdates(
    String objectType,
    Map<Id, SObject> newMap,
    Map<Id, SObject> oldMap
  ) {
    Map<Id, NotificationChangeModels.ChangeContext> contextByRecordId = new Map<Id, NotificationChangeModels.ChangeContext>();

    if (
      String.isBlank(objectType) ||
      newMap == null ||
      newMap.isEmpty() ||
      oldMap == null ||
      oldMap.isEmpty()
    ) {
      return contextByRecordId;
    }

    List<NotificationChangeModels.TrackedFieldDefinition> trackedFields = trackedFieldRepository.selectActiveTrackedFields(
      objectType
    );
    if (trackedFields.isEmpty()) {
      return contextByRecordId;
    }

    Schema.SObjectType sObjectType = newMap.values()[0].getSObjectType();
    Map<String, Schema.SObjectField> fieldMap = sObjectType.getDescribe().fields.getMap();
    List<NotificationChangeModels.TrackedFieldDefinition> validTrackedFields = filterValidTrackedFields(
      trackedFields,
      fieldMap
    );

    if (validTrackedFields.isEmpty()) {
      return contextByRecordId;
    }

    DisplayValueResolver displayResolver = buildDisplayResolver(
      validTrackedFields,
      fieldMap,
      newMap,
      oldMap
    );

    for (Id recordId : newMap.keySet()) {
      SObject newRecord = newMap.get(recordId);
      SObject oldRecord = oldMap.get(recordId);
      if (newRecord == null || oldRecord == null) {
        continue;
      }

      NotificationChangeModels.ChangeContext changeContext = buildUpdateContext(
        objectType,
        newRecord,
        oldRecord,
        validTrackedFields,
        fieldMap,
        displayResolver
      );

      if (changeContext != null && !changeContext.changedFields.isEmpty()) {
        contextByRecordId.put(recordId, changeContext);
      }
    }

    return contextByRecordId;
  }

  private static List<NotificationChangeModels.TrackedFieldDefinition> filterValidTrackedFields(
    List<NotificationChangeModels.TrackedFieldDefinition> trackedFields,
    Map<String, Schema.SObjectField> fieldMap
  ) {
    List<NotificationChangeModels.TrackedFieldDefinition> validTrackedFields = new List<NotificationChangeModels.TrackedFieldDefinition>();

    for (
      NotificationChangeModels.TrackedFieldDefinition trackedField : trackedFields
    ) {
      if (fieldMap.containsKey(trackedField.fieldApiName.toLowerCase())) {
        validTrackedFields.add(trackedField);
      }
    }

    return validTrackedFields;
  }

  private static DisplayValueResolver buildDisplayResolver(
    List<NotificationChangeModels.TrackedFieldDefinition> trackedFields,
    Map<String, Schema.SObjectField> fieldMap,
    Map<Id, SObject> newMap,
    Map<Id, SObject> oldMap
  ) {
    DisplayValueResolver displayResolver = new DisplayValueResolver();
    Set<Id> referenceIds = new Set<Id>();

    for (Id recordId : newMap.keySet()) {
      SObject newRecord = newMap.get(recordId);
      SObject oldRecord = oldMap.get(recordId);
      if (newRecord == null || oldRecord == null) {
        continue;
      }

      for (
        NotificationChangeModels.TrackedFieldDefinition trackedField : trackedFields
      ) {
        Object newValue = newRecord.get(trackedField.fieldApiName);
        Object oldValue = oldRecord.get(trackedField.fieldApiName);
        if (valuesEqual(newValue, oldValue)) {
          continue;
        }

        Schema.DescribeFieldResult fieldDescribe = fieldMap.get(
            trackedField.fieldApiName.toLowerCase()
          )
          .getDescribe();
        displayResolver.queueReferenceResolution(
          oldValue,
          trackedField,
          fieldDescribe,
          referenceIds
        );
        displayResolver.queueReferenceResolution(
          newValue,
          trackedField,
          fieldDescribe,
          referenceIds
        );
      }
    }

    displayResolver.resolveQueuedReferences(referenceIds);
    return displayResolver;
  }

  private static NotificationChangeModels.ChangeContext buildUpdateContext(
    String objectType,
    SObject newRecord,
    SObject oldRecord,
    List<NotificationChangeModels.TrackedFieldDefinition> trackedFields,
    Map<String, Schema.SObjectField> fieldMap,
    DisplayValueResolver displayResolver
  ) {
    NotificationChangeModels.ChangeContext changeContext = new NotificationChangeModels.ChangeContext(
      objectType,
      NotificationConstants.CHANGE_TYPE_UPDATE
    );

    for (
      NotificationChangeModels.TrackedFieldDefinition trackedField : trackedFields
    ) {
      Object newValue = newRecord.get(trackedField.fieldApiName);
      Object oldValue = oldRecord.get(trackedField.fieldApiName);

      if (valuesEqual(newValue, oldValue)) {
        continue;
      }

      Schema.DescribeFieldResult fieldDescribe = fieldMap.get(
          trackedField.fieldApiName.toLowerCase()
        )
        .getDescribe();

      changeContext.changedFields.add(
        new NotificationChangeModels.FieldChange(
          trackedField.fieldApiName,
          trackedField.displayLabel,
          stringifyValue(oldValue),
          stringifyValue(newValue),
          displayResolver.formatDisplayValue(oldValue, trackedField, fieldDescribe),
          displayResolver.formatDisplayValue(newValue, trackedField, fieldDescribe)
        )
      );
    }

    return changeContext.changedFields.isEmpty() ? null : changeContext;
  }

  private static Boolean valuesEqual(Object leftValue, Object rightValue) {
    if (leftValue == null && rightValue == null) {
      return true;
    }

    if (leftValue == null || rightValue == null) {
      return false;
    }

    if (leftValue instanceof Date && rightValue instanceof Date) {
      return ((Date) leftValue) == ((Date) rightValue);
    }

    if (leftValue instanceof Datetime && rightValue instanceof Datetime) {
      return ((Datetime) leftValue) == ((Datetime) rightValue);
    }

    return String.valueOf(leftValue) == String.valueOf(rightValue);
  }

  private static String stringifyValue(Object value) {
    if (value == null) {
      return null;
    }

    if (value instanceof Date) {
      return String.valueOf((Date) value);
    }

    if (value instanceof Datetime) {
      return String.valueOf((Datetime) value);
    }

    return String.valueOf(value);
  }

  private class DisplayValueResolver {
    private final Map<Id, String> referenceIdToDisplay = new Map<Id, String>();

    private void queueReferenceResolution(
      Object value,
      NotificationChangeModels.TrackedFieldDefinition trackedField,
      Schema.DescribeFieldResult fieldDescribe,
      Set<Id> referenceIds
    ) {
      if (value == null || fieldDescribe.getType() != Schema.DisplayType.REFERENCE) {
        return;
      }

      if (
        trackedField.resolveOwnerDisplay != true &&
        trackedField.resolveLookupDisplay != true
      ) {
        return;
      }

      referenceIds.add((Id) value);
    }

    private void resolveQueuedReferences(Set<Id> referenceIds) {
      referenceIdToDisplay.putAll(
        NotificationChangeDisplayResolver.resolveRecordDisplays(referenceIds)
      );
    }

    public String formatDisplayValue(
      Object value,
      NotificationChangeModels.TrackedFieldDefinition trackedField,
      Schema.DescribeFieldResult fieldDescribe
    ) {
      if (value == null) {
        return NotificationConstants.DISPLAY_NOT_APPLICABLE;
      }

      if (
        fieldDescribe.getType() == Schema.DisplayType.REFERENCE &&
        (trackedField.resolveOwnerDisplay == true ||
        trackedField.resolveLookupDisplay == true)
      ) {
        Id referenceId = (Id) value;
        if (referenceIdToDisplay.containsKey(referenceId)) {
          return referenceIdToDisplay.get(referenceId);
        }
      }

      if (value instanceof Date) {
        return ((Date) value).format();
      }

      if (value instanceof Datetime) {
        return ((Datetime) value).format();
      }

      return String.valueOf(value);
    }
  }
}