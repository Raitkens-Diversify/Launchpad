/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-25
 */
@IsTest
private class FscRelAccountRelationRepositoryTest {
  @TestSetup
  static void setup() {
    FscDataTestDataFactory.createTreeScenario();
  }

  @IsTest
  static void selectByAccountAndRecordType_returnsPrimaryRows() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    List<FscRelHouseholdModels.RecordTypeOption> recordTypes = FscRelRecordTypeUtils.selectActiveAccountRelationRecordTypes();
    if (recordTypes.isEmpty()) {
      return;
    }

    Id recordTypeId = FscRelRecordTypeUtils.selectAccountRelationRecordTypeId(
      recordTypes[0].developerName
    );
    Reciprocal_Role__c role = FscDataTestDataFactory.createReciprocalRoleForMemberRelationship(
      recordTypes[0].developerName,
      'Repo Role',
      'Repo Role'
    );
    Account_Account_Relationship__c relationship = new Account_Account_Relationship__c(
      Account__c = scenario.linkedPersonAccount.Id,
      Related_Account__c = scenario.secondPersonAccount.Id,
      RecordTypeId = recordTypeId,
      Reciprocal_Role__c = role.Id,
      Inverse_Reciprocal_Role__c = role.Id,
      Active__c = true
    );
    insert relationship;

    FscRelAccountRelationRepository repository = new FscRelAccountRelationRepository();

    Test.startTest();
    List<Account_Account_Relationship__c> results = repository.selectByAccountAndRecordType(
      scenario.linkedPersonAccount.Id,
      recordTypeId
    );
    Test.stopTest();

    System.assertEquals(1, results.size());
    System.assertEquals(role.Id, results[0].Reciprocal_Role__c);
  }

  @IsTest
  static void selectActiveCountsByAccountIds_returnsActiveCounts() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    List<FscRelHouseholdModels.RecordTypeOption> recordTypes = FscRelRecordTypeUtils.selectActiveAccountRelationRecordTypes();
    if (recordTypes.isEmpty()) {
      return;
    }

    Id recordTypeId = FscRelRecordTypeUtils.selectAccountRelationRecordTypeId(
      recordTypes[0].developerName
    );
    Reciprocal_Role__c role = FscDataTestDataFactory.createReciprocalRoleForMemberRelationship(
      recordTypes[0].developerName,
      'Count Role',
      'Count Role'
    );
    insert new Account_Account_Relationship__c(
      Account__c = scenario.linkedPersonAccount.Id,
      Related_Account__c = scenario.secondPersonAccount.Id,
      RecordTypeId = recordTypeId,
      Reciprocal_Role__c = role.Id,
      Inverse_Reciprocal_Role__c = role.Id,
      Active__c = true
    );

    FscRelAccountRelationRepository repository = new FscRelAccountRelationRepository();

    Test.startTest();
    Map<String, Integer> counts = repository.selectActiveCountsByAccountIds(
      new Set<Id>{ scenario.linkedPersonAccount.Id }
    );
    Test.stopTest();

    System.assertEquals(
      1,
      counts.get(String.valueOf(scenario.linkedPersonAccount.Id))
    );
  }

  @IsTest
  static void selectByRootAccount_returnsPrimaryRows() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelAccountRelationRepository repository = new FscRelAccountRelationRepository();

    Test.startTest();
    List<Account_Account_Relationship__c> results = repository.selectByRootAccount(
      scenario.rootAccount.Id
    );
    Account_Account_Relationship__c relation = repository.selectByRootAccountAndRelatedAccount(
      scenario.rootAccount.Id,
      scenario.relatedBusinessAccount.Id
    );
    Test.stopTest();

    System.assertEquals(1, results.size());
    System.assertNotEquals(null, relation);
  }

  @IsTest
  static void selectByAccountIdsAndRelatedAccountMethods_returnRows() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    List<FscRelHouseholdModels.RecordTypeOption> recordTypes = FscRelRecordTypeUtils.selectActiveAccountRelationRecordTypes();
    if (recordTypes.isEmpty()) {
      return;
    }

    Id recordTypeId = FscRelRecordTypeUtils.selectAccountRelationRecordTypeId(
      recordTypes[0].developerName
    );
    Reciprocal_Role__c role = FscDataTestDataFactory.createReciprocalRoleForMemberRelationship(
      recordTypes[0].developerName,
      'Lookup Role',
      'Lookup Role'
    );
    Account_Account_Relationship__c relationship = new Account_Account_Relationship__c(
      Account__c = scenario.linkedPersonAccount.Id,
      Related_Account__c = scenario.secondPersonAccount.Id,
      RecordTypeId = recordTypeId,
      Reciprocal_Role__c = role.Id,
      Inverse_Reciprocal_Role__c = role.Id,
      Active__c = true
    );
    insert relationship;

    FscRelAccountRelationRepository repository = new FscRelAccountRelationRepository();

    Test.startTest();
    List<Account_Account_Relationship__c> byAccountIds = repository.selectByAccountIds(
      new Set<Id>{ scenario.linkedPersonAccount.Id }
    );
    Account_Account_Relationship__c byPair = repository.selectByAccountRelatedAccountAndRecordType(
      scenario.linkedPersonAccount.Id,
      scenario.secondPersonAccount.Id,
      recordTypeId
    );
    List<Account_Account_Relationship__c> byRelatedAccount = repository.selectByRelatedAccountAndRecordType(
      scenario.secondPersonAccount.Id,
      recordTypeId
    );
    Set<Id> relatedAccountIds = repository.selectRelatedAccountIdsByMemberAccountIds(
      new Set<Id>{ scenario.linkedPersonAccount.Id }
    );
    Map<String, Integer> expansionCounts = repository.selectActiveExpansionCountsByAccountIds(
      new Set<Id>{ scenario.linkedPersonAccount.Id }
    );
    Test.stopTest();

    System.assertEquals(1, byAccountIds.size());
    System.assertNotEquals(null, byPair);
    System.assertEquals(1, byRelatedAccount.size());
    System.assert(relatedAccountIds.contains(scenario.secondPersonAccount.Id));
    System.assert(expansionCounts.containsKey(String.valueOf(scenario.linkedPersonAccount.Id)));
  }

  @IsTest
  static void insertUpdateDeleteRelations_roundTrip() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    List<FscRelHouseholdModels.RecordTypeOption> recordTypes = FscRelRecordTypeUtils.selectActiveAccountRelationRecordTypes();
    if (recordTypes.isEmpty()) {
      return;
    }

    Id recordTypeId = FscRelRecordTypeUtils.selectAccountRelationRecordTypeId(
      recordTypes[0].developerName
    );
    Reciprocal_Role__c role = FscDataTestDataFactory.createReciprocalRoleForMemberRelationship(
      recordTypes[0].developerName,
      'Round Trip Role',
      'Round Trip Role'
    );
    Account_Account_Relationship__c relationship = new Account_Account_Relationship__c(
      Account__c = scenario.linkedPersonAccount.Id,
      Related_Account__c = scenario.unlinkedPersonAccount.Id,
      RecordTypeId = recordTypeId,
      Reciprocal_Role__c = role.Id,
      Inverse_Reciprocal_Role__c = role.Id,
      Active__c = true
    );
    FscRelAccountRelationRepository repository = new FscRelAccountRelationRepository();

    Test.startTest();
    repository.insertRelation(relationship);
    relationship.Active__c = false;
    repository.updateRelation(relationship);
    List<Account_Account_Relationship__c> selected = repository.selectByIds(
      new List<Id>{ relationship.Id }
    );
    Integer deletedCount = repository.deleteRelations(
      new List<Account_Account_Relationship__c>{ relationship }
    );
    Test.stopTest();

    System.assertEquals(1, selected.size());
    System.assertEquals(1, deletedCount);
  }
}