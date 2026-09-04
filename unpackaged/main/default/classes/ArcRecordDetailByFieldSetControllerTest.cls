/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-13
 */
@IsTest
private class ArcRecordDetailByFieldSetControllerTest {

  private static String resolveAccountFieldSetApiName() {
    Map<String, Schema.FieldSet> fieldSetMap = Account.SObjectType
      .getDescribe()
      .fieldSets.getMap();
    return fieldSetMap.isEmpty() ? null : new List<String>(fieldSetMap.keySet())[0];
  }

  private static Object buildTestValue(FieldSetController.FieldMetadata field) {
    if (field == null) {
      return null;
    }

    switch on field.type {
      when 'BOOLEAN' {
        return true;
      }
      when 'DATE' {
        return String.valueOf(Date.today());
      }
      when 'DATETIME' {
        return System.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
      }
      when 'DOUBLE', 'CURRENCY', 'PERCENT' {
        return '1';
      }
      when 'INTEGER' {
        return '1';
      }
      when 'PHONE' {
        return '5555555555';
      }
      when 'EMAIL' {
        return 'test@example.com';
      }
      when 'URL' {
        return 'https://example.com';
      }
      when 'TEXTAREA', 'STRING' {
        return 'Test value';
      }
      when 'PICKLIST' {
        if (field.picklistOptions != null && !field.picklistOptions.isEmpty()) {
          return field.picklistOptions[0].value;
        }
        return null;
      }
      when 'MULTIPICKLIST' {
        if (field.picklistOptions != null && !field.picklistOptions.isEmpty()) {
          return new List<Object>{ field.picklistOptions[0].value };
        }
        return null;
      }
      when else {
        return null;
      }
    }
  }

  @IsTest
  static void loadReturnsFieldSetMetadataAndValues() {
    String fieldSetApiName = resolveAccountFieldSetApiName();
    if (fieldSetApiName == null) {
      return;
    }

    Account account = new Account(
      Name = 'Field Set Test Account',
      Description = 'Loaded description',
      Phone = '5555555555',
      Classification__c = 'Unclassified'
    );
    insert account;

    Test.startTest();
    ArcRecordDetailByFieldSetController.LoadResult result =
      ArcRecordDetailByFieldSetController.load(account.Id, 'Account', fieldSetApiName);
    Test.stopTest();

    System.assertNotEquals(null, result, 'Result should not be null');
    System.assertEquals('Account', result.objectApiName);
    System.assertEquals(fieldSetApiName, result.fieldSetApiName);
    System.assertNotEquals(null, result.fields, 'Fields should not be null');
    System.assertNotEquals(null, result.values, 'Values should not be null');
    System.assert(result.fields.size() > 0, 'Field set should contain fields');
  }

  @IsTest
  static void saveRecordFieldsUpdatesDescription() {
    Account account = new Account(Name = 'Direct Save', Classification__c = 'Unclassified');
    insert account;

    Test.startTest();
    ArcRecordDetailByFieldSetController.saveRecordFields(
      account.Id,
      'Account',
      new Map<String, Object>{ 'Description' => 'Updated from test' }
    );
    Test.stopTest();

    System.assertEquals(
      'Updated from test',
      [SELECT Description FROM Account WHERE Id = :account.Id].Description
    );
  }

  @IsTest
  static void saveUpdatesFirstEditableFieldInFieldSet() {
    Map<String, Schema.FieldSet> fieldSetMap = Account.SObjectType
      .getDescribe()
      .fieldSets.getMap();

    Account account = new Account(Name = 'Before Save', Classification__c = 'Unclassified');
    insert account;

    Boolean saved = false;
    for (String fieldSetApiName : fieldSetMap.keySet()) {
      List<FieldSetController.FieldMetadata> fields = FieldSetController.getFieldSetFields(
        'Account',
        fieldSetApiName
      );

      for (FieldSetController.FieldMetadata field : fields) {
        if (
          field == null ||
          field.disabled == true ||
          String.isBlank(field.fieldPath) ||
          field.fieldPath.contains('.')
        ) {
          continue;
        }

        Object testValue = buildTestValue(field);
        if (testValue == null) {
          continue;
        }

        try {
          ArcRecordDetailByFieldSetController.save(
            account.Id,
            'Account',
            fieldSetApiName,
            new Map<String, Object>{ field.fieldPath => testValue }
          );
          saved = true;
          break;
        } catch (Exception error) {
          // Try the next configured field or field set.
        }
      }

      if (saved) {
        break;
      }
    }

    if (fieldSetMap.isEmpty()) {
      return;
    }

    System.assert(saved, 'Expected at least one field set field to save successfully');
  }

  @IsTest
  static void loadResolvesPolymorphicReferenceFields() {
    User ownerUser = [SELECT Id, Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
    Case parentCase = new Case(
      Subject = 'Case for Task',
      Status = 'New',
      Origin = 'Phone'
    );
    insert parentCase;
    parentCase = [SELECT CaseNumber FROM Case WHERE Id = :parentCase.Id];

    Task task = new Task(
      Subject = 'Lookup Task',
      WhatId = parentCase.Id,
      OwnerId = ownerUser.Id,
      Status = 'Completed',
      Priority = 'Normal'
    );
    insert task;

    List<FieldSetController.FieldMetadata> fields = new List<FieldSetController.FieldMetadata>();

    FieldSetController.FieldMetadata whatField = new FieldSetController.FieldMetadata();
    whatField.label = 'Related To';
    whatField.fieldPath = 'WhatId';
    whatField.type = 'REFERENCE';
    whatField.inputType = 'text';
    fields.add(whatField);

    FieldSetController.FieldMetadata ownerField = new FieldSetController.FieldMetadata();
    ownerField.label = 'Assigned To';
    ownerField.fieldPath = 'OwnerId';
    ownerField.type = 'REFERENCE';
    ownerField.inputType = 'text';
    fields.add(ownerField);

    Test.startTest();
    Map<String, Object> values = ArcRecordDetailByFieldSetController.readRecordValues(
      task.Id,
      'Task',
      fields
    );
    Test.stopTest();

    System.assertEquals(parentCase.Id, values.get('WhatId'));
    System.assertEquals(
      'Case',
      whatField.referenceTo,
      'Polymorphic lookup should resolve the related object api name'
    );
    System.assertEquals('PICKLIST', whatField.type);
    System.assertEquals(
      parentCase.CaseNumber,
      whatField.picklistOptions[0].label,
      'Case lookup should display CaseNumber'
    );

    System.assertEquals(ownerUser.Id, values.get('OwnerId'));
    System.assertEquals('PICKLIST', ownerField.type);
    System.assertEquals(
      ownerUser.Name,
      ownerField.picklistOptions[0].label,
      'Owner lookup should display the user name'
    );
  }

  @IsTest
  static void loadResolvesReferenceFieldToRelatedName() {
    Account parentAccount = new Account(
      Name = 'Parent Lookup Account',
      Classification__c = 'Unclassified',
      RecordTypeId = Schema.SObjectType.Account
        .getRecordTypeInfosByDeveloperName()
        .get('Household')
        .getRecordTypeId()
    );
    insert parentAccount;

    Account childAccount = new Account(
      Name = 'Child Lookup Account',
      ParentId = parentAccount.Id,
      Classification__c = 'Unclassified'
    );
    insert childAccount;

    List<FieldSetController.FieldMetadata> fields = new List<FieldSetController.FieldMetadata>();
    FieldSetController.FieldMetadata parentField = new FieldSetController.FieldMetadata();
    parentField.label = 'Parent Account';
    parentField.fieldPath = 'ParentId';
    parentField.type = 'REFERENCE';
    parentField.inputType = 'text';
    parentField.referenceTo = 'Account';
    fields.add(parentField);

    Test.startTest();
    Map<String, Object> values = ArcRecordDetailByFieldSetController.readRecordValues(
      childAccount.Id,
      'Account',
      fields
    );
    Test.stopTest();

    System.assertEquals(
      parentAccount.Id,
      values.get('ParentId'),
      'Lookup value should remain the related record id'
    );
    System.assertEquals('PICKLIST', parentField.type, 'Lookup should be shaped for display');
    System.assertEquals(1, parentField.picklistOptions.size());
    System.assertEquals(
      'Parent Lookup Account',
      parentField.picklistOptions[0].label,
      'Lookup label should be the related record name'
    );
    System.assertEquals(
      String.valueOf(parentAccount.Id),
      parentField.picklistOptions[0].value,
      'Lookup option value should be the related record id'
    );
  }

  @IsTest
  static void loadReturnsValuesMapForExistingRecord() {
    String fieldSetApiName = resolveAccountFieldSetApiName();
    if (fieldSetApiName == null) {
      return;
    }

    Account account = new Account(
      Name = 'Lookup Account',
      Description = 'Loaded from test',
      Classification__c = 'Unclassified'
    );
    insert account;

    Test.startTest();
    ArcRecordDetailByFieldSetController.LoadResult result =
      ArcRecordDetailByFieldSetController.load(account.Id, 'Account', fieldSetApiName);
    Test.stopTest();

    System.assertNotEquals(null, result.values);
  }

  @IsTest
  static void saveRejectsUnknownObject() {
    Account account = new Account(Name = 'Validation Account', Classification__c = 'Unclassified');
    insert account;

    Boolean threw = false;
    try {
      ArcRecordDetailByFieldSetController.save(
        account.Id,
        'No_Such_Object__c',
        'Any_Field_Set',
        new Map<String, Object>{ 'Name' => 'Updated' }
      );
    } catch (AuraHandledException error) {
      threw = true;
    }
    System.assert(threw, 'Unknown object should throw on save');
  }

  @IsTest
  static void saveNoOpsOnEmptyPayload() {
    String fieldSetApiName = resolveAccountFieldSetApiName();
    if (fieldSetApiName == null) {
      return;
    }

    Account account = new Account(Name = 'No Op Save', Classification__c = 'Unclassified');
    insert account;

    Test.startTest();
    ArcRecordDetailByFieldSetController.save(
      account.Id,
      'Account',
      fieldSetApiName,
      new Map<String, Object>()
    );
    Test.stopTest();

    System.assertEquals(
      'No Op Save',
      [SELECT Name FROM Account WHERE Id = :account.Id].Name
    );
  }

  @IsTest
  static void saveRejectsDisallowedFields() {
    String fieldSetApiName = resolveAccountFieldSetApiName();
    if (fieldSetApiName == null) {
      return;
    }

    Account account = new Account(Name = 'Disallowed Save', Classification__c = 'Unclassified');
    insert account;

    Boolean threw = false;
    try {
      ArcRecordDetailByFieldSetController.save(
        account.Id,
        'Account',
        fieldSetApiName,
        new Map<String, Object>{ 'NotARealField__c' => 'value' }
      );
    } catch (AuraHandledException error) {
      threw = true;
    }

    System.assert(threw, 'Disallowed fields should throw');
  }

  @IsTest
  static void saveRejectsMissingRecordId() {
    Boolean threw = false;
    try {
      ArcRecordDetailByFieldSetController.save(
        null,
        'Account',
        'Any_Field_Set',
        new Map<String, Object>{ 'Name' => 'Updated' }
      );
    } catch (AuraHandledException error) {
      threw = true;
    }
    System.assert(threw, 'Null record id should throw');
  }

  @IsTest
  static void saveRejectsMissingObjectApiName() {
    Account account = new Account(Name = 'Validation Account', Classification__c = 'Unclassified');
    insert account;

    Boolean threw = false;
    try {
      ArcRecordDetailByFieldSetController.save(
        account.Id,
        '',
        'Any_Field_Set',
        new Map<String, Object>{ 'Name' => 'Updated' }
      );
    } catch (AuraHandledException error) {
      threw = true;
    }
    System.assert(threw, 'Blank object api name should throw');
  }

  @IsTest
  static void saveRejectsMissingFieldSetApiName() {
    Account account = new Account(Name = 'Validation Account', Classification__c = 'Unclassified');
    insert account;

    Boolean threw = false;
    try {
      ArcRecordDetailByFieldSetController.save(
        account.Id,
        'Account',
        '',
        new Map<String, Object>{ 'Name' => 'Updated' }
      );
    } catch (AuraHandledException error) {
      threw = true;
    }
    System.assert(threw, 'Blank field set api name should throw');
  }

  @IsTest
  static void loadRejectsMissingRecordId() {
    Boolean threw = false;
    try {
      ArcRecordDetailByFieldSetController.load(null, 'Account', 'Any_Field_Set');
    } catch (AuraHandledException error) {
      threw = true;
    }
    System.assert(threw, 'Null record id should throw');
  }

  @IsTest
  static void loadRejectsMissingObjectApiName() {
    Account account = new Account(Name = 'Validation Account', Classification__c = 'Unclassified');
    insert account;

    Boolean threw = false;
    try {
      ArcRecordDetailByFieldSetController.load(account.Id, '', 'Any_Field_Set');
    } catch (AuraHandledException error) {
      threw = true;
    }
    System.assert(threw, 'Blank object api name should throw');
  }

  @IsTest
  static void loadRejectsMissingFieldSetApiName() {
    Account account = new Account(Name = 'Validation Account', Classification__c = 'Unclassified');
    insert account;

    Boolean threw = false;
    try {
      ArcRecordDetailByFieldSetController.load(account.Id, 'Account', '');
    } catch (AuraHandledException error) {
      threw = true;
    }
    System.assert(threw, 'Blank field set api name should throw');
  }

  @IsTest
  static void loadRejectsUnknownFieldSet() {
    Account account = new Account(Name = 'Validation Account', Classification__c = 'Unclassified');
    insert account;

    Boolean threw = false;
    try {
      ArcRecordDetailByFieldSetController.load(
        account.Id,
        'Account',
        'No_Such_Field_Set__c'
      );
    } catch (AuraHandledException error) {
      threw = true;
    }
    System.assert(threw, 'Unknown field set should throw');
  }

  @IsTest
  static void loadRejectsUnknownObject() {
    Account account = new Account(Name = 'Validation Account', Classification__c = 'Unclassified');
    insert account;

    Boolean threw = false;
    try {
      ArcRecordDetailByFieldSetController.load(
        account.Id,
        'No_Such_Object__c',
        'Any_Field_Set'
      );
    } catch (AuraHandledException error) {
      threw = true;
    }
    System.assert(threw, 'Unknown object should throw');
  }
}