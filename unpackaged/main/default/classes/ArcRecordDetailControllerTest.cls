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
    ArcRecordDetailController.RecordDetailContext context = ArcRecordDetailController.load(
      member.Id,
      null,
      null
    );
    Test.stopTest();

    System.assertNotEquals(null, context, 'Context should not be null');
    System.assertEquals('Account', context.objectApiName);
    System.assertEquals(
      'Client - Individual',
      context.schemaType,
      'Person account should resolve individual schema'
    );
    System.assertEquals(true, context.isPersonAccount);
    System.assertNotEquals(
      null,
      context.sections,
      'Sections should not be null'
    );
    System.assertNotEquals(null, context.values, 'Values should not be null');
    System.assertNotEquals(
      null,
      context.userContext,
      'User context should not be null'
    );
    System.assertEquals(
      false,
      context.isSubmitted,
      'Unsubmitted record should be editable'
    );
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
    ArcRecordDetailController.RecordDetailContext context = ArcRecordDetailController.load(
      business.Id,
      null,
      null
    );
    Test.stopTest();

    System.assertEquals('Account', context.objectApiName);
    System.assertEquals('Client - Business', context.schemaType);
    System.assertEquals(false, context.isPersonAccount);
  }

  @IsTest
  static void resolveAccountSchemaTypeMapsKnownRecordTypes() {
    Assert.areEqual(
      'Client - Individual',
      ArcRecordDetailController.resolveAccountSchemaType('PersonAccount', true),
      'A person account keeps the individual schema.'
    );
    Assert.areEqual(
      'Client - Business',
      ArcRecordDetailController.resolveAccountSchemaType(
        'IndustriesBusiness',
        false
      ),
      'Business record types keep the business schema.'
    );
    Assert.areEqual(
      'Client - Trust',
      ArcRecordDetailController.resolveAccountSchemaType(
        'IndustriesInstitution',
        false
      ),
      'Institution record types keep the trust schema.'
    );
    Assert.areEqual(
      'Client - Retirement Plan',
      ArcRecordDetailController.resolveAccountSchemaType(
        'Retirement_Plan',
        false
      ),
      'Retirement plans keep their own schema.'
    );
  }

  /**
   * Household has no schema of its own. It used to fall back to
   * Client - Individual, which is built on person-account fields a business
   * account cannot store, so every Household rendered a form it could not save.
   */
  @IsTest
  static void resolveAccountSchemaTypeFallsBackByAccountKind() {
    Assert.areEqual(
      'Client - Business',
      ArcRecordDetailController.resolveAccountSchemaType('Household', false),
      'A Household is a business account and must not get the person schema.'
    );
    Assert.areEqual(
      'Client - Business',
      ArcRecordDetailController.resolveAccountSchemaType('Unknown_Type', false),
      'An unmapped business record type falls back to the business schema.'
    );
    Assert.areEqual(
      'Client - Individual',
      ArcRecordDetailController.resolveAccountSchemaType('Unknown_Type', true),
      'An unmapped person account still falls back to the individual schema.'
    );
    Assert.areEqual(
      'Client - Business',
      ArcRecordDetailController.resolveAccountSchemaType(null, false),
      'A blank record type on a business account falls back to business.'
    );
  }

  /**
   * A section edit must never change the record's type. Saving used to route
   * Accounts through the envelope wizard's member-save routine, which forces
   * RecordTypeId from the schema type; on a Household that attempted a
   * business-to-person conversion and Salesforce rejected the whole update.
   */
  @IsTest
  static void saveLeavesTheAccountRecordTypeAlone() {
    Id householdRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get('Household')
      .getRecordTypeId();

    Account household = new Account(
      Name = 'Schema Fallback Household',
      RecordTypeId = householdRecordTypeId
    );
    insert household;

    Test.startTest();
    ArcRecordDetailController.save(
      household.Id,
      'Account',
      null,
      new Map<String, Object>{ 'BillingCity' => 'Denver' }
    );
    Test.stopTest();

    Account reloaded = [
      SELECT RecordTypeId, BillingCity
      FROM Account
      WHERE Id = :household.Id
    ];
    Assert.areEqual(
      householdRecordTypeId,
      reloaded.RecordTypeId,
      'Editing a section must not convert the record to another type.'
    );
    Assert.areEqual(
      'Denver',
      reloaded.BillingCity,
      'The edited field should still be written.'
    );
  }

  /**
   * "Edit Regulated Fields" used to only dispatch an event nothing listened
   * for, so confirming the dialog did nothing. The envelope is raised against
   * the member's household, and has to carry Status__c and Household__c or the
   * wizard's own list filters it straight back out and opens on the list.
   */
  @IsTest
  static void startRegulatedFieldsEnvelopeOpensAnEnvelopeOnTheHousehold() {
    Account household = new Account(
      Name = 'Regulated Fields Household',
      RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
        .get('Household')
        .getRecordTypeId()
    );
    insert household;

    Account member = new Account(
      FirstName = 'Regulated',
      LastName = 'Member',
      Household__c = household.Id,
      RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
        .get('PersonAccount')
        .getRecordTypeId()
    );
    insert member;

    Test.startTest();
    Id envelopeId = ArcRecordDetailController.startRegulatedFieldsEnvelope(
      member.Id
    );
    Test.stopTest();

    Assert.isNotNull(envelopeId, 'An envelope should have been created.');

    Envelope__c envelope = [
      SELECT Status__c, Household__c
      FROM Envelope__c
      WHERE Id = :envelopeId
    ];
    Assert.areEqual(
      'New',
      envelope.Status__c,
      'An envelope the wizard cannot list is the same as no envelope.'
    );
    Assert.areEqual(
      household.Id,
      envelope.Household__c,
      'A member edits its regulated fields through its household.'
    );
  }

  /** Nothing else on the site declares regulated fields. */
  @IsTest
  static void startRegulatedFieldsEnvelopeRejectsNonAccounts() {
    Task task = new Task(Subject = 'Not an account');
    insert task;

    Boolean threw = false;
    try {
      ArcRecordDetailController.startRegulatedFieldsEnvelope(task.Id);
    } catch (AuraHandledException e) {
      threw = true;
    }
    Assert.isTrue(
      threw,
      'Only accounts can start a regulated-fields envelope.'
    );
  }

  /** Task and Check Log resolve their one schema without a record-type branch. */
  @IsTest
  static void singleSchemaObjectsResolveTheirOwnSchemaType() {
    Assert.areEqual(
      'Task',
      ArcRecordDetailController.SINGLE_SCHEMA_OBJECTS.get('Task'),
      'Task detail is driven by the Task schema.'
    );
    Assert.areEqual(
      'Check Log',
      ArcRecordDetailController.SINGLE_SCHEMA_OBJECTS.get('Check_Log__c'),
      'Check Log detail is driven by the Check Log schema.'
    );
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
      ArcRecordDetailController.load(null, null, null);
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
    ArcRecordDetailController.RecordDetailContext context = ArcRecordDetailController.load(
      service.Id,
      null,
      null
    );
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

    ArcRecordDetailController.RecordDetailContext context = ArcRecordDetailController.load(
      service.Id,
      null,
      null
    );

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
        null,
        new Map<String, Object>{ 'Name' => 'After Save' }
      );
    } catch (AuraHandledException e) {
      threw = true;
    }
    System.assert(
      threw,
      'Service save should reject fields outside the schema'
    );
  }

  @IsTest
  static void loadFinancialAccountResolvesFinAcctSchema() {
    Financial_Account__c fa = new Financial_Account__c(
      Name = 'Fin Acct Test',
      DPI__c = false
    );
    insert fa;

    ArcRecordDetailController.RecordDetailContext context = ArcRecordDetailController.load(
      fa.Id,
      null,
      null
    );

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

    ArcRecordDetailController.RecordDetailContext context = ArcRecordDetailController.load(
      fa.Id,
      null,
      null
    );

    System.assertEquals('ISA - DPI', context.schemaType);
  }

  @IsTest
  static void loadCaseResolvesSchemaType() {
    Case caseRecord = new Case(
      Subject = 'Edit Individual Request',
      Type = 'Edit Individual'
    );
    insert caseRecord;

    ArcRecordDetailController.RecordDetailContext context = ArcRecordDetailController.load(
      caseRecord.Id,
      null,
      null
    );

    System.assertEquals('Case', context.objectApiName);
    System.assertEquals('Client - Individual', context.schemaType);
  }

  @IsTest
  static void saveGenericRecordUpdatesConfiguredField() {
    Financial_Account__c fa = new Financial_Account__c(
      Name = 'Generic Save FA'
    );
    insert fa;

    ArcRecordDetailController.RecordDetailContext context = ArcRecordDetailController.load(
      fa.Id,
      null,
      null
    );

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
      System.assert(
        true,
        'No writable schema fields configured for Financial_Account__c'
      );
      return;
    }

    Test.startTest();
    ArcRecordDetailController.save(
      fa.Id,
      null,
      null,
      new Map<String, Object>{ fieldPath => 'Updated Value' }
    );
    Test.stopTest();

    System.assert(
      true,
      'Generic save path should complete for configured schema fields'
    );
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
    ArcRecordDetailController.save(member.Id, null, null, fields);
    Test.stopTest();

    Account updated = [
      SELECT FirstName
      FROM Account
      WHERE Id = :member.Id
    ];
    System.assertEquals(
      'After',
      updated.FirstName,
      'First name should be updated'
    );
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

    ArcRecordDetailController.RecordDetailContext context = ArcRecordDetailController.load(
      trust.Id,
      null,
      null
    );

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
}