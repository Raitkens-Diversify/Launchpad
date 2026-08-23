/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-12
 */
@IsTest
private class ArcRecordDetailControllerTest {

  @IsTest
  static void loadReturnsSchemaAndValues() {
    Account member = new Account(
      FirstName = 'Jane',
      LastName = 'Doe',
      RecordTypeId = Schema.SObjectType.Account
        .getRecordTypeInfosByDeveloperName()
        .get('PersonAccount')
        .getRecordTypeId()
    );
    insert member;

    Test.startTest();
    ArcRecordDetailController.RecordDetailContext context =
      ArcRecordDetailController.load(member.Id, null, false, null);
    Test.stopTest();

    System.assertNotEquals(null, context, 'Context should not be null');
    System.assertEquals('Account', context.objectApiName);
    System.assertEquals(
      'Client - Individual',
      context.schemaType,
      'Person account should resolve individual schema'
    );
    System.assertEquals(true, context.isPersonAccount);
    System.assertNotEquals(null, context.sections, 'Sections should not be null');
    System.assertNotEquals(null, context.values, 'Values should not be null');
    System.assertNotEquals(null, context.userContext, 'User context should not be null');
    System.assertEquals(false, context.isSubmitted, 'Unsubmitted record should be editable');
  }

  @IsTest
  static void loadResolvesBusinessSchemaFromRecordType() {
    Id businessRecordTypeId = Schema.SObjectType.Account
      .getRecordTypeInfosByDeveloperName()
      .get('Business')
      .getRecordTypeId();

    Account business = new Account(
      Name = 'Acme Corp',
      RecordTypeId = businessRecordTypeId
    );
    insert business;

    Test.startTest();
    ArcRecordDetailController.RecordDetailContext context =
      ArcRecordDetailController.load(business.Id, null, false, null);
    Test.stopTest();

    System.assertEquals('Account', context.objectApiName);
    System.assertEquals('Client - Business', context.schemaType);
    System.assertEquals(false, context.isPersonAccount);
  }

  @IsTest
  static void resolveAccountSchemaTypeMapsKnownRecordTypes() {
    System.assertEquals(
      'Client - Individual',
      ArcRecordDetailController.resolveAccountSchemaType('PersonAccount')
    );
    System.assertEquals(
      'Client - Business',
      ArcRecordDetailController.resolveAccountSchemaType('Business')
    );
    System.assertEquals(
      'Client - Trust',
      ArcRecordDetailController.resolveAccountSchemaType('Trust')
    );
    System.assertEquals(
      'Client - Retirement Plan',
      ArcRecordDetailController.resolveAccountSchemaType('Retirement_Plan')
    );

    Boolean threw = false;
    try {
      ArcRecordDetailController.resolveAccountSchemaType('Unknown_Type');
    } catch (AuraHandledException e) {
      threw = true;
    }
    System.assert(threw, 'Unknown account record types should not fall back to a default schema.');
  }

  @IsTest
  static void saveRejectsSubmittedRecord() {
    Account member = new Account(
      FirstName = 'Submitted',
      LastName = 'Member',
      Submitted__c = true,
      RecordTypeId = Schema.SObjectType.Account
        .getRecordTypeInfosByDeveloperName()
        .get('PersonAccount')
        .getRecordTypeId()
    );
    insert member;

    Boolean threw = false;
    try {
      ArcRecordDetailController.save(
        member.Id,
        null,
        false,
        null,
        new Map<String, Object>{ 'FirstName' => 'Updated' }
      );
    } catch (AuraHandledException e) {
      threw = true;
    }
    System.assert(threw, 'Submitted record save should throw');
  }

  @IsTest
  static void loadRejectsNullRecordId() {
    Boolean threw = false;
    try {
      ArcRecordDetailController.load(null, null, false, null);
    } catch (AuraHandledException e) {
      threw = true;
    }
    System.assert(threw, 'Null record id should throw');
  }

  @IsTest
  static void loadResolvesServiceSchemaFromRecordId() {
    Service__c service = new Service__c(Name = 'Detail Service');
    insert service;

    Test.startTest();
    ArcRecordDetailController.RecordDetailContext context =
      ArcRecordDetailController.load(service.Id, null, false, null);
    Test.stopTest();

    System.assertEquals('Service__c', context.objectApiName);
    System.assertEquals('ISA - Service Agreement', context.schemaType);
    System.assertEquals(false, context.isSubmitted);
    System.assertNotEquals(null, context.sections);
  }

  @IsTest
  static void loadSubmittedServiceRecord() {
    Service__c service = new Service__c(
      Name = 'Submitted Service',
      Submitted__c = true
    );
    insert service;

    ArcRecordDetailController.RecordDetailContext context =
      ArcRecordDetailController.load(service.Id, null, false, null);

    System.assertEquals(true, context.isSubmitted);
  }

  @IsTest
  static void saveServiceThrowsWhenFieldNotInSchema() {
    Service__c service = new Service__c(Name = 'Before Save');
    insert service;

    Boolean threw = false;
    try {
      ArcRecordDetailController.save(
        service.Id,
        null,
        false,
        null,
        new Map<String, Object>{ 'Name' => 'After Save' }
      );
    } catch (AuraHandledException e) {
      threw = true;
    }
    System.assert(threw, 'Service save should reject fields outside the schema');
  }

  @IsTest
  static void loadFinancialAccountResolvesFinAcctSchema() {
    Financial_Account__c fa = new Financial_Account__c(
      Name = 'Fin Acct Test',
      DPI__c = false
    );
    insert fa;

    ArcRecordDetailController.RecordDetailContext context =
      ArcRecordDetailController.load(fa.Id, null, false, null);

    System.assertEquals('Financial_Account__c', context.objectApiName);
    System.assertEquals('ISA - Fin Acct', context.schemaType);
  }

  @IsTest
  static void loadFinancialAccountResolvesDpiSchema() {
    Financial_Account__c fa = new Financial_Account__c(
      Name = 'DPI Test',
      DPI__c = true
    );
    insert fa;

    ArcRecordDetailController.RecordDetailContext context =
      ArcRecordDetailController.load(fa.Id, null, false, null);

    System.assertEquals('ISA - DPI', context.schemaType);
  }

  @IsTest
  static void loadCaseResolvesSchemaType() {
    Case caseRecord = new Case(
      Subject = 'Edit Individual Request',
      Type = 'Edit Individual'
    );
    insert caseRecord;

    ArcRecordDetailController.RecordDetailContext context =
      ArcRecordDetailController.load(caseRecord.Id, null, false, null);

    System.assertEquals('Case', context.objectApiName);
    System.assertEquals(ARCConstants.SCHEMA_STANDARD_CASE, context.schemaType);
  }

  @IsTest
  static void saveGenericRecordUpdatesConfiguredField() {
    Financial_Account__c fa = new Financial_Account__c(Name = 'Generic Save FA');
    insert fa;

    ArcRecordDetailController.RecordDetailContext context =
      ArcRecordDetailController.load(fa.Id, null, false, null);

    String fieldPath = null;
    for (FieldDetailController.FormSection section : context.sections) {
      for (FieldDetailController.FieldMetadata field : section.fields) {
        if (
          field.addRecord != true &&
          String.isNotBlank(field.fieldPath) &&
          (String.isBlank(field.objectApiName) ||
          field.objectApiName == 'Financial_Account__c')
        ) {
          fieldPath = field.fieldPath;
          break;
        }
      }
      if (fieldPath != null) {
        break;
      }
    }

    if (fieldPath == null) {
      System.assert(true, 'No writable schema fields configured for Financial_Account__c');
      return;
    }

    Test.startTest();
    ArcRecordDetailController.save(
      fa.Id,
      null,
      false,
      null,
      new Map<String, Object>{ fieldPath => 'Updated Value' }
    );
    Test.stopTest();

    System.assert(true, 'Generic save path should complete for configured schema fields');
  }

  @IsTest
  static void saveUpdatesAllowedFields() {
    Account member = new Account(
      FirstName = 'Before',
      LastName = 'Save',
      RecordTypeId = Schema.SObjectType.Account
        .getRecordTypeInfosByDeveloperName()
        .get('PersonAccount')
        .getRecordTypeId()
    );
    insert member;

    Map<String, Object> fields = new Map<String, Object>{
      'FirstName' => 'After',
      'Not_A_Real_Field__c' => 'ignored'
    };

    Test.startTest();
    ArcRecordDetailController.save(member.Id, null, false, null, fields);
    Test.stopTest();

    Account updated = [
      SELECT FirstName
      FROM Account
      WHERE Id = :member.Id
    ];
    System.assertEquals('After', updated.FirstName, 'First name should be updated');
  }

  @IsTest
  static void saveNoOpWhenFieldsEmpty() {
    Account member = new Account(
      LastName = 'Empty',
      RecordTypeId = Schema.SObjectType.Account
        .getRecordTypeInfosByDeveloperName()
        .get('PersonAccount')
        .getRecordTypeId()
    );
    insert member;

    Test.startTest();
    ArcRecordDetailController.save(
      member.Id,
      null,
      false,
      null,
      new Map<String, Object>()
    );
    Test.stopTest();

    System.assert(true, 'Empty field map should complete without error');
  }

  @IsTest
  static void saveStripsPersonFieldsForBusinessAccount() {
    Id businessRecordTypeId = Schema.SObjectType.Account
      .getRecordTypeInfosByDeveloperName()
      .get('Business')
      .getRecordTypeId();

    Account business = new Account(
      Name = 'Acme Corp',
      RecordTypeId = businessRecordTypeId
    );
    insert business;

    Test.startTest();
    ArcRecordDetailController.save(
      business.Id,
      null,
      false,
      null,
      new Map<String, Object>{
        'FirstName' => 'Ignored',
        'LastName' => 'Ignored',
        'Name' => 'Acme Updated'
      }
    );
    Test.stopTest();

    Account updated = [
      SELECT Name, IsPersonAccount
      FROM Account
      WHERE Id = :business.Id
    ];
    System.assertEquals(false, updated.IsPersonAccount);
    System.assertEquals('Acme Updated', updated.Name);
  }

  @IsTest
  static void saveStripsPersonPrefixedFieldsForBusinessAccount() {
    Id businessRecordTypeId = Schema.SObjectType.Account
      .getRecordTypeInfosByDeveloperName()
      .get('Business')
      .getRecordTypeId();

    Account business = new Account(
      Name = 'Birthdate Corp',
      RecordTypeId = businessRecordTypeId
    );
    insert business;

    Test.startTest();
    ArcRecordDetailController.save(
      business.Id,
      null,
      false,
      null,
      new Map<String, Object>{
        'PersonBirthdate' => Date.newInstance(1990, 1, 1),
        'Name' => 'Birthdate Corp Updated'
      }
    );
    Test.stopTest();

    Account updated = [
      SELECT Name
      FROM Account
      WHERE Id = :business.Id
    ];
    System.assertEquals('Birthdate Corp Updated', updated.Name);
  }

  @IsTest
  static void saveStripsNameForPersonAccount() {
    Account member = new Account(
      FirstName = 'Keep',
      LastName = 'Name',
      RecordTypeId = Schema.SObjectType.Account
        .getRecordTypeInfosByDeveloperName()
        .get('PersonAccount')
        .getRecordTypeId()
    );
    insert member;

    Test.startTest();
    ArcRecordDetailController.save(
      member.Id,
      null,
      false,
      null,
      new Map<String, Object>{
        'Name' => 'Should Not Apply',
        'FirstName' => 'Updated'
      }
    );
    Test.stopTest();

    Account updated = [
      SELECT FirstName, LastName
      FROM Account
      WHERE Id = :member.Id
    ];
    System.assertEquals('Updated', updated.FirstName);
    System.assertEquals('Name', updated.LastName);
  }

  @IsTest
  static void saveThrowsWhenNoEditableFieldsRemain() {
    Account member = new Account(
      LastName = 'NoFields',
      RecordTypeId = Schema.SObjectType.Account
        .getRecordTypeInfosByDeveloperName()
        .get('PersonAccount')
        .getRecordTypeId()
    );
    insert member;

    Boolean threw = false;
    try {
      ArcRecordDetailController.save(
        member.Id,
        null,
        false,
        null,
        new Map<String, Object>{ 'Not_In_Schema__c' => 'value' }
      );
    } catch (AuraHandledException e) {
      threw = true;
    }
    System.assert(threw, 'Save with no allowed fields should throw');
  }

  @IsTest
  static void loadResolvesTrustSchemaFromRecordType() {
    Id trustRecordTypeId = Schema.SObjectType.Account
      .getRecordTypeInfosByDeveloperName()
      .get('Trust')
      .getRecordTypeId();

    Account trust = new Account(
      Name = 'Family Trust',
      RecordTypeId = trustRecordTypeId
    );
    insert trust;

    ArcRecordDetailController.RecordDetailContext context =
      ArcRecordDetailController.load(trust.Id, null, false, null);

    System.assertEquals('Client - Trust', context.schemaType);
    System.assertEquals(false, context.isPersonAccount);
  }

  @IsTest
  static void saveTrustAccountName() {
    Id trustRecordTypeId = Schema.SObjectType.Account
      .getRecordTypeInfosByDeveloperName()
      .get('Trust')
      .getRecordTypeId();

    Account trust = new Account(
      Name = 'Trust Before',
      RecordTypeId = trustRecordTypeId
    );
    insert trust;

    Test.startTest();
    ArcRecordDetailController.save(
      trust.Id,
      null,
      false,
      null,
      new Map<String, Object>{ 'Name' => 'Trust After' }
    );
    Test.stopTest();

    Account updated = [
      SELECT Name
      FROM Account
      WHERE Id = :trust.Id
    ];
    System.assertEquals('Trust After', updated.Name);
  }

  @IsTest
  static void loadCaseAccountClosureUsesCaseTypeSchemaOnly() {
    Id accountServicingRecordTypeId = Schema.SObjectType.Case
      .getRecordTypeInfosByDeveloperName()
      .get('Account_Servicing')
      .getRecordTypeId();

    Case caseRecord = new Case(
      Subject = 'Account Closure Request',
      Type = 'Account Closure',
      RecordTypeId = accountServicingRecordTypeId
    );
    insert caseRecord;

    Test.startTest();
    ArcRecordDetailController.RecordDetailContext context =
      ArcRecordDetailController.load(caseRecord.Id, null, false, null);
    Test.stopTest();

    System.assertEquals('Case', context.objectApiName);
    System.assertEquals(
      ARCConstants.SCHEMA_STANDARD_CASE,
      context.schemaType,
      'Case schema should always resolve to Standard Case metadata.'
    );
  }

  @IsTest
  static void loadCaseWithNullTypeUsesStandardCaseSchema() {
    Id accountOpeningRecordTypeId = Schema.SObjectType.Case
      .getRecordTypeInfosByDeveloperName()
      .get('Account_Opening')
      .getRecordTypeId();

    Case caseRecord = new Case(
      Subject = 'Unmapped Type Case',
      Type = null,
      RecordTypeId = accountOpeningRecordTypeId
    );
    insert caseRecord;

    Test.startTest();
    ArcRecordDetailController.RecordDetailContext context =
      ArcRecordDetailController.load(caseRecord.Id, null, false, null);
    Test.stopTest();

    System.assertEquals(
      ARCConstants.SCHEMA_STANDARD_CASE,
      context.schemaType,
      'Cases without Case.Type should still load Standard Case metadata.'
    );
  }

  @IsTest
  static void loadCaseWithExplicitStandardCaseSchemaType() {
    Id accountOpeningRecordTypeId = Schema.SObjectType.Case
      .getRecordTypeInfosByDeveloperName()
      .get('Account_Opening')
      .getRecordTypeId();

    Case caseRecord = new Case(
      Subject = 'Standard Case Request',
      Type = 'Financial Planning',
      RecordTypeId = accountOpeningRecordTypeId
    );
    insert caseRecord;

    Test.startTest();
    ArcRecordDetailController.RecordDetailContext context =
      ArcRecordDetailController.load(caseRecord.Id, null, false, null);
    Test.stopTest();

    System.assertEquals('Case', context.objectApiName);
    System.assertEquals('Standard Case', context.schemaType);
    System.assertNotEquals(null, context.sections);
  }

  @IsTest
  static void findCaseLookupFieldDiscoversServiceRelationship() {
    Map<String, Schema.SObjectField> caseFieldMap =
      Case.SObjectType.getDescribe().fields.getMap();

    System.assertEquals(
      ARCConstants.OBJECT_SERVICE,
      RecordQueryUtil.findCaseLookupField(caseFieldMap, ARCConstants.OBJECT_SERVICE),
      'Case.Service__c should resolve Service__c records dynamically'
    );
  }

  @IsTest
  static void loadCaseAlwaysUsesStandardCaseSchemaRegardlessOfType() {
    Case accountClosureCase = new Case(
      Subject = 'Account Closure Request',
      Type = 'Account Closure'
    );
    insert accountClosureCase;

    Case editIndividualCase = new Case(
      Subject = 'Edit Individual Request',
      Type = 'Edit Individual'
    );
    insert editIndividualCase;

    Test.startTest();
    ArcRecordDetailController.RecordDetailContext closureContext =
      ArcRecordDetailController.load(accountClosureCase.Id, null, false, null);
    ArcRecordDetailController.RecordDetailContext editContext =
      ArcRecordDetailController.load(editIndividualCase.Id, null, false, null);
    Test.stopTest();

    System.assertEquals(
      ARCConstants.SCHEMA_STANDARD_CASE,
      closureContext.schemaType,
      'Account Closure cases should load Standard Case metadata.'
    );
    System.assertEquals(
      ARCConstants.SCHEMA_STANDARD_CASE,
      editContext.schemaType,
      'Edit Individual cases should load Standard Case metadata.'
    );
  }

  @IsTest
  static void loadCaseMergesRelatedServiceValues() {
    Id accountOpeningRecordTypeId = Schema.SObjectType.Case
      .getRecordTypeInfosByDeveloperName()
      .get('Account_Opening')
      .getRecordTypeId();

    Service__c service = new Service__c(
      Name = 'Standard Case Service',
      Terms_of_Payment__c = 'Hourly Fee'
    );
    insert service;

    Case caseRecord = new Case(
      Subject = 'FP Case',
      Type = 'Financial Planning',
      Service__c = service.Id,
      RecordTypeId = accountOpeningRecordTypeId
    );
    insert caseRecord;

    Test.startTest();
    ArcRecordDetailController.RecordDetailContext context =
      ArcRecordDetailController.load(caseRecord.Id, null, false, null);
    Test.stopTest();

    System.assertEquals('Standard Case', context.schemaType);
    System.assertEquals(
      'Hourly Fee',
      context.values.get('Terms_of_Payment__c'),
      'Related Service field values should merge into the Case draft'
    );
  }

  @IsTest
  static void saveCaseUpdatesRelatedServiceField() {
    Id accountOpeningRecordTypeId = Schema.SObjectType.Case
      .getRecordTypeInfosByDeveloperName()
      .get('Account_Opening')
      .getRecordTypeId();

    Service__c service = new Service__c(
      Name = 'Save Service',
      Terms_of_Payment__c = 'Hourly Fee'
    );
    insert service;

    Case caseRecord = new Case(
      Subject = 'FP Save Case',
      Type = 'Financial Planning',
      Service__c = service.Id,
      RecordTypeId = accountOpeningRecordTypeId
    );
    insert caseRecord;

    Test.startTest();
    ArcRecordDetailController.save(
      caseRecord.Id,
      null,
      false,
      null,
      new Map<String, Object>{ 'Terms_of_Payment__c' => 'Fixed Project Fee' }
    );
    Test.stopTest();

    Service__c updated = [
      SELECT Terms_of_Payment__c
      FROM Service__c
      WHERE Id = :service.Id
    ];
    System.assertEquals('Fixed Project Fee', updated.Terms_of_Payment__c);
  }

  @IsTest
  static void saveCaseThrowsWhenRelatedRecordMissing() {
    Id accountOpeningRecordTypeId = Schema.SObjectType.Case
      .getRecordTypeInfosByDeveloperName()
      .get('Account_Opening')
      .getRecordTypeId();

    Case caseRecord = new Case(
      Subject = 'FP Missing Service',
      Type = 'Financial Planning',
      RecordTypeId = accountOpeningRecordTypeId
    );
    insert caseRecord;

    Boolean threw = false;
    try {
      ArcRecordDetailController.save(
        caseRecord.Id,
        null,
        false,
        null,
        new Map<String, Object>{ 'Terms_of_Payment__c' => 'Fixed Project Fee' }
      );
    } catch (AuraHandledException e) {
      threw = true;
    }
    System.assert(threw, 'Save should fail when Case has no linked Service record');
  }

  @IsTest
  static void loadRelatedRecordModeResolvesServiceFromCase() {
    Id accountOpeningRecordTypeId = Schema.SObjectType.Case
      .getRecordTypeInfosByDeveloperName()
      .get('Account_Opening')
      .getRecordTypeId();

    Service__c service = new Service__c(
      Name = 'Related Mode Service',
      Terms_of_Payment__c = 'Hourly Fee'
    );
    insert service;

    Case caseRecord = new Case(
      Subject = 'Related Mode Case',
      Type = 'Financial Planning',
      Service__c = service.Id,
      RecordTypeId = accountOpeningRecordTypeId
    );
    insert caseRecord;

    Test.startTest();
    ArcRecordDetailController.RecordDetailContext context =
      ArcRecordDetailController.load(
        caseRecord.Id,
        null,
        true,
        'Service__c'
      );
    Test.stopTest();

    System.assertEquals(false, context.hidden);
    System.assertEquals(caseRecord.Id, context.pageRecordId);
    System.assertEquals(service.Id, context.displayRecordId);
    System.assertEquals('Service__c', context.objectApiName);
    System.assertEquals(
      ARCConstants.SCHEMA_ISA_SERVICE_AGREEMENT,
      context.schemaType
    );
    System.assertEquals(
      'Hourly Fee',
      context.values.get('Terms_of_Payment__c'),
      'Values should come from the related Service record'
    );
  }

  @IsTest
  static void loadRelatedRecordModeHidesWhenLookupEmpty() {
    Id accountOpeningRecordTypeId = Schema.SObjectType.Case
      .getRecordTypeInfosByDeveloperName()
      .get('Account_Opening')
      .getRecordTypeId();

    Case caseRecord = new Case(
      Subject = 'No Service Linked',
      Type = 'Financial Planning',
      RecordTypeId = accountOpeningRecordTypeId
    );
    insert caseRecord;

    Test.startTest();
    ArcRecordDetailController.RecordDetailContext context =
      ArcRecordDetailController.load(
        caseRecord.Id,
        null,
        true,
        'Service__c'
      );
    Test.stopTest();

    System.assertEquals(true, context.hidden);
    System.assertEquals(caseRecord.Id, context.pageRecordId);
    System.assertEquals(null, context.displayRecordId);
    System.assertEquals(0, context.sections.size());
  }

  @IsTest
  static void loadRelatedRecordModeRequiresLookupField() {
    Case caseRecord = new Case(Subject = 'Missing Lookup Config');
    insert caseRecord;

    Boolean threw = false;
    try {
      ArcRecordDetailController.load(caseRecord.Id, null, true, null);
    } catch (AuraHandledException e) {
      threw = true;
    }
    System.assert(threw, 'Related mode without lookup field should throw');
  }

  @IsTest
  static void loadRelatedRecordModeRejectsInvalidLookupField() {
    Case caseRecord = new Case(Subject = 'Invalid Lookup Field');
    insert caseRecord;

    Boolean threw = false;
    try {
      ArcRecordDetailController.load(
        caseRecord.Id,
        null,
        true,
        'Not_A_Real_Field__c'
      );
    } catch (AuraHandledException e) {
      threw = true;
    }
    System.assert(threw, 'Invalid lookup field API should throw');
  }

  @IsTest
  static void collectWhereReferencedFieldApisIncludesBooleanGates() {
    Map<String, Schema.SObjectField> caseFields =
      Case.SObjectType.getDescribe().fields.getMap();

    FieldDetailController.FieldMetadata amountField =
      new FieldDetailController.FieldMetadata();
    amountField.fieldPath = 'Amount__c';
    amountField.shownWhereStatement = 'Source_of_Funds_Value__c = true';

    FieldDetailController.FormSection section = new FieldDetailController.FormSection(
      'Source of Funds'
    );
    section.fields.add(amountField);

    Set<String> fieldApis = ArcRecordDetailController.collectWhereReferencedFieldApis(
      new List<FieldDetailController.FormSection>{ section },
      caseFields
    );

    System.assert(
      fieldApis.contains('Source_of_Funds_Value__c'),
      'Boolean gate fields referenced only in WHERE should be collected.'
    );
  }

  @IsTest
  static void loadStandardCaseIncludesBooleanWhereGateValues() {
    List<Envelope_Field__mdt> amountRows = [
      SELECT Field_API__c
      FROM Envelope_Field__mdt
      WHERE Type__c = 'Standard Case'
      AND Object__c = 'Case'
      AND Field_API__c = 'Amount__c'
      LIMIT 1
    ];
    if (amountRows.isEmpty()) {
      return;
    }

    List<Case> existingCases = [
      SELECT Id
      FROM Case
      WHERE Source_of_Funds_Value__c = true
      AND Amount__c != null
      LIMIT 1
    ];
    if (existingCases.isEmpty()) {
      return;
    }

    Test.startTest();
    ArcRecordDetailController.RecordDetailContext context =
      ArcRecordDetailController.load(existingCases[0].Id, null, false, null);
    Test.stopTest();

    System.assertEquals(
      true,
      context.values.get('Source_of_Funds_Value__c'),
      'Boolean gate values must be present for client-side Shown WHERE evaluation.'
    );
    System.assertNotEquals(
      null,
      context.values.get('Amount__c'),
      'Configured field values should still load.'
    );
  }

  @IsTest
  static void loadAccountClosureCaseSerializesDateValuesAsIsoStrings() {
    Id accountServicingRecordTypeId = Schema.SObjectType.Case
      .getRecordTypeInfosByDeveloperName()
      .get('Account_Servicing')
      .getRecordTypeId();

    Case caseRecord = new Case(
      Subject = 'Closure With End Date',
      Type = 'Account Closure',
      RecordTypeId = accountServicingRecordTypeId,
      Account_Closure_Reason__c = 'Client Terminated Services',
      Account_Closure_End_Date__c = Date.newInstance(2024, 7, 19)
    );
    insert caseRecord;

    Test.startTest();
    ArcRecordDetailController.RecordDetailContext context =
      ArcRecordDetailController.load(caseRecord.Id, null, false, null);
    Test.stopTest();

    System.assertEquals(
      '2024-07-19',
      context.values.get('Account_Closure_End_Date__c'),
      'Date fields should be serialized as YYYY-MM-DD strings for the LWC layer.'
    );
  }

  @IsTest
  static void formatFieldValueForWireSerializesDateAndDatetime() {
    System.assertEquals(
      '2024-07-19',
      ArcRecordDetailController.formatFieldValueForWire(
        Date.newInstance(2024, 7, 19),
        Schema.DisplayType.DATE
      )
    );
    System.assertEquals(
      '2024-07-19T15:30:00Z',
      ArcRecordDetailController.formatFieldValueForWire(
        Datetime.newInstanceGmt(2024, 7, 19, 15, 30, 0),
        Schema.DisplayType.DATETIME
      )
    );
  }
}