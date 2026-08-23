/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-12
 *
 * Loads and saves metadata-driven record detail forms (Envelope_Field__mdt schema)
 * for Experience Cloud record pages.
 */
public with sharing class ArcRecordDetailController {
  @AuraEnabled
  public static RecordDetailContext load(
    Id recordId,
    String objectName,
    Boolean useRelatedRecord,
    String relatedRecordLookupField
  ) {
    validateRecordId(recordId);

    Id pageRecordId = recordId;
    String pageObjectName = resolveObjectName(recordId, objectName);
    DisplayRecordResolution displayResolution = resolveDisplayRecord(
      recordId,
      pageObjectName,
      useRelatedRecord,
      relatedRecordLookupField
    );

    if (displayResolution.hidden == true) {
      return buildHiddenContext(pageRecordId);
    }

    recordId = displayResolution.displayRecordId;
    String resolvedObjectName = resolveObjectName(recordId, null);
    RecordResolution resolution = resolveRecordContext(
      recordId,
      resolvedObjectName
    );
    String resolvedSchemaType = resolution.schemaType;

    RecordDetailContext context = new RecordDetailContext();
    context.pageRecordId = pageRecordId;
    context.displayRecordId = recordId;
    context.hidden = false;
    context.objectApiName = resolvedObjectName;
    context.schemaType = resolvedSchemaType;
    context.isPersonAccount = resolution.isPersonAccount;
    context.sections = FieldDetailController.getFormSchema(
      resolvedObjectName,
      resolvedSchemaType
    );

    Map<String, List<FieldDetailController.SectionGroup>> layouts =
      FieldDetailController.getSectionLayouts();
    context.sectionLayout = layouts.containsKey(resolvedSchemaType)
      ? layouts.get(resolvedSchemaType)
      : new List<FieldDetailController.SectionGroup>();

    Map<Id, Map<String, Object>> valuesById =
      FieldDetailController.getRecordValuesForType(
        resolvedObjectName,
        resolvedSchemaType,
        new List<Id>{ recordId }
      );
    context.values = valuesById.containsKey(recordId)
      ? valuesById.get(recordId)
      : new Map<String, Object>();

    if (hasRelatedObjectFields(
      resolvedObjectName,
      resolvedSchemaType,
      context.sections
    )) {
      RecordQueryUtil.mergeRelatedRecordValues(
        recordId,
        resolvedObjectName,
        resolvedSchemaType,
        context.sections,
        context.values
      );
    }

    ensureVisibilityContextValues(
      recordId,
      resolvedObjectName,
      context.sections,
      context.values
    );

    normalizeValuesForWire(context.values, context.sections);

    context.userContext = buildUserContext();
    context.isSubmitted = resolution.isSubmitted;
    return context;
  }

  @AuraEnabled
  public static void save(
    Id recordId,
    String objectName,
    Boolean useRelatedRecord,
    String relatedRecordLookupField,
    Map<String, Object> fields
  ) {
    validateRecordId(recordId);

    if (fields == null || fields.isEmpty()) {
      return;
    }

    String pageObjectName = resolveObjectName(recordId, objectName);
    DisplayRecordResolution displayResolution = resolveDisplayRecord(
      recordId,
      pageObjectName,
      useRelatedRecord,
      relatedRecordLookupField
    );

    if (displayResolution.hidden == true) {
      throw new AuraHandledException(ARCConstants.ERROR_RECORD_NOT_FOUND);
    }

    recordId = displayResolution.displayRecordId;
    String resolvedObjectName = resolveObjectName(recordId, null);
    RecordResolution resolution = resolveRecordContext(
      recordId,
      resolvedObjectName
    );
    String resolvedSchemaType = resolution.schemaType;

    if (resolution.isSubmitted) {
      throw new AuraHandledException(ARCConstants.ERROR_SUBMITTED_RECORD);
    }

    Set<String> allowedFields = collectAllowedFieldPaths(
      recordId,
      resolvedObjectName,
      resolvedSchemaType
    );
    Map<String, Object> filtered = filterToAllowedFields(fields, allowedFields);
    filtered = filterFieldsForRecord(recordId, resolvedObjectName, filtered);
    filtered = removePersonAccountName(filtered, resolution.isPersonAccount);

    if (filtered.isEmpty()) {
      throw new AuraHandledException(ARCConstants.ERROR_NO_EDITABLE_FIELDS);
    }

    if (resolvedObjectName == ARCConstants.OBJECT_ACCOUNT) {
      saveAccountRecord(recordId, resolvedSchemaType, filtered);
      return;
    }

    if (resolvedObjectName != ARCConstants.OBJECT_ACCOUNT && hasRelatedObjectFields(
      resolvedObjectName,
      resolvedSchemaType,
      FieldDetailController.getFormSchema(resolvedObjectName, resolvedSchemaType)
    )) {
      savePrimaryWithRelatedRecords(
        recordId,
        resolvedObjectName,
        resolvedSchemaType,
        filtered,
        FieldDetailController.getFormSchema(resolvedObjectName, resolvedSchemaType)
      );
      return;
    }

    saveGenericRecord(recordId, resolvedObjectName, filtered);
  }

  private static void saveAccountRecord(
    Id recordId,
    String schemaType,
    Map<String, Object> filtered
  ) {
    String memberType = ARCConstants.SCHEMA_TYPE_TO_MEMBER_TYPE.get(schemaType);
    if (String.isBlank(memberType)) {
      throw new AuraHandledException(ARCConstants.ERROR_UNSUPPORTED_ACCOUNT_SCHEMA);
    }

    Map<String, Object> accountPayload = new Map<String, Object>(filtered);
    accountPayload.put(ARCConstants.FIELD_ID, recordId);
    accountPayload.put(ARCConstants.FIELD_RECORD_TYPE_ID, memberType);

    EnvelopeHouseholdMemberController.saveEntity(accountPayload, null, null);
  }

  private static void saveGenericRecord(
    Id recordId,
    String objectName,
    Map<String, Object> filtered
  ) {
    Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectName);
    if (objectType == null) {
      throw new AuraHandledException(ARCConstants.ERROR_OBJECT_NOT_FOUND + objectName);
    }

    if (!objectType.getDescribe().isUpdateable()) {
      throw new AuraHandledException(ARCConstants.ERROR_NO_UPDATE_PERMISSION);
    }

    WizardFieldValidator.enforce(objectName, filtered);
    WizardFieldValidator.normalizeForStorage(objectName, filtered);

    SObject record = objectType.newSObject(recordId);
    applyFields(record, objectType.getDescribe().fields.getMap(), filtered);

    SObjectAccessDecision decision = Security.stripInaccessible(
      AccessType.UPDATABLE,
      new List<SObject>{ record }
    );

    try {
      update decision.getRecords();
    } catch (DmlException e) {
      throw new AuraHandledException(formatDmlMessage(e));
    }
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

  private static Map<String, Object> removePersonAccountName(
    Map<String, Object> fields,
    Boolean isPersonAccount
  ) {
    if (fields == null || fields.isEmpty() || isPersonAccount != true) {
      return fields;
    }

    Map<String, Object> filtered = new Map<String, Object>(fields);
    filtered.remove(ARCConstants.FIELD_NAME);
    return filtered;
  }

  private static void validateRecordId(Id recordId) {
    if (recordId == null) {
      throw new AuraHandledException(ARCConstants.ERROR_RECORD_ID_REQUIRED);
    }
  }

  private static String resolveObjectName(Id recordId, String objectNameOverride) {
    if (String.isNotBlank(objectNameOverride)) {
      return objectNameOverride;
    }

    Schema.SObjectType objectType = recordId.getSObjectType();
    if (objectType == null) {
      throw new AuraHandledException(ARCConstants.ERROR_RECORD_NOT_FOUND);
    }

    return objectType.getDescribe().getName();
  }

  private static DisplayRecordResolution resolveDisplayRecord(
    Id pageRecordId,
    String pageObjectName,
    Boolean useRelatedRecord,
    String relatedRecordLookupField
  ) {
    DisplayRecordResolution resolution = new DisplayRecordResolution();
    resolution.displayRecordId = pageRecordId;
    resolution.hidden = false;

    if (useRelatedRecord != true) {
      return resolution;
    }

    if (String.isBlank(relatedRecordLookupField)) {
      throw new AuraHandledException(ARCConstants.ERROR_RELATED_LOOKUP_FIELD_REQUIRED);
    }

    Id relatedRecordId = RecordQueryUtil.resolveRecordIdFromLookupField(
      pageRecordId,
      pageObjectName,
      relatedRecordLookupField.trim()
    );

    if (relatedRecordId == null) {
      resolution.hidden = true;
      resolution.displayRecordId = null;
      return resolution;
    }

    resolution.displayRecordId = relatedRecordId;
    return resolution;
  }

  private static RecordDetailContext buildHiddenContext(Id pageRecordId) {
    RecordDetailContext context = new RecordDetailContext();
    context.pageRecordId = pageRecordId;
    context.displayRecordId = null;
    context.hidden = true;
    context.objectApiName = null;
    context.schemaType = null;
    context.isPersonAccount = false;
    context.sections = new List<FieldDetailController.FormSection>();
    context.sectionLayout = new List<FieldDetailController.SectionGroup>();
    context.values = new Map<String, Object>();
    context.userContext = buildUserContext();
    context.isSubmitted = false;
    return context;
  }

  private static RecordResolution resolveRecordContext(
    Id recordId,
    String objectName
  ) {
    RecordResolution resolution = new RecordResolution();
    resolution.isPersonAccount = false;
    resolution.isSubmitted = false;

    if (objectName == ARCConstants.OBJECT_ACCOUNT) {
      Account account = queryAccountContext(recordId);
      if (account == null) {
        throw new AuraHandledException(ARCConstants.ERROR_RECORD_NOT_FOUND);
      }

      resolution.isSubmitted = account.Submitted__c == true;
      resolution.isPersonAccount = account.IsPersonAccount == true;

      String recordTypeName = account.RecordType?.DeveloperName;
      resolution.schemaType = resolveAccountSchemaType(recordTypeName);
      return resolution;
    }

    if (objectName == ARCConstants.OBJECT_SERVICE) {
      resolution.schemaType = ARCConstants.SCHEMA_ISA_SERVICE_AGREEMENT;
      resolution.isSubmitted = querySubmittedFlag(recordId, objectName);
      return resolution;
    }

    if (objectName == ARCConstants.OBJECT_FINANCIAL_ACCOUNT) {
      resolution.schemaType = resolveFinancialAccountSchemaType(recordId);
      resolution.isSubmitted = querySubmittedFlag(recordId, objectName);
      return resolution;
    }

    if (objectName == ARCConstants.OBJECT_CASE) {
      resolution.schemaType = resolveCaseSchemaType(recordId);
      resolution.isSubmitted = querySubmittedFlag(recordId, objectName);
      return resolution;
    }

    throw new AuraHandledException(
      ARCConstants.ERROR_SCHEMA_UNRESOLVED_FOR_OBJECT + objectName + ' records.'
    );
  }

  private static String resolveFinancialAccountSchemaType(Id recordId) {
    List<Financial_Account__c> rows = [
      SELECT DPI__c
      FROM Financial_Account__c
      WHERE Id = :recordId
      WITH USER_MODE
      LIMIT 1
    ];

    if (rows.isEmpty()) {
      throw new AuraHandledException(ARCConstants.ERROR_RECORD_NOT_FOUND);
    }

    return ARCConstants.FINANCIAL_ACCOUNT_DPI_TO_SCHEMA_TYPE.get(
      rows[0].DPI__c == true
    );
  }

  private static String resolveCaseSchemaType(Id recordId) {
    List<Case> rows = [
      SELECT Id
      FROM Case
      WHERE Id = :recordId
      WITH USER_MODE
      LIMIT 1
    ];

    if (rows.isEmpty()) {
      throw new AuraHandledException(ARCConstants.ERROR_RECORD_NOT_FOUND);
    }

    return ARCConstants.SCHEMA_STANDARD_CASE;
  }

  private static final Set<String> WHERE_STATEMENT_KEYWORDS = new Set<String>{
    'true',
    'false',
    'null',
    'and',
    'or',
    'not',
    'like'
  };

  /**
   * Load field values referenced in Shown/Required WHERE clauses (e.g. Case.Type,
   * Source_of_Funds_Value__c) that are not their own Envelope_Field__mdt rows and
   * therefore omitted from getRecordValuesForType.
   */
  private static void ensureVisibilityContextValues(
    Id recordId,
    String objectName,
    List<FieldDetailController.FormSection> sections,
    Map<String, Object> values
  ) {
    if (recordId == null || String.isBlank(objectName) || values == null) {
      return;
    }

    Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectName);
    if (objectType == null) {
      return;
    }

    Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();
    Set<String> referencedFields = collectWhereReferencedFieldApis(sections, fieldMap);
    Set<String> fieldsToQuery = new Set<String>();

    for (String fieldApi : referencedFields) {
      if (!values.containsKey(fieldApi)) {
        fieldsToQuery.add(fieldApi);
      }
    }

    if (fieldsToQuery.isEmpty()) {
      return;
    }

    String soql =
      'SELECT ' +
      String.join(new List<String>(fieldsToQuery), ', ') +
      ' FROM ' +
      String.escapeSingleQuotes(objectName) +
      ' WHERE Id = :recordId WITH USER_MODE LIMIT 1';

    SObject record = Database.query(soql);
    for (String fieldApi : fieldsToQuery) {
      Object value = record.get(fieldApi);
      Schema.DisplayType fieldType = fieldMap.get(fieldApi).getDescribe().getType();
      if (value != null || fieldType == Schema.DisplayType.BOOLEAN) {
        Object wireValue =
          fieldType == Schema.DisplayType.BOOLEAN && value == null
            ? false
            : formatFieldValueForWire(value, fieldType);
        values.put(fieldApi, wireValue);
      }
    }
  }

  /**
   * Serialize Date and Datetime values as ISO strings for the LWC layer. Applied in this controller
   * rather than FieldDetailController so interview-wide value loading stays unchanged.
   */
  @TestVisible
  private static Object formatFieldValueForWire(
    Object value,
    Schema.DisplayType fieldType
  ) {
    if (value == null) {
      return null;
    }

    if (fieldType == Schema.DisplayType.DATE) {
      return String.valueOf((Date) value);
    }

    if (fieldType == Schema.DisplayType.DATETIME) {
      return ((Datetime) value).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
    }

    return value;
  }

  private static void normalizeValuesForWire(
    Map<String, Object> values,
    List<FieldDetailController.FormSection> sections
  ) {
    if (values == null || values.isEmpty() || sections == null) {
      return;
    }

    for (FieldDetailController.FormSection section : sections) {
      if (section?.fields == null) {
        continue;
      }
      for (FieldDetailController.FieldMetadata field : section.fields) {
        String fieldPath = field?.fieldPath;
        if (String.isBlank(fieldPath) || !values.containsKey(fieldPath)) {
          continue;
        }

        Object value = values.get(fieldPath);
        if (value == null) {
          continue;
        }

        String fieldType = field.type;
        if (fieldType == 'DATE') {
          values.put(fieldPath, formatFieldValueForWire(value, Schema.DisplayType.DATE));
        } else if (fieldType == 'DATETIME') {
          values.put(fieldPath, formatFieldValueForWire(value, Schema.DisplayType.DATETIME));
        }
      }
    }
  }

  @TestVisible
  private static Set<String> collectWhereReferencedFieldApis(
    List<FieldDetailController.FormSection> sections,
    Map<String, Schema.SObjectField> fieldMap
  ) {
    Set<String> fieldApis = new Set<String>();
    if (sections == null) {
      return fieldApis;
    }

    for (FieldDetailController.FormSection section : sections) {
      if (section?.fields == null) {
        continue;
      }
      for (FieldDetailController.FieldMetadata field : section.fields) {
        addWhereReferencedFields(fieldApis, field.shownWhereStatement, fieldMap);
        addWhereReferencedFields(fieldApis, field.requiredWhereStatement, fieldMap);
      }
    }
    return fieldApis;
  }

  private static void addWhereReferencedFields(
    Set<String> fieldApis,
    String whereStatement,
    Map<String, Schema.SObjectField> fieldMap
  ) {
    if (String.isBlank(whereStatement)) {
      return;
    }

    Matcher matcher = Pattern.compile(
      '(?i)(?:^|[\\s(])(?:NOT\\s+)?(?:\\$User\\.)?([A-Za-z][A-Za-z0-9_]*)\\s*(?:=|!=|LIKE)'
    ).matcher(whereStatement);

    while (matcher.find()) {
      String token = matcher.group(1);
      if (WHERE_STATEMENT_KEYWORDS.contains(token.toLowerCase())) {
        continue;
      }
      if (fieldMap.containsKey(token)) {
        fieldApis.add(token);
      }
    }
  }

  private static Account queryAccountContext(Id recordId) {
    List<Account> rows = [
      SELECT
        Id,
        Submitted__c,
        IsPersonAccount,
        RecordType.DeveloperName
      FROM Account
      WHERE Id = :recordId
      WITH USER_MODE
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0];
  }

  @TestVisible
  private static String resolveAccountSchemaType(String recordTypeDeveloperName) {
    if (String.isBlank(recordTypeDeveloperName)) {
      throw new AuraHandledException(ARCConstants.ERROR_ACCOUNT_SCHEMA_UNRESOLVED);
    }

    String schemaType = ARCConstants.RECORD_TYPE_TO_SCHEMA_TYPE.get(
      recordTypeDeveloperName
    );
    if (String.isBlank(schemaType)) {
      throw new AuraHandledException(ARCConstants.ERROR_ACCOUNT_SCHEMA_UNRESOLVED);
    }

    return schemaType;
  }

  private static UserContext buildUserContext() {
    UserContext ctx = new UserContext();
    try {
      User runningUser = [
        SELECT Relationship_to_firm__c
        FROM User
        WHERE Id = :UserInfo.getUserId()
        LIMIT 1
      ];
      ctx.relationshipToFirm = runningUser.Relationship_to_firm__c;
    } catch (Exception e) {
      ctx.relationshipToFirm = null;
    }
    return ctx;
  }

  private static Boolean querySubmittedFlag(Id recordId, String objectName) {
    Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectName);
    if (objectType == null) {
      return false;
    }

    Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();
    if (!fieldMap.containsKey(ARCConstants.FIELD_SUBMITTED)) {
      return false;
    }

    String soql =
      'SELECT ' +
      ARCConstants.FIELD_SUBMITTED +
      ' FROM ' +
      String.escapeSingleQuotes(objectName) +
      ' WHERE Id = :recordId WITH USER_MODE LIMIT 1';
    List<SObject> rows = Database.query(soql);
    if (rows.isEmpty()) {
      return false;
    }

    return rows[0].get(ARCConstants.FIELD_SUBMITTED) == true;
  }

  private static Set<String> personAccountOnlyFieldCache;

  private static Set<String> getPersonAccountOnlyFields() {
    if (personAccountOnlyFieldCache != null) {
      return personAccountOnlyFieldCache;
    }

    Set<String> fields = new Set<String>(ARCConstants.PERSON_ACCOUNT_BASE_FIELDS);

    for (String apiName : Account.SObjectType.getDescribe().fields.getMap().keySet()) {
      if (apiName.startsWith(ARCConstants.PERSON_FIELD_PREFIX)) {
        fields.add(apiName);
      }
    }

    personAccountOnlyFieldCache = fields;
    return personAccountOnlyFieldCache;
  }

  private static Set<String> collectAllowedFieldPaths(
    Id recordId,
    String objectName,
    String schemaType
  ) {
    Set<String> allowed = new Set<String>();
    for (FieldDetailController.FormSection section :
      FieldDetailController.getFormSchema(objectName, schemaType)) {
      for (FieldDetailController.FieldMetadata field : section.fields) {
        if (field.addRecord == true || String.isBlank(field.fieldPath)) {
          continue;
        }
        String targetObject = String.isNotBlank(field.objectApiName)
          ? field.objectApiName
          : objectName;
        allowed.add(field.fieldPath);
      }
    }

    return removePersonAccountOnlyFields(recordId, objectName, allowed);
  }

  private static Boolean hasRelatedObjectFields(
    String objectName,
    String schemaType,
    List<FieldDetailController.FormSection> sections
  ) {
    List<FieldDetailController.FormSection> sectionSource = sections != null
      ? sections
      : FieldDetailController.getFormSchema(objectName, schemaType);

    return !RecordQueryUtil.collectRelatedObjectApiNames(sectionSource, objectName)
      .isEmpty();
  }

  private static Boolean hasRelatedObjectFields(
    String objectName,
    String schemaType
  ) {
    return hasRelatedObjectFields(objectName, schemaType, null);
  }

  private static Map<String, String> buildFieldPathToObjectMap(
    String objectName,
    String schemaType
  ) {
    Map<String, String> fieldPathToObject = new Map<String, String>();
    for (FieldDetailController.FormSection section :
      FieldDetailController.getFormSchema(objectName, schemaType)) {
      for (FieldDetailController.FieldMetadata field : section.fields) {
        if (field.addRecord == true || String.isBlank(field.fieldPath)) {
          continue;
        }
        String targetObject = String.isNotBlank(field.objectApiName)
          ? field.objectApiName
          : objectName;
        fieldPathToObject.put(field.fieldPath, targetObject);
      }
    }
    return fieldPathToObject;
  }

  private static Map<String, Map<String, Object>> groupFieldsByTargetObject(
    Map<String, Object> fields,
    String objectName,
    String schemaType
  ) {
    Map<String, Map<String, Object>> grouped = new Map<String, Map<String, Object>>();
    Map<String, String> fieldPathToObject = buildFieldPathToObjectMap(
      objectName,
      schemaType
    );

    for (String fieldPath : fields.keySet()) {
      String targetObject = fieldPathToObject.get(fieldPath);
      if (String.isBlank(targetObject)) {
        continue;
      }
      if (!grouped.containsKey(targetObject)) {
        grouped.put(targetObject, new Map<String, Object>());
      }
      grouped.get(targetObject).put(fieldPath, fields.get(fieldPath));
    }

    return grouped;
  }

  private static void savePrimaryWithRelatedRecords(
    Id primaryRecordId,
    String primaryObjectApiName,
    String schemaType,
    Map<String, Object> filtered,
    List<FieldDetailController.FormSection> sections
  ) {
    Map<String, Map<String, Object>> grouped = groupFieldsByTargetObject(
      filtered,
      primaryObjectApiName,
      schemaType
    );
    if (grouped.isEmpty()) {
      throw new AuraHandledException(ARCConstants.ERROR_NO_EDITABLE_FIELDS);
    }

    Set<String> relatedObjects = RecordQueryUtil.collectRelatedObjectApiNames(
      sections,
      primaryObjectApiName
    );
    Map<String, Id> relatedIds = RecordQueryUtil.resolveRelatedRecordIdsFromPrimary(
      primaryRecordId,
      primaryObjectApiName,
      relatedObjects
    );

    if (
      grouped.containsKey(primaryObjectApiName) &&
      !grouped.get(primaryObjectApiName).isEmpty()
    ) {
      saveGenericRecord(
        primaryRecordId,
        primaryObjectApiName,
        grouped.get(primaryObjectApiName)
      );
    }

    for (String targetObject : grouped.keySet()) {
      if (targetObject == primaryObjectApiName) {
        continue;
      }

      Map<String, Object> objectFields = grouped.get(targetObject);
      if (objectFields == null || objectFields.isEmpty()) {
        continue;
      }

      Id relatedId = relatedIds.get(targetObject);
      if (relatedId == null) {
        throw new AuraHandledException(
          ARCUtil.formatNoRelatedRecordLinkedMessage(
            targetObject,
            primaryObjectApiName
          )
        );
      }

      saveGenericRecord(relatedId, targetObject, objectFields);
    }
  }

  private static Map<String, Object> filterFieldsForRecord(
    Id recordId,
    String objectName,
    Map<String, Object> fields
  ) {
    if (fields == null || fields.isEmpty()) {
      return fields;
    }

    Set<String> removable = personAccountOnlyFieldsToRemove(recordId, objectName);
    if (removable.isEmpty()) {
      return fields;
    }

    Map<String, Object> filtered = new Map<String, Object>(fields);
    for (String apiName : removable) {
      filtered.remove(apiName);
    }
    return filtered;
  }

  private static Set<String> removePersonAccountOnlyFields(
    Id recordId,
    String objectName,
    Set<String> fieldPaths
  ) {
    Set<String> removable = personAccountOnlyFieldsToRemove(recordId, objectName);
    if (removable.isEmpty()) {
      return fieldPaths;
    }

    Set<String> allowed = new Set<String>(fieldPaths);
    allowed.removeAll(removable);
    return allowed;
  }

  private static Set<String> personAccountOnlyFieldsToRemove(
    Id recordId,
    String objectName
  ) {
    if (recordId == null || objectName != ARCConstants.OBJECT_ACCOUNT) {
      return new Set<String>();
    }

    Account account = new FscRelAccountRepository().selectById(recordId);
    if (account == null || FscRelAccountRepository.isPersonAccountRecord(account)) {
      return new Set<String>();
    }

    return getPersonAccountOnlyFields().clone();
  }

  private static void applyFields(
    SObject record,
    Map<String, Schema.SObjectField> fieldMap,
    Map<String, Object> values
  ) {
    List<String> failedKeys = new List<String>();
    for (String key : values.keySet()) {
      Schema.SObjectField fieldToken = fieldMap.get(key);
      if (fieldToken == null) {
        failedKeys.add(key);
        continue;
      }
      try {
        record.put(key, coerceForField(fieldToken, values.get(key)));
      } catch (Exception e) {
        failedKeys.add(key);
      }
    }
    if (!failedKeys.isEmpty()) {
      throw new AuraHandledException(
        ARCConstants.ERROR_FIELDS_NOT_SAVED_PREFIX + String.join(failedKeys, ', ')
      );
    }
  }

  private static Object coerceForField(Schema.SObjectField field, Object value) {
    if (field == null || value == null) {
      return value;
    }

    Schema.DisplayType fieldType = field.getDescribe().getType();

    if (fieldType == Schema.DisplayType.MULTIPICKLIST && value instanceof List<Object>) {
      List<String> parts = new List<String>();
      for (Object item : (List<Object>) value) {
        if (item != null) {
          parts.add(String.valueOf(item));
        }
      }
      return String.join(parts, ';');
    }

    if (!(value instanceof String)) {
      return value;
    }

    String text = (String) value;
    if (String.isBlank(text)) {
      return null;
    }

    switch on fieldType {
      when BOOLEAN {
        return Boolean.valueOf(text);
      }
      when DATE {
        return Date.valueOf(text);
      }
      when DATETIME {
        return Datetime.valueOfGmt(text.replace('T', ' ').replace('Z', ''));
      }
      when DOUBLE, CURRENCY, PERCENT {
        return Decimal.valueOf(text);
      }
      when INTEGER {
        return Integer.valueOf(text);
      }
      when else {
        return value;
      }
    }
  }

  private static String formatDmlMessage(DmlException error) {
    if (error == null) {
      return ARCConstants.ERROR_GENERIC_SAVE;
    }
    if (error.getNumDml() > 0) {
      return error.getDmlMessage(0);
    }
    return error.getMessage();
  }

  private class RecordResolution {
    public String schemaType;
    public Boolean isPersonAccount;
    public Boolean isSubmitted;
  }

  private class DisplayRecordResolution {
    public Id displayRecordId;
    public Boolean hidden;
  }

  public class RecordDetailContext {
    @AuraEnabled
    public Id pageRecordId;

    @AuraEnabled
    public Id displayRecordId;

    @AuraEnabled
    public Boolean hidden;

    @AuraEnabled
    public String objectApiName;

    @AuraEnabled
    public String schemaType;

    @AuraEnabled
    public Boolean isPersonAccount;

    @AuraEnabled
    public List<FieldDetailController.FormSection> sections;

    @AuraEnabled
    public List<FieldDetailController.SectionGroup> sectionLayout;

    @AuraEnabled
    public Map<String, Object> values;

    @AuraEnabled
    public UserContext userContext;

    @AuraEnabled
    public Boolean isSubmitted;
  }

  public class UserContext {
    @AuraEnabled
    public String relationshipToFirm;
  }
}