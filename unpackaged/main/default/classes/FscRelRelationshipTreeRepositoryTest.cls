/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-22
 */
@IsTest
private class FscRelRelationshipTreeRepositoryTest {
  @TestSetup
  static void setup() {
    FscDataTestDataFactory.createTreeScenario();
  }

  @IsTest
  static void buildMemberAccountIds_householdLaunch_usesHouseholdClients() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelRelationshipTreeRepository repository = new FscRelRelationshipTreeRepository();

    Test.startTest();
    Set<Id> memberAccountIds = repository.buildMemberAccountIds(
      scenario.rootAccount.Id,
      null,
      true
    );
    Test.stopTest();

    System.assert(memberAccountIds.contains(scenario.linkedPersonAccount.Id));
    System.assert(memberAccountIds.contains(scenario.secondPersonAccount.Id));
    System.assert(!memberAccountIds.contains(scenario.rootAccount.Id));
  }

  @IsTest
  static void buildMemberAccountIds_nonHouseholdLaunch_includesContextClient() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelRelationshipTreeRepository repository = new FscRelRelationshipTreeRepository();

    Test.startTest();
    Set<Id> memberAccountIds = repository.buildMemberAccountIds(
      scenario.rootAccount.Id,
      scenario.linkedPersonAccount.Id,
      false
    );
    Test.stopTest();

    System.assert(memberAccountIds.contains(scenario.linkedPersonAccount.Id));
    System.assert(memberAccountIds.contains(scenario.secondPersonAccount.Id));
  }
}