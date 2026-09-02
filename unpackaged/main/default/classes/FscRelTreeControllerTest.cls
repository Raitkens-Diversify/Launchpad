/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-01
 */
@IsTest
private class FscRelTreeControllerTest {
  @TestSetup
  static void setup() {
    FscDataTestDataFactory.createTreeScenario();
  }

  @IsTest
  static void resolveRootAccountId_nullAccountId_returnsEmptyResult() {
    Test.startTest();
    FscRelHouseholdModels.RootAccountResolveResult result = FscRelTreeController.resolveRootAccountId(
      null
    );
    Test.stopTest();

    System.assertEquals(false, result.isPersonAccount);
    System.assertEquals(null, result.rootAccountId);
  }

  @IsTest
  static void resolveRootAccountId_rootAccount_returnsSelf() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();

    Test.startTest();
    FscRelHouseholdModels.RootAccountResolveResult result = FscRelTreeController.resolveRootAccountId(
      scenario.rootAccount.Id
    );
    Test.stopTest();

    System.assertEquals(false, result.isPersonAccount);
    System.assertEquals(scenario.rootAccount.Id, result.rootAccountId);
  }

  @IsTest
  static void resolveRootAccountId_linkedPerson_returnsRootAccount() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();

    Test.startTest();
    FscRelHouseholdModels.RootAccountResolveResult result = FscRelTreeController.resolveRootAccountId(
      scenario.linkedPersonAccount.Id
    );
    Test.stopTest();

    System.assertEquals(true, result.isPersonAccount);
    System.assertEquals(scenario.rootAccount.Id, result.rootAccountId);
  }

  @IsTest
  static void resolveRootAccountId_householdLinkedEntity_returnsHouseholdRoot() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();

    update new Account(
      Id = scenario.relatedBusinessAccount.Id,
      Household__c = scenario.rootAccount.Id,
      Classification__c = FscRelClassificationUtils.UNCLASSIFIED
    );

    Test.startTest();
    FscRelHouseholdModels.RootAccountResolveResult result = FscRelTreeController.resolveRootAccountId(
      scenario.relatedBusinessAccount.Id
    );
    Test.stopTest();

    System.assertEquals(false, result.isPersonAccount);
    System.assertEquals(
      scenario.rootAccount.Id,
      result.rootAccountId,
      'Expected household-linked entity accounts to resolve to their household root.'
    );
  }

  @IsTest
  static void getRelationshipTree_fromHouseholdLinkedEntity_includesClassifiedAccount() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();

    update new Account(
      Id = scenario.relatedBusinessAccount.Id,
      Household__c = scenario.rootAccount.Id,
      Classification__c = FscRelClassificationUtils.UNCLASSIFIED
    );

    Test.startTest();
    FscRelHouseholdModels.RootAccountResolveResult resolveResult = FscRelTreeController.resolveRootAccountId(
      scenario.relatedBusinessAccount.Id
    );
    FscRelHouseholdModels.RelationshipTreeData treeData = FscRelTreeController.getRelationshipTree(
      resolveResult.rootAccountId
    );
    Test.stopTest();

    Boolean includesLinkedEntity = false;

    for (FscRelHouseholdModels.TreeAccount classifiedAccount : treeData.classifiedAccounts) {
      if (
        classifiedAccount.accountId ==
        String.valueOf(scenario.relatedBusinessAccount.Id)
      ) {
        includesLinkedEntity = true;
        break;
      }
    }

    System.assertEquals(
      true,
      includesLinkedEntity,
      'Expected household-linked classified accounts on the household tree.'
    );
  }

  @IsTest
  static void resolveRootAccountId_prefersHouseholdFieldOverPrimaryGroup() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();

    update new Account(
      Id = scenario.linkedPersonAccount.Id,
      Household__c = scenario.secondRootAccount.Id
    );

    Test.startTest();
    FscRelHouseholdModels.RootAccountResolveResult result = FscRelTreeController.resolveRootAccountId(
      scenario.linkedPersonAccount.Id
    );
    Test.stopTest();

    System.assertEquals(true, result.isPersonAccount);
    System.assertEquals(
      scenario.secondRootAccount.Id,
      result.rootAccountId,
      'Expected person account Household__c to win over primary group membership.'
    );
  }

  @IsTest
  static void getPersonAccountMapTree_returnsPersonMemberNode() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();

    Test.startTest();
    FscRelHouseholdModels.RelationshipTreeData treeData = FscRelTreeController.getPersonAccountMapTree(
      scenario.unlinkedPersonAccount.Id
    );
    Test.stopTest();

    System.assertEquals(
      String.valueOf(scenario.unlinkedPersonAccount.Id),
      treeData.rootAccountId
    );
    System.assertEquals(1, treeData.members.size());
    System.assertEquals(
      scenario.unlinkedPersonAccount.Name,
      treeData.members[0].name
    );
  }

  @IsTest
  static void resolveRootAccountId_unlinkedPerson_returnsNullRoot() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();

    Test.startTest();
    FscRelHouseholdModels.RootAccountResolveResult result = FscRelTreeController.resolveRootAccountId(
      scenario.unlinkedPersonAccount.Id
    );
    Test.stopTest();

    System.assertEquals(true, result.isPersonAccount);
    System.assertEquals(null, result.rootAccountId);
  }

  @IsTest
  static void getRelationshipTree_returnsMembersForRootAccount() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();

    Test.startTest();
    FscRelHouseholdModels.RelationshipTreeData treeData = FscRelTreeController.getRelationshipTree(
      scenario.rootAccount.Id
    );
    Test.stopTest();

    System.assertEquals(String.valueOf(scenario.rootAccount.Id), treeData.rootAccountId);
    System.assertEquals(scenario.rootAccount.Name, treeData.name);
    System.assertEquals(2, treeData.members.size());
    System.assertEquals(2, treeData.clientAccounts.size());

    FscRelHouseholdModels.TreeMember linkedMember;
    for (FscRelHouseholdModels.TreeMember member : treeData.members) {
      if (member.accountId == String.valueOf(scenario.linkedPersonAccount.Id)) {
        linkedMember = member;
        break;
      }
    }

    System.assertNotEquals(null, linkedMember);
    System.assertEquals(
      String.valueOf(scenario.linkedPersonAccount.Id),
      linkedMember.accountId
    );
  }

  @IsTest
  static void getRelationshipTree_returnsRelatedAccountsForRootAccount() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();

    Test.startTest();
    FscRelHouseholdModels.RelationshipTreeData treeData = FscRelTreeController.getRelationshipTree(
      scenario.rootAccount.Id
    );
    Test.stopTest();

    FscRelHouseholdModels.TreeAccount relatedBusinessAccount;
    for (FscRelHouseholdModels.TreeAccount relatedAccount : treeData.relatedAccounts) {
      if (
        relatedAccount.accountId ==
        String.valueOf(scenario.relatedBusinessAccount.Id)
      ) {
        relatedBusinessAccount = relatedAccount;
        break;
      }
    }

    System.assertNotEquals(
      null,
      relatedBusinessAccount,
      'Expected the business related account on the household tree.'
    );
    System.assertEquals(
      new List<String>(),
      relatedBusinessAccount.roles,
      'Business relationships without reciprocal roles should expose an empty role list.'
    );
  }

  @IsTest
  static void getRelationshipTree_nullRootAccountId_throwsHandledException() {
    Boolean threwException = false;

    Test.startTest();
    try {
      FscRelTreeController.getRelationshipTree(null);
    } catch (Exception error) {
      threwException = true;
    }
    Test.stopTest();

    System.assertEquals(true, threwException);
  }

  @IsTest
  static void refreshPersonAccountMapTree_returnsPersonCentricTree() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();

    Test.startTest();
    FscRelHouseholdModels.RelationshipTreeData treeData = FscRelTreeController.refreshPersonAccountMapTree(
      scenario.linkedPersonAccount.Id
    );
    Test.stopTest();

    System.assertNotEquals(null, treeData);
  }
}