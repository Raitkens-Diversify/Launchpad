/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-22
 */
@IsTest
private class FscRelRelationRepositoryTest {
  @TestSetup
  static void setup() {
    FscDataTestDataFactory.createTreeScenario();
  }

  @IsTest
  static void selectByRootAccount_returnsActiveRelations() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelRelationRepository repository = new FscRelRelationRepository();

    Test.startTest();
    List<AccountContactRelation> relations = repository.selectByRootAccount(
      scenario.rootAccount.Id
    );
    List<AccountContactRelation> emptyResults = repository.selectByRootAccount(null);
    Test.stopTest();

    System.assert(!relations.isEmpty());
    System.assertEquals(true, emptyResults.isEmpty());
  }

  @IsTest
  static void selectByRootAccountAndContact_returnsMatchingRelation() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelRelationRepository repository = new FscRelRelationRepository();

    Test.startTest();
    AccountContactRelation relation = repository.selectByRootAccountAndContact(
      scenario.rootAccount.Id,
      scenario.linkedPersonAccount.PersonContactId
    );
    Test.stopTest();

    System.assertNotEquals(null, relation);
  }

  @IsTest
  static void selectPrimaryGroupByContact_returnsPrimaryGroup() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelRelationRepository repository = new FscRelRelationRepository();

    Test.startTest();
    AccountContactRelation primaryGroup = repository.selectPrimaryGroupByContact(
      scenario.linkedPersonAccount.PersonContactId
    );
    Test.stopTest();

    System.assertNotEquals(null, primaryGroup);
    System.assertEquals(scenario.rootAccount.Id, primaryGroup.AccountId);
  }

  @IsTest
  static void selectActiveGroupsByContact_returnsActiveGroups() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelRelationRepository repository = new FscRelRelationRepository();

    Test.startTest();
    List<AccountContactRelation> groups = repository.selectActiveGroupsByContact(
      scenario.linkedPersonAccount.PersonContactId
    );
    Test.stopTest();

    System.assert(!groups.isEmpty());
  }

  @IsTest
  static void selectPrimaryGroupConflict_returnsNullWhenNoConflict() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelRelationRepository repository = new FscRelRelationRepository();

    Test.startTest();
    AccountContactRelation conflict = repository.selectPrimaryGroupConflict(
      scenario.linkedPersonAccount.PersonContactId,
      scenario.rootAccount.Id
    );
    Test.stopTest();

    System.assertEquals(null, conflict);
  }

  @IsTest
  static void selectOtherPrimaryMembers_returnsOtherPrimaryMembers() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelRelationRepository repository = new FscRelRelationRepository();
    AccountContactRelation keepRelation = repository.selectByRootAccountAndContact(
      scenario.rootAccount.Id,
      scenario.linkedPersonAccount.PersonContactId
    );

    Test.startTest();
    List<AccountContactRelation> otherPrimaryMembers = repository.selectOtherPrimaryMembers(
      scenario.rootAccount.Id,
      keepRelation.Id
    );
    Test.stopTest();

    System.assertEquals(true, otherPrimaryMembers.isEmpty());
  }

  @IsTest
  static void selectByIds_returnsRequestedRelations() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelRelationRepository repository = new FscRelRelationRepository();
    AccountContactRelation relation = repository.selectByRootAccountAndContact(
      scenario.rootAccount.Id,
      scenario.linkedPersonAccount.PersonContactId
    );

    Test.startTest();
    List<AccountContactRelation> relations = repository.selectByIds(
      new List<Id>{ relation.Id }
    );
    List<AccountContactRelation> emptyResults = repository.selectByIds(new List<Id>());
    Test.stopTest();

    System.assertEquals(1, relations.size());
    System.assertEquals(true, emptyResults.isEmpty());
  }

  @IsTest
  static void selectActiveByRootAccounts_returnsActiveRelations() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelRelationRepository repository = new FscRelRelationRepository();

    Test.startTest();
    List<AccountContactRelation> relations = repository.selectActiveByRootAccounts(
      new Set<Id>{ scenario.rootAccount.Id }
    );
    Test.stopTest();

    System.assert(!relations.isEmpty());
  }

  @IsTest
  static void selectActiveMemberCountsByRootAccountIds_returnsMemberCounts() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelRelationRepository repository = new FscRelRelationRepository();

    Test.startTest();
    Map<Id, Integer> memberCounts = repository.selectActiveMemberCountsByRootAccountIds(
      new Set<Id>{ scenario.rootAccount.Id, scenario.secondRootAccount.Id }
    );
    Test.stopTest();

    System.assertEquals(2, memberCounts.get(scenario.rootAccount.Id));
    System.assertEquals(0, memberCounts.get(scenario.secondRootAccount.Id));
  }

  @IsTest
  static void insertUpdateAndDeleteRelation_roundTrip() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelRelationRepository repository = new FscRelRelationRepository();
    AccountContactRelation relation = new AccountContactRelation(
      AccountId = scenario.secondRootAccount.Id,
      ContactId = scenario.unlinkedPersonAccount.PersonContactId,
      Roles = FscDataTestDataFactory.resolveDefaultRoleValue(),
      IsActive = true
    );

    Test.startTest();
    repository.insertRelation(relation);
    relation.Roles = FscDataTestDataFactory.resolveDefaultRoleValue();
    repository.updateRelation(relation);
    Integer deletedCount = repository.deleteRelations(
      new List<AccountContactRelation>{ relation }
    );
    repository.updateRelations(new List<AccountContactRelation>());
    Test.stopTest();

    System.assertEquals(1, deletedCount);
    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM AccountContactRelation
        WHERE Id = :relation.Id
      ]
    );
  }
}