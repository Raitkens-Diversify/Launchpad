@IsTest
private class ArcAccountRelationshipsControllerTest {
  @TestSetup
  static void setup() {
    Id trustRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get('Trust')
      .getRecordTypeId();
    Id businessRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get('Business')
      .getRecordTypeId();
    Id individualRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get('Diversify_Related_Person')
      .getRecordTypeId();
    Id householdRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get('Household')
      .getRecordTypeId();
    Id fiduciaryRecordTypeId = Schema.SObjectType.Account_Account_Relationship__c.getRecordTypeInfosByDeveloperName()
      .get('Fiduciary_Legal')
      .getRecordTypeId();

    Account trustAccount = new Account(Name = 'Test Trust', RecordTypeId = trustRecordTypeId);
    Account estateAccount = new Account(
      Name = 'Test Estate',
      RecordTypeId = trustRecordTypeId,
      Trust_Type__c = 'Estate'
    );
    Account businessAccount = new Account(Name = 'Test Business', RecordTypeId = businessRecordTypeId);
    // Diversify_Related_Person is a true Person Account record type -- Name
    // is computed from First/Last, not directly settable.
    Account individualAccount = new Account(
      FirstName = 'Test',
      LastName = 'Individual',
      RecordTypeId = individualRecordTypeId
    );
    Account householdAccount = new Account(Name = 'Test Household', RecordTypeId = householdRecordTypeId);
    // The "related person" stand-ins only need to exist and have a Name --
    // their own record type isn't what this test is checking -- so these
    // use the plain Business type rather than fighting Person Account's
    // First/Last-only Name.
    Account trusteePerson = new Account(Name = 'Trustee Person', RecordTypeId = businessRecordTypeId);
    Account grantorPerson = new Account(Name = 'Grantor Person', RecordTypeId = businessRecordTypeId);
    Account executorPerson = new Account(Name = 'Executor Person', RecordTypeId = businessRecordTypeId);
    Account beneficialOwnerPerson = new Account(
      Name = 'Beneficial Owner Person',
      RecordTypeId = businessRecordTypeId
    );
    Account trustedContactPerson = new Account(
      Name = 'Trusted Contact Person',
      RecordTypeId = businessRecordTypeId
    );

    insert new List<Account>{
      trustAccount,
      estateAccount,
      businessAccount,
      individualAccount,
      householdAccount,
      trusteePerson,
      grantorPerson,
      executorPerson,
      beneficialOwnerPerson,
      trustedContactPerson
    };

    insert new List<Account_Account_Relationship__c>{
      new Account_Account_Relationship__c(
        Account__c = trustAccount.Id,
        Related_Account__c = trusteePerson.Id,
        //Roles__c = 'Trustee',
        RecordTypeId = fiduciaryRecordTypeId,
        Active__c = true
      ),
      new Account_Account_Relationship__c(
        Account__c = trustAccount.Id,
        Related_Account__c = grantorPerson.Id,
        //Roles__c = 'Grantor',
        RecordTypeId = fiduciaryRecordTypeId,
        Active__c = true
      ),
      new Account_Account_Relationship__c(
        Account__c = estateAccount.Id,
        Related_Account__c = executorPerson.Id,
        //Roles__c = 'Executor / Personal Representative',
        RecordTypeId = fiduciaryRecordTypeId,
        Active__c = true
      ),
      new Account_Account_Relationship__c(
        Account__c = businessAccount.Id,
        Related_Account__c = beneficialOwnerPerson.Id,
        //Roles__c = 'Beneficial Owner',
        RecordTypeId = fiduciaryRecordTypeId,
        Active__c = true
      ),
      new Account_Account_Relationship__c(
        Account__c = individualAccount.Id,
        Related_Account__c = trustedContactPerson.Id,
        //Roles__c = 'Trusted Contact',
        RecordTypeId = fiduciaryRecordTypeId,
        Active__c = true
      ),
      // Inactive rows and rows on other record types must never surface.
      new Account_Account_Relationship__c(
        Account__c = trustAccount.Id,
        Related_Account__c = trustedContactPerson.Id,
        //Roles__c = 'Trustee',
        RecordTypeId = fiduciaryRecordTypeId,
        Active__c = false
      )
    };
  }

  @IsTest
  static void returnsTrusteeAndGrantorForTrust() {
    Account trustAccount = [SELECT Id FROM Account WHERE Name = 'Test Trust' LIMIT 1];

    Test.startTest();
    ArcAccountRelationshipsController.RelationshipsResult result = ArcAccountRelationshipsController.getRelationships(
      trustAccount.Id
    );
    Test.stopTest();

    Assert.areEqual('Trust', result.category);
    Assert.areEqual(2, result.groups.size());
    Assert.areEqual('Trustee', result.groups[0].label);
    Assert.areEqual(1, result.groups[0].rows.size(), 'inactive row must be excluded');
    Assert.areEqual('Trustee Person', result.groups[0].rows[0].relatedAccountName);
    Assert.areEqual('Grantor', result.groups[1].label);
    Assert.areEqual(1, result.groups[1].rows.size());
    Assert.areEqual('Grantor Person', result.groups[1].rows[0].relatedAccountName);
  }

  @IsTest
  static void returnsExecutorForEstate() {
    Account estateAccount = [SELECT Id FROM Account WHERE Name = 'Test Estate' LIMIT 1];

    Test.startTest();
    ArcAccountRelationshipsController.RelationshipsResult result = ArcAccountRelationshipsController.getRelationships(
      estateAccount.Id
    );
    Test.stopTest();

    Assert.areEqual('Estate', result.category);
    Assert.areEqual(1, result.groups.size());
    Assert.areEqual('Executor', result.groups[0].label);
    Assert.areEqual(1, result.groups[0].rows.size());
    Assert.areEqual('Executor Person', result.groups[0].rows[0].relatedAccountName);
  }

  @IsTest
  static void returnsBusinessBucketsIncludingEmptyOnes() {
    Account businessAccount = [SELECT Id FROM Account WHERE Name = 'Test Business' LIMIT 1];

    Test.startTest();
    ArcAccountRelationshipsController.RelationshipsResult result = ArcAccountRelationshipsController.getRelationships(
      businessAccount.Id
    );
    Test.stopTest();

    Assert.areEqual('Business', result.category);
    Assert.areEqual(3, result.groups.size(), 'Control Person, Beneficial Owner, Authorized Person, always all three');

    Map<String, ArcAccountRelationshipsController.RelationshipGroup> byLabel = new Map<String, ArcAccountRelationshipsController.RelationshipGroup>();
    for (ArcAccountRelationshipsController.RelationshipGroup relationshipGroup : result.groups) {
      byLabel.put(relationshipGroup.label, relationshipGroup);
    }

    Assert.areEqual(1, byLabel.get('Beneficial Owner').rows.size());
    Assert.areEqual(0, byLabel.get('Control Person').rows.size(), 'empty bucket must still be returned');
    Assert.areEqual(0, byLabel.get('Authorized Person').rows.size());
  }

  @IsTest
  static void returnsTrustedContactForIndividual() {
    Account individualAccount = [SELECT Id FROM Account WHERE Name = 'Test Individual' LIMIT 1];

    Test.startTest();
    ArcAccountRelationshipsController.RelationshipsResult result = ArcAccountRelationshipsController.getRelationships(
      individualAccount.Id
    );
    Test.stopTest();

    Assert.areEqual('Individual', result.category);
    Assert.areEqual(1, result.groups.size());
    Assert.areEqual('Trusted Contact', result.groups[0].label);
    Assert.areEqual(1, result.groups[0].rows.size());
  }

  @IsTest
  static void returnsEmptyForUnsupportedRecordTypeAndNullOrMissingId() {
    Account householdAccount = [SELECT Id FROM Account WHERE Name = 'Test Household' LIMIT 1];

    Test.startTest();
    ArcAccountRelationshipsController.RelationshipsResult householdResult = ArcAccountRelationshipsController.getRelationships(
      householdAccount.Id
    );
    ArcAccountRelationshipsController.RelationshipsResult nullResult = ArcAccountRelationshipsController.getRelationships(
      null
    );
    Test.stopTest();

    Assert.areEqual('', householdResult.category);
    Assert.isTrue(householdResult.groups.isEmpty());
    Assert.areEqual('', nullResult.category);
    Assert.isTrue(nullResult.groups.isEmpty());
  }
}