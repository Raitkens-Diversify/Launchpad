/**
 * Author: Hoang Long Vu To
 *
 * Loads and saves metadata-driven record detail forms (Envelope_Field__mdt schema)
 * for Experience Cloud record pages.
 */
public with sharing class ArcRecordDetailController {
  private static final String DEFAULT_ACCOUNT_SCHEMA_TYPE = 'Client - Individual';
  // Households carry no Envelope_Field__mdt schema of their own, and neither do
  // any other unmapped business record types. They borrow the business schema
  // rather than the individual one, whose fields a business account cannot hold.
  private static final String DEFAULT_BUSINESS_ACCOUNT_SCHEMA_TYPE = 'Client - Business';

  // Mirrors envelopeFormSchema.js MDT_TYPE_TO_RECORD_TYPES / WizardEnvelopeStateService.addMemberByRecordType.
  private static final Map<String, String> RECORD_TYPE_TO_SCHEMA_TYPE = new Map<String, String>{
    'PersonAccount' => 'Client - Individual',
    'Individual' => 'Client - Individual',
    'Business' => 'Client - Business',
    'IndustriesBusiness' => 'Client - Business',
    'Trust' => 'Client - Trust',
    'IndustriesInstitution' => 'Client - Trust',
    'Retirement_Plan' => 'Client - Retirement Plan'
  };

  // Objects whose detail page has exactly one Envelope_Field__mdt schema, so
  // there is nothing on the record to branch on.
  @TestVisible
  private static final Map<String, String> SINGLE_SCHEMA_OBJECTS = new Map<String, String>{
    'Task' => 'Task',
    'Check_Log__c' => 'Check Log',
    'Check_Deposit__c' => 'Check Deposit',
    'Advertising_Item__c' => 'Standard Advertising Item'
  };

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
   * Opens a home-office envelope for a record whose regulated fields the user
   * wants to change, and returns its id so the caller can navigate to the
   * wizard.
   *
   * Regulation is a household-level conversation, so the envelope is always
   * raised against the household even when the user started from one of its
   * members.
   *
   * It does not pre-select the member. Which members an envelope covers lives
   * in the wizard's own state blob, not in Envelope_Content__c, so seeding it
   * from here would mean writing that blob behind the wizard's back — and an
   * Envelope_Content__c row on its own is invisible to the outline. The user
   * picks the member with Add member, one click into the envelope.
   *
   * Conventions:
   * - Account only. Nothing else on the site declares regulated fields, and
   *   inventing an envelope for a record the wizard cannot open would be worse
   *   than saying so.
   * - Reuses EnvelopeLandingApex.createWizEnvelopeV2 — the same call the create
   *   dialog makes — rather than inserting an Envelope__c here, so an envelope
   *   started this way is identical to one started from the wizard. (Not the v1
   *   createWizEnvelope, which sets neither Status__c nor Household__c and so
   *   produces an envelope getWizEnvelopes filters straight back out.)
   */
  @AuraEnabled
  public static Id startRegulatedFieldsEnvelope(Id recordId) {
    validateRecordId(recordId);

    String objectName = resolveObjectName(recordId, null);
    if (objectName != 'Account') {
      throw new AuraHandledException(
        'Envelopes can only be started from a contact or household.'
      );
    }

    if (!Schema.sObjectType.Envelope__c.isCreateable()) {
      throw new AuraHandledException(
        'You do not have permission to create envelopes.'
      );
    }

    List<Account> rows = [
      SELECT Id, Name, Household__c, Household__r.Name
      FROM Account
      WHERE Id = :recordId
      WITH USER_MODE
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      throw new AuraHandledException('Record not found.');
    }

    Account record = rows[0];
    // A household edits itself; a member edits through its household.
    Id householdId = record.Household__c != null
      ? record.Household__c
      : record.Id;
    String householdName = record.Household__c != null
      ? record.Household__r.Name
      : record.Name;

    EnvelopeLandingApex.EnvelopeCreateResult created = EnvelopeLandingApex.createWizEnvelopeV2(
      Date.today().format() + ' - ' + householdName,
      'existing',
      householdId,
      null,
      null
    );

    return created.id;
  }

  @AuraEnabled
  public static RecordDetailContext load(
    Id recordId,
    String objectName,
    String schemaType,
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
      resolvedObjectName,
      schemaType
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

    Map<String, List<FieldDetailController.SectionGroup>> layouts = FieldDetailController.getSectionLayouts();
    context.sectionLayout = layouts.containsKey(resolvedSchemaType)
      ? layouts.get(resolvedSchemaType)
      : new List<FieldDetailController.SectionGroup>();

    Map<Id, Map<String, Object>> valuesById = FieldDetailController.getRecordValuesForType(
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

    context.referenceLabels = resolveReferenceLabels(
      context.sections,
      context.values
    );
    context.userContext = buildUserContext();
    context.isSubmitted = resolution.isSubmitted;
    return context;
  }

  /**
   * Display names for the lookup fields on the form, keyed by field path.
   *
   * A lookup's stored value is an 18-character id, which is all the read-only
   * row had to show. The picker resolves the name but only as a form control,
   * so read mode was a row of greyed-out search boxes among plain text.
   *
   * Ids are grouped by their own SObject type and each type is queried once,
   * so this stays a small fixed number of queries however many lookups a form
   * has. Everything nameable answers to Name; the two that do not are mapped.
   */
  private static final Map<String, String> NAME_FIELD_BY_OBJECT = new Map<String, String>{
    'Case' => 'CaseNumber',
    'Task' => 'Subject'
  };

  private static Map<String, String> resolveReferenceLabels(
    List<FieldDetailController.FormSection> sections,
    Map<String, Object> values
  ) {
    Map<String, String> labels = new Map<String, String>();
    if (sections == null || values == null || values.isEmpty()) {
      return labels;
    }

    // fieldPath -> the id it holds, for reference fields that hold one.
    Map<String, Id> idByFieldPath = new Map<String, Id>();
    Map<String, Set<Id>> idsByObject = new Map<String, Set<Id>>();

    for (FieldDetailController.FormSection section : sections) {
      for (FieldDetailController.FieldMetadata field : section.fields) {
        if (
          field.type != 'REFERENCE' ||
          String.isBlank(field.fieldPath) ||
          !values.containsKey(field.fieldPath)
        ) {
          continue;
        }

        Id value = toId(values.get(field.fieldPath));
        if (value == null) {
          continue;
        }

        String objectName = value.getSObjectType().getDescribe().getName();
        idByFieldPath.put(field.fieldPath, value);
        if (!idsByObject.containsKey(objectName)) {
          idsByObject.put(objectName, new Set<Id>());
        }
        idsByObject.get(objectName).add(value);
      }
    }

    if (idByFieldPath.isEmpty()) {
      return labels;
    }

    Map<Id, String> nameById = new Map<Id, String>();
    for (String objectName : idsByObject.keySet()) {
      // The FinServ financial account is invisible to portal users (no
      // object permission, Private external sharing), so the USER_MODE
      // query below finds nothing and the form shows a blank where
      // Lightning shows the account's name. Its display name is resolved
      // through the narrowly-scoped system-mode resolver instead — the id
      // was read off a record the user already accessed under USER_MODE.
      if (objectName == 'FinServ__FinancialAccount__c') {
        Map<Id, ArcFinServAccountLabels.Entry> finServLabels = ArcFinServAccountLabels.resolve(
          idsByObject.get(objectName)
        );
        for (Id accountId : finServLabels.keySet()) {
          nameById.put(accountId, finServLabels.get(accountId).name);
        }
        continue;
      }

      String nameField = NAME_FIELD_BY_OBJECT.containsKey(objectName)
        ? NAME_FIELD_BY_OBJECT.get(objectName)
        : 'Name';

      Schema.SObjectType objectType = Schema.getGlobalDescribe()
        .get(objectName);
      if (
        objectType == null ||
        !objectType.getDescribe().fields.getMap().containsKey(nameField)
      ) {
        continue;
      }

      Set<Id> ids = idsByObject.get(objectName);
      // Both halves are describe-derived, never caller input, so there is
      // nothing here for a caller to inject through.
      String soql =
        'SELECT Id, ' +
        nameField +
        ' FROM ' +
        objectName +
        ' WHERE Id IN :ids WITH USER_MODE';
      try {
        for (SObject row : Database.query(soql)) {
          Object name = row.get(nameField);
          if (name != null) {
            nameById.put((Id) row.get('Id'), String.valueOf(name));
          }
        }
      } catch (Exception e) {
        // A type the reader cannot see leaves its rows showing the id, which
        // is no worse than before and better than failing the whole load.
        continue;
      }
    }

    for (String fieldPath : idByFieldPath.keySet()) {
      String name = nameById.get(idByFieldPath.get(fieldPath));
      if (String.isNotBlank(name)) {
        labels.put(fieldPath, name);
      }
    }

    return labels;
  }

  private static Id toId(Object value) {
    if (value == null) {
      return null;
    }
    try {
      return Id.valueOf(String.valueOf(value));
    } catch (Exception e) {
      return null;
    }
  }

  @AuraEnabled
  public static void save(
    Id recordId,
    String objectName,
    String schemaType,
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
      throw new AuraHandledException('Record not found.');
    }

    recordId = displayResolution.displayRecordId;
    String resolvedObjectName = resolveObjectName(recordId, null);
    RecordResolution resolution = resolveRecordContext(
      recordId,
      resolvedObjectName,
      schemaType
    );
    String resolvedSchemaType = resolution.schemaType;

    if (resolution.isSubmitted) {
      throw new AuraHandledException(
        'This record has been submitted and can no longer be edited.'
      );
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
      throw new AuraHandledException(
        'There are no editable fields to update in this section.'
      );
    }

    // Accounts update through the same generic path as every other object.
    //
    // They used to route through EnvelopeHouseholdMemberController.saveEntity,
    // which is the envelope wizard's member-save routine and therefore forces
    // RecordTypeId from the schema type on every write. That is right when the
    // wizard is creating a member; it is wrong when someone edits a section of
    // a record that already has a type. On a Household account it resolved to
    // the person-account type and tried to convert the record, which Salesforce
    // refuses: "Cannot specify any additional fields when marrying or
    // separating a Person-Account". The DML error was the only thing stopping
    // a Household being turned into a Person Account by editing its email.
    //
    // Editing a section must never change a record's type, so nothing here
    // sends one. Create still goes through saveEntity, where the record type is
    // genuinely the caller's to set.
    if (resolvedObjectName != 'Account' && hasRelatedObjectFields(
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

  private static void saveGenericRecord(
    Id recordId,
    String objectName,
    Map<String, Object> filtered
  ) {
    Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectName);
    if (objectType == null) {
      throw new AuraHandledException('Object not found: ' + objectName);
    }

    if (!objectType.getDescribe().isUpdateable()) {
      throw new AuraHandledException(
        'You do not have permission to update this record.'
      );
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
    filtered.remove('Name');
    return filtered;
  }

  private static final Map<String, String> CASE_TYPE_TO_SCHEMA_TYPE = new Map<String, String>{
    'Account Closure' => 'Account Closure',
    'Update DMS Instructions' => 'Manage DMS Instructions',
    'Change Management Style' => 'Change Management Style',
    'Additional Funding' => 'Additional Funding',
    'Edit Individual' => 'Client - Individual',
    'Edit Business' => 'Client - Business',
    'Edit Trust' => 'Client - Trust',
    'Edit Retirement Plan' => 'Client - Retirement Plan'
  };

  private static void validateRecordId(Id recordId) {
    if (recordId == null) {
      throw new AuraHandledException('Record Id is required');
    }
  }

  private static String resolveObjectName(
    Id recordId,
    String objectNameOverride
  ) {
    if (String.isNotBlank(objectNameOverride)) {
      return objectNameOverride;
    }

    Schema.SObjectType objectType = recordId.getSObjectType();
    if (objectType == null) {
      throw new AuraHandledException('Record not found.');
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
      throw new AuraHandledException(
        ARCConstants.ERROR_RELATED_LOOKUP_FIELD_REQUIRED
      );
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
    context.referenceLabels = new Map<String, String>();
    context.userContext = buildUserContext();
    context.isSubmitted = false;
    return context;
  }

  private static RecordResolution resolveRecordContext(
    Id recordId,
    String objectName,
    String schemaTypeOverride
  ) {
    RecordResolution resolution = new RecordResolution();
    resolution.isPersonAccount = false;
    resolution.isSubmitted = false;

    if (objectName == 'Account') {
      Account account = queryAccountContext(recordId);
      if (account == null) {
        throw new AuraHandledException('Record not found.');
      }

      resolution.isSubmitted = account.Submitted__c == true;
      resolution.isPersonAccount = account.IsPersonAccount == true;

      String recordTypeName = account.RecordType?.DeveloperName;
      resolution.schemaType = resolveAccountSchemaType(
        recordTypeName,
        resolution.isPersonAccount
      );
      return resolution;
    }

    if (objectName == 'Service__c') {
      resolution.schemaType = 'ISA - Service Agreement';
      resolution.isSubmitted = querySubmittedFlag(recordId, objectName);
      return resolution;
    }

    if (objectName == 'Financial_Account__c') {
      resolution.schemaType = resolveFinancialAccountSchemaType(recordId);
      resolution.isSubmitted = querySubmittedFlag(recordId, objectName);
      return resolution;
    }

    if (objectName == 'Case') {
      resolution.schemaType = resolveCaseSchemaType(recordId);
      resolution.isSubmitted = querySubmittedFlag(recordId, objectName);
      return resolution;
    }

    // One schema per object, no record-type branch: these pages have a single
    // form each. Named here rather than left to the caller so the page keeps
    // working from a bare record link with no schemaType on the URL.
    // Advertising_Item__c (the Case Detail page's related-record section for
    // Advertising Review cases) belongs here too.
    if (SINGLE_SCHEMA_OBJECTS.containsKey(objectName)) {
      resolution.schemaType = SINGLE_SCHEMA_OBJECTS.get(objectName);
      resolution.isSubmitted = querySubmittedFlag(recordId, objectName);
      return resolution;
    }

    if (String.isBlank(schemaTypeOverride)) {
      throw new AuraHandledException(
        'Schema type could not be resolved for ' + objectName + ' records.'
      );
    }

    resolution.schemaType = schemaTypeOverride;
    resolution.isSubmitted = querySubmittedFlag(recordId, objectName);
    return resolution;
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
      throw new AuraHandledException('Record not found.');
    }

    // The record page used to borrow the wizard's form schemas
    // ('ISA - DPI' / 'ISA - Fin Acct'), which carry form phrasing like
    // "If you already have the account number, please enter it here" and
    // only the handful of fields the wizard asks about. 'Financial Account'
    // is the record-detail schema, mirroring the Lightning record page's
    // Information section. The wizard itself never resolves through here —
    // its schemas live client-side in envelopeFormSchema.js.
    return 'Financial Account';
  }

  private static String resolveCaseSchemaType(Id recordId) {
    List<Case> rows = [
      SELECT Type
      FROM Case
      WHERE Id = :recordId
      WITH USER_MODE
      LIMIT 1
    ];

    if (rows.isEmpty()) {
      throw new AuraHandledException('Record not found.');
    }

    String caseType = rows[0].Type;
    if (
      String.isBlank(caseType) ||
      !CASE_TYPE_TO_SCHEMA_TYPE.containsKey(caseType)
    ) {
      throw new AuraHandledException(
        'Schema type could not be resolved for this case type.'
      );
    }

    return CASE_TYPE_TO_SCHEMA_TYPE.get(caseType);
  }

  private static Account queryAccountContext(Id recordId) {
    List<Account> rows = [
      SELECT Id, Submitted__c, IsPersonAccount, RecordType.DeveloperName
      FROM Account
      WHERE Id = :recordId
      WITH USER_MODE
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0];
  }

  /**
   * The schema a record type's form is built from.
   *
   * The fallback has to know whether the account is a person, because the two
   * defaults are not interchangeable: Client - Individual is built entirely on
   * person-account fields (FirstName, PersonEmail, PersonMobilePhone), which do
   * not exist on a business account. Handing that schema to a business account
   * renders a form of fields it cannot store — which is what every Household
   * account got, Household having no schema of its own.
   */
  @TestVisible
  private static String resolveAccountSchemaType(
    String recordTypeDeveloperName,
    Boolean isPersonAccount
  ) {
    Boolean isPerson = isPersonAccount == true;
    String fallback = isPerson
      ? DEFAULT_ACCOUNT_SCHEMA_TYPE
      : DEFAULT_BUSINESS_ACCOUNT_SCHEMA_TYPE;

    if (String.isBlank(recordTypeDeveloperName)) {
      return fallback;
    }

    String schemaType = RECORD_TYPE_TO_SCHEMA_TYPE.get(recordTypeDeveloperName);
    if (String.isBlank(schemaType)) {
      return fallback;
    }

    // A mapping that disagrees with the record itself loses to the record: the
    // fields a person account can store are decided by the data, not the map.
    if (!isPerson && schemaType == DEFAULT_ACCOUNT_SCHEMA_TYPE) {
      return DEFAULT_BUSINESS_ACCOUNT_SCHEMA_TYPE;
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

    Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe()
      .fields.getMap();
    if (!fieldMap.containsKey('Submitted__c')) {
      return false;
    }

    String soql =
      'SELECT Submitted__c FROM ' +
      String.escapeSingleQuotes(objectName) +
      ' WHERE Id = :recordId WITH USER_MODE LIMIT 1';
    List<SObject> rows = Database.query(soql);
    if (rows.isEmpty()) {
      return false;
    }

    return rows[0].get('Submitted__c') == true;
  }

  private static Set<String> personAccountOnlyFieldCache;

  private static Set<String> getPersonAccountOnlyFields() {
    if (personAccountOnlyFieldCache != null) {
      return personAccountOnlyFieldCache;
    }

    Set<String> fields = new Set<String>{
      'FirstName',
      'LastName',
      'Salutation',
      'MiddleName',
      'Suffix'
    };

    for (
      String apiName : Account.SObjectType.getDescribe()
        .fields.getMap()
        .keySet()
    ) {
      if (apiName.startsWith('Person')) {
        fields.add(apiName);
      }
    }

    personAccountOnlyFieldCache = fields;
    return personAccountOnlyFieldCache;
  }

  /**
   * The writable field paths a schema declares, without the record-specific
   * pruning collectAllowedFieldPaths does. Create has no record to describe, so
   * the person-account-only trim happens against the schema type instead.
   */
  private static Set<String> collectSchemaFields(
    String objectName,
    String schemaType
  ) {
    Set<String> allowed = new Set<String>();
    for (
      FieldDetailController.FormSection section : FieldDetailController.getFormSchema(
        objectName,
        schemaType
      )
    ) {
      for (FieldDetailController.FieldMetadata field : section.fields) {
        if (field.addRecord == true || String.isBlank(field.fieldPath)) {
          continue;
        }
        String targetObject = String.isNotBlank(field.objectApiName)
          ? field.objectApiName
          : objectName;
        if (targetObject == objectName) {
          allowed.add(field.fieldPath);
        }
      }
    }
    return allowed;
  }

  private static Set<String> collectAllowedFieldPaths(
    Id recordId,
    String objectName,
    String schemaType
  ) {
    Set<String> allowed = new Set<String>();
    for (
      FieldDetailController.FormSection section : FieldDetailController.getFormSchema(
        objectName,
        schemaType
      )
    ) {
      for (FieldDetailController.FieldMetadata field : section.fields) {
        if (field.addRecord == true || String.isBlank(field.fieldPath)) {
          continue;
        }
        String targetObject = String.isNotBlank(field.objectApiName)
          ? field.objectApiName
          : objectName;
        if (targetObject == objectName) {
          allowed.add(field.fieldPath);
        }
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
    if (recordId == null || objectName != 'Account') {
      return new Set<String>();
    }

    Account account = new FscRelAccountRepository().selectById(recordId);
    if (
      account == null || FscRelAccountRepository.isPersonAccountRecord(account)
    ) {
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
        'These fields could not be saved: ' + String.join(failedKeys, ', ')
      );
    }
  }

  private static Object coerceForField(
    Schema.SObjectField field,
    Object value
  ) {
    if (field == null || value == null) {
      return value;
    }

    Schema.DisplayType fieldType = field.getDescribe().getType();

    if (
      fieldType == Schema.DisplayType.MULTIPICKLIST &&
      value instanceof List<Object>
    ) {
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
      return 'Something went wrong while saving your changes. Please try again.';
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

    /** Lookup field path -> the referenced record's display name. */
    @AuraEnabled
    public Map<String, String> referenceLabels;

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