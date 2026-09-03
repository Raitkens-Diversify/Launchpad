@IsTest
private class ArcAccountRelationshipsControllerTest {
  /**
   * Account.Type on every test account: the Type_OR_Classification_Required
   * validation rule (activated 2026-09-02) rejects a Business, Trust,
   * Retirement Plan or person account that carries neither a Type nor a
   * Classification, which is what broke this class's setup.
   */
  private static final String ACCOUNT_TYPE = 'Prospect';

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
    Id retirementPlanRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get('Retirement_Plan')
      .getRecordTypeId();
    Id fiduciaryRecordTypeId = Schema.SObjectType.Account_Account_Relationship__c.getRecordTypeInfosByDeveloperName()
      .get('Fiduciary_Legal')
      .getRecordTypeId();
    Id householdRelationshipRecordTypeId = Schema.SObjectType.Account_Account_Relationship__c.getRecordTypeInfosByDeveloperName()
      .get('Household')
      .getRecordTypeId();

    Account trustAccount = new Account(Type = ACCOUNT_TYPE, Name = 'Test Trust', RecordTypeId = trustRecordTypeId);
    Account estateAccount = new Account(
      Type = ACCOUNT_TYPE,
      Name = 'Test Estate',
      RecordTypeId = trustRecordTypeId,
      Trust_Type__c = 'Estate'
    );
    Account businessAccount = new Account(Type = ACCOUNT_TYPE, Name = 'Test Business', RecordTypeId = businessRecordTypeId);
    // Diversify_Related_Person is a true Person Account record type -- Name
    // is computed from First/Last, not directly settable.
    Account individualAccount = new Account(
      Type = ACCOUNT_TYPE,
      FirstName = 'Test',
      LastName = 'Individual',
      RecordTypeId = individualRecordTypeId
    );
    Account householdAccount = new Account(Type = ACCOUNT_TYPE, Name = 'Test Household', RecordTypeId = householdRecordTypeId);
    Account retirementPlanAccount = new Account(
      Type = ACCOUNT_TYPE,
      Name = 'Test Retirement Plan',
      RecordTypeId = retirementPlanRecordTypeId
    );
    // The "related person" stand-ins only need to exist and have a Name --
    // their own record type isn't what this test is checking -- so these
    // use the plain Business type rather than fighting Person Account's
    // First/Last-only Name.
    Account trusteePerson = new Account(Type = ACCOUNT_TYPE, Name = 'Trustee Person', RecordTypeId = businessRecordTypeId);
    Account grantorPerson = new Account(Type = ACCOUNT_TYPE, Name = 'Grantor Person', RecordTypeId = businessRecordTypeId);
    Account executorPerson = new Account(Type = ACCOUNT_TYPE, Name = 'Executor Person', RecordTypeId = businessRecordTypeId);
    Account beneficialOwnerPerson = new Account(
      Type = ACCOUNT_TYPE,
      Name = 'Beneficial Owner Person',
      RecordTypeId = businessRecordTypeId
    );
    Account trustedContactPerson = new Account(
      Type = ACCOUNT_TYPE,
      Name = 'Trusted Contact Person',
      RecordTypeId = businessRecordTypeId
    );

    insert new List<Account>{
      trustAccount,
      estateAccount,
      businessAccount,
      individualAccount,
      householdAccount,
      retirementPlanAccount,
      trusteePerson,
      grantorPerson,
      executorPerson,
      beneficialOwnerPerson,
      trustedContactPerson
    };

    // The controller reads a relationship's role off Reciprocal_Role__r.Role__c
    // (the Relationship Map's catalog), so each fiduciary row below points at a
    // catalog entry spelled the way the controller's synonym table expects.
    Reciprocal_Role__c trusteeRole = new Reciprocal_Role__c(Role__c = 'Trustee');
    Reciprocal_Role__c grantorRole = new Reciprocal_Role__c(Role__c = 'Grantor');
    Reciprocal_Role__c executorRole = new Reciprocal_Role__c(Role__c = 'Executor / Personal Representative');
    Reciprocal_Role__c beneficialOwnerRole = new Reciprocal_Role__c(Role__c = 'Beneficial Owner');
    Reciprocal_Role__c trustedContactRole = new Reciprocal_Role__c(Role__c = 'Trusted Contact');
    insert new List<Reciprocal_Role__c>{
      trusteeRole,
      grantorRole,
      executorRole,
      beneficialOwnerRole,
      trustedContactRole
    };

    insert new List<Account_Account_Relationship__c>{
      new Account_Account_Relationship__c(
        Account__c = trustAccount.Id,
        Related_Account__c = trusteePerson.Id,
        Reciprocal_Role__c = trusteeRole.Id,
        RecordTypeId = fiduciaryRecordTypeId,
        Active__c = true
      ),
      new Account_Account_Relationship__c(
        Account__c = trustAccount.Id,
        Related_Account__c = grantorPerson.Id,
        Reciprocal_Role__c = grantorRole.Id,
        RecordTypeId = fiduciaryRecordTypeId,
        Active__c = true
      ),
      new Account_Account_Relationship__c(
        Account__c = estateAccount.Id,
        Related_Account__c = executorPerson.Id,
        Reciprocal_Role__c = executorRole.Id,
        RecordTypeId = fiduciaryRecordTypeId,
        Active__c = true
      ),
      new Account_Account_Relationship__c(
        Account__c = businessAccount.Id,
        Related_Account__c = beneficialOwnerPerson.Id,
        Reciprocal_Role__c = beneficialOwnerRole.Id,
        RecordTypeId = fiduciaryRecordTypeId,
        Active__c = true
      ),
      new Account_Account_Relationship__c(
        Account__c = individualAccount.Id,
        Related_Account__c = trustedContactPerson.Id,
        Reciprocal_Role__c = trustedContactRole.Id,
        RecordTypeId = fiduciaryRecordTypeId,
        Active__c = true
      ),
      // Inactive rows and rows on other record types must never surface.
      new Account_Account_Relationship__c(
        Account__c = trustAccount.Id,
        Related_Account__c = trustedContactPerson.Id,
        Reciprocal_Role__c = trusteeRole.Id,
        RecordTypeId = fiduciaryRecordTypeId,
        Active__c = false
      ),
      // Household membership: household -> member, record type Household, no role.
      new Account_Account_Relationship__c(
        Account__c = householdAccount.Id,
        Related_Account__c = individualAccount.Id,
        RecordTypeId = householdRelationshipRecordTypeId,
        Active__c = true
      ),
      new Account_Account_Relationship__c(
        Account__c = householdAccount.Id,
        Related_Account__c = businessAccount.Id,
        RecordTypeId = householdRelationshipRecordTypeId,
        Active__c = true
      ),
      new Account_Account_Relationship__c(
        Account__c = householdAccount.Id,
        Related_Account__c = trustAccount.Id,
        RecordTypeId = householdRelationshipRecordTypeId,
        Active__c = true
      ),
      // An inactive membership, and a fiduciary row hung off the household,
      // must both stay out of the household's member groups.
      new Account_Account_Relationship__c(
        Account__c = householdAccount.Id,
        Related_Account__c = estateAccount.Id,
        RecordTypeId = householdRelationshipRecordTypeId,
        Active__c = false
      ),
      new Account_Account_Relationship__c(
        Account__c = householdAccount.Id,
        Related_Account__c = trustedContactPerson.Id,
        RecordTypeId = fiduciaryRecordTypeId,
        Active__c = true
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
  static void returnsMembersGroupedByTypeForHousehold() {
    Account householdAccount = [SELECT Id FROM Account WHERE Name = 'Test Household' LIMIT 1];

    Test.startTest();
    ArcAccountRelationshipsController.RelationshipsResult result = ArcAccountRelationshipsController.getRelationships(
      householdAccount.Id
    );
    Test.stopTest();

    Assert.areEqual('Household', result.category);
    Assert.areEqual(4, result.groups.size(), 'Members, Businesses, Trusts & Estates, Retirement Plans, always all four');
    Assert.areEqual('Members', result.groups[0].label);
    Assert.areEqual(1, result.groups[0].rows.size());
    Assert.areEqual('Test Individual', result.groups[0].rows[0].relatedAccountName);
    Assert.areEqual('Businesses', result.groups[1].label);
    Assert.areEqual(1, result.groups[1].rows.size(), 'the fiduciary row on the household is not membership');
    Assert.areEqual('Test Business', result.groups[1].rows[0].relatedAccountName);
    Assert.areEqual('Trusts & Estates', result.groups[2].label);
    Assert.areEqual(1, result.groups[2].rows.size(), 'inactive membership must be excluded');
    Assert.areEqual('Test Trust', result.groups[2].rows[0].relatedAccountName);
    Assert.areEqual('Retirement Plans', result.groups[3].label);
    Assert.areEqual(0, result.groups[3].rows.size(), 'empty group must still be returned');
  }

  @IsTest
  static void returnsEmptyForUnsupportedRecordTypeAndNullOrMissingId() {
    Account retirementPlanAccount = [SELECT Id FROM Account WHERE Name = 'Test Retirement Plan' LIMIT 1];

    Test.startTest();
    ArcAccountRelationshipsController.RelationshipsResult unsupportedResult = ArcAccountRelationshipsController.getRelationships(
      retirementPlanAccount.Id
    );
    ArcAccountRelationshipsController.RelationshipsResult nullResult = ArcAccountRelationshipsController.getRelationships(
      null
    );
    Test.stopTest();

    Assert.areEqual('', unsupportedResult.category);
    Assert.isTrue(unsupportedResult.groups.isEmpty());
    Assert.areEqual('', nullResult.category);
    Assert.isTrue(nullResult.groups.isEmpty());
  }
}