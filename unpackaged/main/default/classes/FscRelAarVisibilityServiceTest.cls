/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-19
 */
@IsTest
private class FscRelAarVisibilityServiceTest {
  @IsTest
  static void selectVisibleByAccountIds_returnsRelationsWhenRelatedAccountIsReadable() {
    User ownerUser = createStandardUser();
    User readerUser = createStandardUser();

    Account memberAccount;
    Account relatedAccount;
    Account_Account_Relationship__c relation;

    System.runAs(ownerUser) {
      memberAccount = createPersonAccount('FscAarVisibility Member');
      relatedAccount = createPersonAccount('FscAarVisibility Related');
      relation = insertManagedRelationship(memberAccount.Id, relatedAccount.Id);
    }

    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert new AccountShare(
        AccountId = relatedAccount.Id,
        UserOrGroupId = readerUser.Id,
        AccountAccessLevel = 'Read',
        OpportunityAccessLevel = 'None',
        RowCause = Schema.AccountShare.RowCause.Manual
      );
    }

    Test.startTest();
    List<Account_Account_Relationship__c> visibleRelations;
    System.runAs(readerUser) {
      visibleRelations = FscRelAccountRelationVisibilityService.selectVisibleByAccountIds(
        new Set<Id>{ memberAccount.Id }
      );
    }
    Test.stopTest();

    System.assertEquals(1, visibleRelations.size());
    System.assertEquals(relation.Id, visibleRelations[0].Id);
  }

  @IsTest
  static void selectVisibleByAccountIds_hidesRelationsWithoutRelatedAccountAccess() {
    User ownerUser = createStandardUser();
    User readerUser = createStandardUser();

    Account memberAccount;
    Account relatedAccount;

    System.runAs(ownerUser) {
      memberAccount = createPersonAccount('FscAarVisibility Hidden Member');
      relatedAccount = createPersonAccount('FscAarVisibility Hidden Related');
      insertManagedRelationship(memberAccount.Id, relatedAccount.Id);
    }

    Test.startTest();
    List<Account_Account_Relationship__c> visibleRelations;
    System.runAs(readerUser) {
      visibleRelations = FscRelAccountRelationVisibilityService.selectVisibleByAccountIds(
        new Set<Id>{ memberAccount.Id }
      );
    }
    Test.stopTest();

    System.assertEquals(
      0,
      visibleRelations.size(),
      'Relationships should be hidden when the user cannot read Related_Account__c.'
    );
  }

  @IsTest
  static void selectVisibleByAccountIds_excludesStructuralHouseholdMembershipLinks() {
    User ownerUser = createStandardUser();
    Account householdAccount;
    Account memberAccount;

    System.runAs(ownerUser) {
      householdAccount = createHouseholdAccount('FscAarVisibility Household');
      memberAccount = createPersonAccount('FscAarVisibility Member');
      insert new Account_Account_Relationship__c(
        Account__c = householdAccount.Id,
        Related_Account__c = memberAccount.Id,
        Association_Type__c = 'Member',
        Active__c = true
      );
    }

    Test.startTest();
    List<Account_Account_Relationship__c> outgoingRelations;
    List<Account_Account_Relationship__c> incomingRelations;
    Map<String, Integer> expansionCounts;
    System.runAs(ownerUser) {
      outgoingRelations = FscRelAccountRelationVisibilityService.selectVisibleByAccountIds(
        new Set<Id>{ householdAccount.Id }
      );
      incomingRelations = FscRelAccountRelationVisibilityService.selectVisibleByRelatedAccountIds(
        new Set<Id>{ memberAccount.Id }
      );
      expansionCounts = FscRelAccountRelationVisibilityService.selectVisibleExpansionCountsByAccountIds(
        new Set<Id>{ memberAccount.Id }
      );
    }
    Test.stopTest();

    System.assertEquals(
      0,
      outgoingRelations.size(),
      'Structural household membership links should not appear in map relationship queries.'
    );
    System.assertEquals(
      0,
      incomingRelations.size(),
      'Structural household membership links should not appear when viewed from the member account.'
    );
    System.assertEquals(
      false,
      expansionCounts.containsKey(String.valueOf(memberAccount.Id)),
      'Structural links should not inflate member expansion counts.'
    );
  }

  @IsTest
  static void selectReadableHouseholdMembership_includesStructuralLinksBidirectionally() {
    User ownerUser = createStandardUser();
    Account householdAccount;
    Account memberAccount;

    System.runAs(ownerUser) {
      householdAccount = createHouseholdAccount('FscAarVisibility Membership Household');
      memberAccount = createPersonAccount('FscAarVisibility Membership Member');
      FscDataTestDataFactory.createHouseholdMembershipRelations(
        new List<Account>{ memberAccount },
        householdAccount.Id
      );
    }

    Test.startTest();
    List<Account_Account_Relationship__c> outgoingMembership;
    List<Account_Account_Relationship__c> incomingMembership;
    System.runAs(ownerUser) {
      outgoingMembership = FscRelAccountRelationVisibilityService.selectReadableHouseholdMembershipByHouseholdId(
        householdAccount.Id
      );
      incomingMembership = FscRelAccountRelationVisibilityService.selectReadableHouseholdMembershipByMemberAccountId(
        memberAccount.Id
      );
    }
    Test.stopTest();

    System.assertEquals(
      1,
      outgoingMembership.size(),
      'Household membership read should include structural links from the household.'
    );
    System.assertEquals(
      memberAccount.Id,
      outgoingMembership[0].Related_Account__c
    );
    System.assertEquals(
      1,
      incomingMembership.size(),
      'Household membership read should include structural links from the member account.'
    );
    System.assertEquals(
      householdAccount.Id,
      incomingMembership[0].Account__c,
      'Incoming membership read should expose the household root on Account__c.'
    );
  }

  @IsTest
  static void getMemberAccountRelationshipsForAccounts_usesRelatedAccountVisibility() {
    User ownerUser = createStandardUser();
    User readerUser = createStandardUser();

    Account memberAccount;
    Account relatedAccount;
    Account_Account_Relationship__c relation;

    System.runAs(ownerUser) {
      memberAccount = createPersonAccount('FscAarService Member');
      relatedAccount = createPersonAccount('FscAarService Related');
      relation = insertManagedRelationship(memberAccount.Id, relatedAccount.Id);
    }

    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert new AccountShare(
        AccountId = relatedAccount.Id,
        UserOrGroupId = readerUser.Id,
        AccountAccessLevel = 'Read',
        OpportunityAccessLevel = 'None',
        RowCause = Schema.AccountShare.RowCause.Manual
      );
    }

    Test.startTest();
    List<FscRelHouseholdModels.TreeMemberAccountRelationship> relationships;
    System.runAs(readerUser) {
      relationships = new FscRelHouseholdService()
        .getMemberAccountRelationshipsForAccounts(new Set<Id>{ memberAccount.Id });
    }
    Test.stopTest();

    System.assertEquals(1, relationships.size());
    System.assertEquals(
      String.valueOf(relatedAccount.Id),
      relationships[0].relatedAccountId
    );
    System.assertEquals(relation.Id, Id.valueOf(relationships[0].relationId));
  }

  @IsTest
  static void selectVisibleExpansionCountsByAccountIds_countsManagedRelationships() {
    User ownerUser = createStandardUser();
    Account memberAccount;
    Account relatedAccount;

    System.runAs(ownerUser) {
      memberAccount = createPersonAccount('FscAarVisibility Count Member');
      relatedAccount = createPersonAccount('FscAarVisibility Count Related');
      insertManagedRelationship(memberAccount.Id, relatedAccount.Id);
    }

    Test.startTest();
    Map<String, Integer> expansionCounts;
    List<Account_Account_Relationship__c> emptyAccountResults;
    System.runAs(ownerUser) {
      expansionCounts = FscRelAccountRelationVisibilityService.selectVisibleExpansionCountsByAccountIds(
        new Set<Id>{ memberAccount.Id }
      );
      emptyAccountResults = FscRelAccountRelationVisibilityService.selectVisibleByAccountIds(
        new Set<Id>()
      );
    }
    Test.stopTest();

    System.assertEquals(1, expansionCounts.get(String.valueOf(memberAccount.Id)));
    System.assertEquals(0, emptyAccountResults.size());
  }

  @IsTest
  static void selectVisibleByAccountAndRecordType_returnsManagedRelationshipsOnly() {
    User ownerUser = createStandardUser();
    Account memberAccount;
    Account relatedAccount;
    Account householdAccount;
    String recordTypeDeveloperName;
    Id recordTypeId;

    System.runAs(ownerUser) {
      memberAccount = createPersonAccount('FscAarVisibility RecordType Member');
      relatedAccount = createPersonAccount('FscAarVisibility RecordType Related');
      householdAccount = createHouseholdAccount('FscAarVisibility RecordType Household');
      recordTypeDeveloperName = resolveFirstAccountRelationRecordTypeDeveloperName();
      recordTypeId = FscRelRecordTypeUtils.selectAccountRelationRecordTypeId(
        recordTypeDeveloperName
      );
      insertManagedRelationship(memberAccount.Id, relatedAccount.Id);
      insert new Account_Account_Relationship__c(
        Account__c = householdAccount.Id,
        Related_Account__c = memberAccount.Id,
        RecordTypeId = recordTypeId,
        Association_Type__c = 'Member',
        Active__c = true
      );
    }

    Test.startTest();
    List<Account_Account_Relationship__c> managedRelations;
    List<Account_Account_Relationship__c> incomingManagedRelations;
    System.runAs(ownerUser) {
      managedRelations = FscRelAccountRelationVisibilityService.selectVisibleByAccountAndRecordType(
        memberAccount.Id,
        recordTypeId
      );
      incomingManagedRelations = FscRelAccountRelationVisibilityService.selectVisibleByRelatedAccountAndRecordType(
        relatedAccount.Id,
        recordTypeId
      );
    }
    Test.stopTest();

    System.assertEquals(1, managedRelations.size());
    System.assertEquals(relatedAccount.Id, managedRelations[0].Related_Account__c);
    System.assertEquals(1, incomingManagedRelations.size());
    System.assertEquals(memberAccount.Id, incomingManagedRelations[0].Account__c);
  }

  @IsTest
  static void isRelationshipMapManagedRelation_requiresReciprocalRole() {
    Account_Account_Relationship__c structuralRelation = new Account_Account_Relationship__c(
      Active__c = true
    );
    Account_Account_Relationship__c managedRelation = new Account_Account_Relationship__c(
      Active__c = true,
      Reciprocal_Role__c = UserInfo.getUserId()
    );

    System.assertEquals(
      false,
      FscRelAccountRelationVisibilityService.isRelationshipMapManagedRelation(
        structuralRelation
      )
    );
    System.assertEquals(
      true,
      FscRelAccountRelationVisibilityService.isRelationshipMapManagedRelation(
        managedRelation
      )
    );
    System.assertEquals(
      0,
      FscRelAccountRelationVisibilityService.filterToRelationshipMapManagedRelations(
          new List<Account_Account_Relationship__c>{ structuralRelation }
        )
        .size()
    );
    System.assertEquals(
      1,
      FscRelAccountRelationVisibilityService.filterToRelationshipMapManagedRelations(
          new List<Account_Account_Relationship__c>{ managedRelation }
        )
        .size()
    );
  }

  @IsTest
  static void selectVisibleExpansionCountsByAccountIds_countsUniqueRelatedAccounts() {
    User ownerUser = createStandardUser();
    Account memberAccount;
    Account relatedAccount;

    System.runAs(ownerUser) {
      memberAccount = createPersonAccount('FscAarVisibility Unique Member');
      relatedAccount = createPersonAccount('FscAarVisibility Unique Related');
      insertManagedRelationship(memberAccount.Id, relatedAccount.Id);
      insertManagedRelationshipWithRoles(
        memberAccount.Id,
        relatedAccount.Id,
        'Unique Grantor',
        'Unique Principal'
      );
    }

    Test.startTest();
    Map<String, Integer> expansionCounts;
    System.runAs(ownerUser) {
      expansionCounts = FscRelAccountRelationVisibilityService.selectVisibleExpansionCountsByAccountIds(
        new Set<Id>{ memberAccount.Id }
      );
    }
    Test.stopTest();

    System.assertEquals(
      1,
      expansionCounts.get(String.valueOf(memberAccount.Id)),
      'Duplicate relationships to the same related account should count once.'
    );
  }

  private static Account_Account_Relationship__c insertManagedRelationshipWithRoles(
    Id memberAccountId,
    Id relatedAccountId,
    String memberRoleName,
    String relatedRoleName
  ) {
    String recordTypeDeveloperName = resolveFirstAccountRelationRecordTypeDeveloperName();
    Reciprocal_Role__c role = FscDataTestDataFactory.createReciprocalRoleForMemberRelationship(
      recordTypeDeveloperName,
      memberRoleName,
      relatedRoleName
    );
    Id recordTypeId = FscRelRecordTypeUtils.selectAccountRelationRecordTypeId(
      recordTypeDeveloperName
    );

    Account_Account_Relationship__c relation = new Account_Account_Relationship__c(
      Account__c = memberAccountId,
      Related_Account__c = relatedAccountId,
      RecordTypeId = recordTypeId,
      Reciprocal_Role__c = role.Id,
      Inverse_Reciprocal_Role__c = role.Id,
      Active__c = true
    );
    insert relation;
    return relation;
  }

  private static Account_Account_Relationship__c insertManagedRelationship(
    Id memberAccountId,
    Id relatedAccountId
  ) {
    String recordTypeDeveloperName = resolveFirstAccountRelationRecordTypeDeveloperName();
    Reciprocal_Role__c role = FscDataTestDataFactory.createReciprocalRoleForMemberRelationship(
      recordTypeDeveloperName,
      'Managed Child',
      'Managed Parent'
    );
    Id recordTypeId = FscRelRecordTypeUtils.selectAccountRelationRecordTypeId(
      recordTypeDeveloperName
    );

    Account_Account_Relationship__c relation = new Account_Account_Relationship__c(
      Account__c = memberAccountId,
      Related_Account__c = relatedAccountId,
      RecordTypeId = recordTypeId,
      Reciprocal_Role__c = role.Id,
      Inverse_Reciprocal_Role__c = role.Id,
      Active__c = true
    );
    insert relation;
    return relation;
  }

  private static String resolveFirstAccountRelationRecordTypeDeveloperName() {
    List<RecordType> recordTypes = [
      SELECT DeveloperName
      FROM RecordType
      WHERE SObjectType = 'Account_Account_Relationship__c' AND IsActive = TRUE
      LIMIT 1
    ];

    return recordTypes.isEmpty() ? null : recordTypes[0].DeveloperName;
  }

  private static User createStandardUser() {
    Profile standardProfile = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Standard User'
      LIMIT 1
    ];

    String suffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));

    User standardUser = new User(
      Alias = ('usr' + suffix).left(8),
      Email = 'fsc.aar.visibility.' + suffix + '@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Visibility ' + suffix,
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = standardProfile.Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      Username = 'fsc.aar.visibility.' + suffix + '@example.com.testclass'
    );
    insert standardUser;
    return standardUser;
  }

  private static Account createPersonAccount(String lastName) {
    Id personAccountRecordTypeId = [
      SELECT Id
      FROM RecordType
      WHERE SObjectType = 'Account' AND IsPersonType = TRUE
      LIMIT 1
    ]
    .Id;

    Account personAccount = new Account(
      LastName = lastName,
      RecordTypeId = personAccountRecordTypeId
    );
    insert personAccount;
    return personAccount;
  }

  private static Account createHouseholdAccount(String name) {
    List<RecordType> householdRecordTypes = [
      SELECT Id
      FROM RecordType
      WHERE
        SObjectType = 'Account'
        AND IsPersonType = FALSE
        AND DeveloperName LIKE '%Household%'
      LIMIT 1
    ];

    Account householdAccount = new Account(Name = name);
    if (!householdRecordTypes.isEmpty()) {
      householdAccount.RecordTypeId = householdRecordTypes[0].Id;
    }
    insert householdAccount;
    return householdAccount;
  }
}