/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 *
 * Models for notification change context serialized through platform events
 * and stored on Notification_Log__c.Change_Context__c.
 */
public with sharing class NotificationChangeModels {
  public static String formatChangedAtDisplay(
    NotificationChangeModels.ChangeContext changeContext,
    Notification_Log__c logRecord
  ) {
    String changedAtIso = changeContext == null ? null : changeContext.changedAt;
    return formatChangedAtDisplay(changedAtIso, readLogCreatedDate(logRecord));
  }

  public static String formatChangedAtDisplay(
    String changedAtIso,
    Datetime fallbackCreatedDate
  ) {
    Datetime changedAt = parseChangedAt(changedAtIso);

    if (changedAt == null) {
      changedAt = fallbackCreatedDate;
    }

    if (changedAt == null) {
      return NotificationConstants.DISPLAY_NOT_APPLICABLE;
    }

    return changedAt.format('MM/dd/yyyy h:mm a');
  }

  public static Datetime resolveChangedAtDatetime(
    NotificationChangeModels.ChangeContext changeContext,
    Notification_Log__c logRecord
  ) {
    Datetime changedAt = parseChangedAt(
      changeContext == null ? null : changeContext.changedAt
    );

    if (changedAt != null) {
      return changedAt;
    }

    return readLogCreatedDate(logRecord);
  }

  @TestVisible
  private static Datetime readLogCreatedDate(Notification_Log__c logRecord) {
    if (
      logRecord == null ||
      !logRecord.getPopulatedFieldsAsMap().containsKey('CreatedDate')
    ) {
      return null;
    }

    return logRecord.CreatedDate;
  }

  @TestVisible
  private static Datetime parseChangedAt(String changedAtIso) {
    if (String.isBlank(changedAtIso)) {
      return null;
    }

    try {
      String normalizedValue = changedAtIso.trim();
      Integer timezoneIndex = normalizedValue.indexOf('+');

      if (timezoneIndex > -1) {
        normalizedValue = normalizedValue.substring(0, timezoneIndex).trim();
      }

      normalizedValue = normalizedValue.replace('T', ' ');
      normalizedValue = normalizedValue.replace('Z', '');

      Integer fractionalSecondIndex = normalizedValue.indexOf('.');

      if (fractionalSecondIndex > -1) {
        normalizedValue = normalizedValue.substring(0, fractionalSecondIndex);
      }

      return Datetime.valueOfGmt(normalizedValue);
    } catch (Exception error) {
      return null;
    }
  }

  public class ChangeContext {
    public String objectType;
    public String triggerType;
    public String recordId;
    public String recordLabel;
    public String changedByUserId;
    public String changedByUserName;
    public String changedAt;
    public List<FieldChange> changedFields = new List<FieldChange>();

    public ChangeContext() {
      this.changedFields = new List<FieldChange>();
    }

    public ChangeContext(String objectType, String triggerType) {
      this.objectType = objectType;
      this.triggerType = triggerType;
      this.changedFields = new List<FieldChange>();
    }

    public String toJson() {
      List<FieldChange> savedChangedFields = this.changedFields;

      if (NotificationChangeModels.isInsertTriggerType(this.triggerType)) {
        this.changedFields = null;
      }

      try {
        return JSON.serialize(this, true);
      } finally {
        this.changedFields = savedChangedFields == null
          ? new List<FieldChange>()
          : savedChangedFields;
      }
    }

    public void enrichDmlContext(SObject record) {
      enrichRecordContext(record);
      enrichActorContext();

      if (String.isBlank(this.changedAt)) {
        this.changedAt = System.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
      }
    }

    public void enrichRecordContext(SObject record) {
      if (record == null || record.Id == null) {
        return;
      }

      if (String.isBlank(this.recordId)) {
        this.recordId = String.valueOf(record.Id);
      }

      if (String.isBlank(this.recordLabel)) {
        String label = NotificationChangeModels.resolveRecordLabel(record);
        if (!String.isBlank(label)) {
          this.recordLabel = label;
        }
      }
    }

    public void enrichActorContext() {
      if (!String.isBlank(this.changedByUserId)) {
        return;
      }

      Id userId = UserInfo.getUserId();
      if (userId != null) {
        this.changedByUserId = String.valueOf(userId);
      }

      if (String.isBlank(this.changedByUserName)) {
        String userName = UserInfo.getName();
        if (!String.isBlank(userName)) {
          this.changedByUserName = userName;
        }
      }
    }
  }

  public static ChangeContext fromJson(String jsonValue) {
    if (String.isBlank(jsonValue)) {
      return null;
    }

    return (ChangeContext) JSON.deserialize(jsonValue, ChangeContext.class);
  }

  public static String mergeAndEnrichJson(
    String changeContextJson,
    SObject record,
    String sourceType
  ) {
    ChangeContext changeContext = fromJson(changeContextJson);

    if (changeContext == null) {
      changeContext = new ChangeContext(sourceType, null);
    } else if (String.isBlank(changeContext.objectType) && !String.isBlank(sourceType)) {
      changeContext.objectType = sourceType;
    }

    changeContext.enrichRecordContext(record);

    if (String.isBlank(changeContext.changedByUserId)) {
      changeContext.enrichActorContext();
    }

    if (String.isBlank(changeContext.changedAt)) {
      changeContext.changedAt = System.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
    }

    return changeContext.toJson();
  }

  public static String ensureEnrichedJson(
    String changeContextJson,
    String sourceType,
    String sourceId
  ) {
    if (String.isBlank(sourceType) || String.isBlank(sourceId)) {
      return changeContextJson;
    }

    ChangeContext changeContext = fromJson(changeContextJson);
    if (
      changeContext != null &&
      !String.isBlank(changeContext.recordId) &&
      !String.isBlank(changeContext.recordLabel) &&
      !String.isBlank(changeContext.changedByUserId) &&
      !String.isBlank(changeContext.changedAt)
    ) {
      return changeContextJson;
    }

    SObject sourceRecord = querySourceRecord(sourceType, sourceId);
    if (sourceRecord == null) {
      return enrichPartialJson(changeContextJson, sourceType, sourceId);
    }

    return mergeAndEnrichJson(changeContextJson, sourceRecord, sourceType);
  }

  public static Map<Id, String> enrichChangeContextsForDisplay(
    List<Notification_Log__c> logRecords
  ) {
    Map<Id, String> changeContextByLogId = new Map<Id, String>();

    if (logRecords == null || logRecords.isEmpty()) {
      return changeContextByLogId;
    }

    Map<Id, SObject> sourceRecordById = querySourceRecordsForLogs(logRecords);

    for (Notification_Log__c logRecord : logRecords) {
      if (logRecord == null || logRecord.Id == null) {
        continue;
      }

      SObject sourceRecord = resolveSourceRecord(logRecord, sourceRecordById);
      changeContextByLogId.put(
        logRecord.Id,
        enrichChangeContextForDisplay(
          logRecord.Change_Context__c,
          logRecord,
          sourceRecord
        )
      );
    }

    return changeContextByLogId;
  }

  public static String enrichChangeContextForDisplay(
    String changeContextJson,
    Notification_Log__c logRecord,
    SObject sourceRecord
  ) {
    ChangeContext changeContext = fromJson(changeContextJson);

    if (changeContext == null) {
      changeContext = new ChangeContext(
        logRecord == null ? null : logRecord.Source_Type__c,
        null
      );
    } else if (
      logRecord != null &&
      String.isBlank(changeContext.objectType) &&
      !String.isBlank(logRecord.Source_Type__c)
    ) {
      changeContext.objectType = logRecord.Source_Type__c;
    }

    if (sourceRecord != null) {
      changeContext.enrichRecordContext(sourceRecord);
      applyLastModifiedByFallback(changeContext, sourceRecord);
    } else if (
      logRecord != null &&
      String.isBlank(changeContext.recordId) &&
      !String.isBlank(logRecord.Source_Record_Id__c)
    ) {
      changeContext.recordId = logRecord.Source_Record_Id__c;
    }

    if (
      logRecord != null &&
      String.isBlank(changeContext.changedAt) &&
      logRecord.CreatedDate != null
    ) {
      changeContext.changedAt = logRecord.CreatedDate.formatGmt(
        'yyyy-MM-dd\'T\'HH:mm:ss\'Z\''
      );
    }

    return changeContext.toJson();
  }

  @TestVisible
  private static String enrichPartialJson(
    String changeContextJson,
    String sourceType,
    String sourceId
  ) {
    ChangeContext changeContext = fromJson(changeContextJson);

    if (changeContext == null) {
      changeContext = new ChangeContext(sourceType, null);
    } else if (String.isBlank(changeContext.objectType)) {
      changeContext.objectType = sourceType;
    }

    if (String.isBlank(changeContext.recordId)) {
      changeContext.recordId = sourceId;
    }

    if (String.isBlank(changeContext.changedAt)) {
      changeContext.changedAt = System.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
    }

    changeContext.enrichActorContext();
    return changeContext.toJson();
  }

  @TestVisible
  private static SObject resolveSourceRecord(
    Notification_Log__c logRecord,
    Map<Id, SObject> sourceRecordById
  ) {
    if (
      logRecord == null ||
      String.isBlank(logRecord.Source_Record_Id__c) ||
      sourceRecordById == null ||
      sourceRecordById.isEmpty()
    ) {
      return null;
    }

    return sourceRecordById.get((Id) logRecord.Source_Record_Id__c);
  }

  @TestVisible
  private static Map<Id, SObject> querySourceRecordsForLogs(
    List<Notification_Log__c> logRecords
  ) {
    Map<String, Set<Id>> recordIdsBySourceType = new Map<String, Set<Id>>();

    for (Notification_Log__c logRecord : logRecords) {
      if (
        logRecord == null ||
        String.isBlank(logRecord.Source_Type__c) ||
        String.isBlank(logRecord.Source_Record_Id__c)
      ) {
        continue;
      }

      if (!recordIdsBySourceType.containsKey(logRecord.Source_Type__c)) {
        recordIdsBySourceType.put(
          logRecord.Source_Type__c,
          new Set<Id>()
        );
      }

      recordIdsBySourceType.get(logRecord.Source_Type__c)
        .add((Id) logRecord.Source_Record_Id__c);
    }

    Map<Id, SObject> sourceRecordById = new Map<Id, SObject>();

    for (String sourceType : recordIdsBySourceType.keySet()) {
      Set<Id> recordIds = recordIdsBySourceType.get(sourceType);

      if (recordIds == null || recordIds.isEmpty()) {
        continue;
      }

      sourceRecordById.putAll(querySourceRecords(sourceType, recordIds));
    }

    return sourceRecordById;
  }

  @TestVisible
  private static Map<Id, SObject> querySourceRecords(
    String sourceType,
    Set<Id> recordIds
  ) {
    Map<Id, SObject> sourceRecordById = new Map<Id, SObject>();

    if (String.isBlank(sourceType) || recordIds == null || recordIds.isEmpty()) {
      return sourceRecordById;
    }

    if (sourceType == NotificationConstants.OBJECT_TYPE_CASE) {
      for (Case caseRecord : [
        SELECT
          Id,
          CaseNumber,
          Subject,
          LastModifiedById,
          LastModifiedBy.Name
        FROM Case
        WHERE Id IN :recordIds
      ]) {
        sourceRecordById.put(caseRecord.Id, caseRecord);
      }

      return sourceRecordById;
    }

    if (sourceType == NotificationConstants.OBJECT_TYPE_TASK) {
      for (Task taskRecord : [
        SELECT
          Id,
          Subject,
          LastModifiedById,
          LastModifiedBy.Name
        FROM Task
        WHERE Id IN :recordIds
      ]) {
        sourceRecordById.put(taskRecord.Id, taskRecord);
      }

      return sourceRecordById;
    }

    if (sourceType == NotificationConstants.OBJECT_TYPE_EVENT) {
      for (Event eventRecord : [
        SELECT
          Id,
          Subject,
          LastModifiedById,
          LastModifiedBy.Name
        FROM Event
        WHERE Id IN :recordIds
      ]) {
        sourceRecordById.put(eventRecord.Id, eventRecord);
      }
    }

    return sourceRecordById;
  }

  @TestVisible
  private static SObject querySourceRecord(String sourceType, String sourceId) {
    if (String.isBlank(sourceType) || String.isBlank(sourceId)) {
      return null;
    }

    Map<Id, SObject> sourceRecordById = querySourceRecords(
      sourceType,
      new Set<Id>{ (Id) sourceId }
    );

    return sourceRecordById.get((Id) sourceId);
  }

  @TestVisible
  private static void applyLastModifiedByFallback(
    ChangeContext changeContext,
    SObject sourceRecord
  ) {
    if (changeContext == null || sourceRecord == null || !String.isBlank(changeContext.changedByUserName)) {
      return;
    }

    SObject lastModifiedBy = sourceRecord.getSObject('LastModifiedBy');

    if (lastModifiedBy == null) {
      return;
    }

    Object userId = lastModifiedBy.get('Id');
    Object userName = lastModifiedBy.get('Name');

    if (userId != null && String.isBlank(changeContext.changedByUserId)) {
      changeContext.changedByUserId = String.valueOf(userId);
    }

    if (userName != null) {
      changeContext.changedByUserName = String.valueOf(userName);
    }
  }

  public static Boolean isInsertTriggerType(String triggerType) {
    return NotificationConstants.CHANGE_TYPE_INSERT.equalsIgnoreCase(triggerType);
  }

  public class FieldChange {
    public String apiName;
    public String label;
    public String oldValue;
    public String newValue;
    public String oldDisplay;
    public String newDisplay;

    public FieldChange() {
    }

    public FieldChange(
      String apiName,
      String label,
      String oldValue,
      String newValue,
      String oldDisplay,
      String newDisplay
    ) {
      this.apiName = apiName;
      this.label = label;
      this.oldValue = oldValue;
      this.newValue = newValue;
      this.oldDisplay = oldDisplay;
      this.newDisplay = newDisplay;
    }
  }

  public class TrackedFieldDefinition {
    public String objectType;
    public String fieldApiName;
    public String displayLabel;
    public Integer sortOrder;
    public Boolean resolveOwnerDisplay;
    public Boolean resolveLookupDisplay;

    public TrackedFieldDefinition(
      String objectType,
      String fieldApiName,
      String displayLabel,
      Integer sortOrder,
      Boolean resolveOwnerDisplay,
      Boolean resolveLookupDisplay
    ) {
      this.objectType = objectType;
      this.fieldApiName = fieldApiName;
      this.displayLabel = displayLabel;
      this.sortOrder = sortOrder;
      this.resolveOwnerDisplay = resolveOwnerDisplay == true;
      this.resolveLookupDisplay = resolveLookupDisplay == true;
    }
  }

  @TestVisible
  private static String resolveRecordLabel(SObject record) {
    if (record == null) {
      return null;
    }

    String objectApiName = record.getSObjectType().getDescribe().getName();
    Map<String, Schema.SObjectField> fieldMap = record.getSObjectType()
      .getDescribe()
      .fields.getMap();

    if (
      objectApiName == NotificationConstants.OBJECT_TYPE_CASE &&
      fieldMap.containsKey('casenumber')
    ) {
      Object caseNumber = record.get('CaseNumber');
      if (caseNumber != null) {
        return String.valueOf(caseNumber);
      }
    }

    if (fieldMap.containsKey('subject')) {
      Object subject = record.get('Subject');
      if (subject != null) {
        return String.valueOf(subject);
      }
    }

    if (fieldMap.containsKey('name')) {
      Object nameValue = record.get('Name');
      if (nameValue != null) {
        return String.valueOf(nameValue);
      }
    }

    return null;
  }
}