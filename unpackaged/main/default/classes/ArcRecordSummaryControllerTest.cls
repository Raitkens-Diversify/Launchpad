/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-13
 */
@IsTest
private class ArcRecordSummaryControllerTest {

  @IsTest
  static void loadReturnsRecordSummaryContext() {
    Account member = new Account(
      FirstName = 'David',
      LastName = 'Harrison',
      Type = 'Active Client',
      RecordTypeId = Schema.SObjectType.Account
        .getRecordTypeInfosByDeveloperName()
        .get('PersonAccount')
        .getRecordTypeId()
    );
    insert member;

    Test.startTest();
    ArcRecordSummaryController.RecordSummaryContext context =
      ArcRecordSummaryController.load(member.Id);
    Test.stopTest();

    System.assertEquals('PersonAccount', context.recordTypeDeveloperName);
    System.assertEquals('Active Client', context.accountType);
    System.assertEquals('Active Client', context.status);
    System.assertNotEquals(null, context.createdDate);
  }

  @IsTest
  static void loadRequiresAccountId() {
    Boolean threw = false;

    try {
      ArcRecordSummaryController.load(null);
    } catch (AuraHandledException error) {
      threw = true;
    }

    System.assertEquals(true, threw, 'Expected required Account Id error.');
  }

  @IsTest
  static void loadRejectsARecordThatIsNotAnAccount() {
    Case aCase = new Case(Subject = 'Not an account', Status = 'New');
    insert aCase;

    Boolean threw = false;
    try {
      ArcRecordSummaryController.load(aCase.Id);
    } catch (AuraHandledException error) {
      threw = true;
    }

    Assert.isTrue(threw, 'A non-Account record Id must be rejected.');
  }

  @IsTest
  static void loadThrowsWhenAccountNotFound() {
    Account transient = new Account(Name = 'Transient Account', Type = 'Prospect');
    insert transient;
    Id deletedId = transient.Id;
    delete transient;

    Boolean threw = false;
    try {
      ArcRecordSummaryController.load(deletedId);
    } catch (AuraHandledException error) {
      threw = true;
    }

    Assert.isTrue(threw, 'A record that no longer exists must be reported as not found.');
  }

  @IsTest
  static void loadResolvesHouseholdAndAdvisorTeamContext() {
    Id householdRecordTypeId = Schema.SObjectType.Account
      .getRecordTypeInfosByDeveloperName()
      .get('Household')
      .getRecordTypeId();
    Id businessRecordTypeId = Schema.SObjectType.Account
      .getRecordTypeInfosByDeveloperName()
      .get('Business')
      .getRecordTypeId();

    Account household = new Account(
      Name = 'Harrison Household',
      Type = 'Prospect',
      RecordTypeId = householdRecordTypeId
    );
    insert household;

    // Financial_Advisor_Team_TriggerHandler.updateRepCode (fired indirectly by
    // inserting a team with a Primary Financial Advisor, through the team
    // member automation) does a strict `= [SELECT ... WHERE Name = 'Default
    // Team']` with no LIMIT-1 guard, which throws List-has-no-rows in a test
    // context with no such team. Seeding one first (with no advisor of its
    // own, so its own insert does not cascade) lets that query find a row.
    insert new Financial_Advisor_Team__c(Name = 'Default Team');

    Financial_Advisor_Team__c team = new Financial_Advisor_Team__c(
      Name = 'Team Alpha',
      Primary_Financial_Advisor__c = UserInfo.getUserId()
    );
    insert team;

    Account member = new Account(
      Name = 'Harrison Holdings',
      Type = 'Active Client',
      RecordTypeId = businessRecordTypeId,
      Household__c = household.Id,
      Financial_Advisor_Team__c = team.Id
    );
    insert member;

    Account otherParty = new Account(Name = 'Related Party', Type = 'Prospect');
    insert otherParty;

    Reciprocal_Role__c trusteeAndGrantor = new Reciprocal_Role__c(Role__c = 'Trustee;Grantor');
    Reciprocal_Role__c trusteeAgain = new Reciprocal_Role__c(Role__c = 'Trustee;Beneficiary');
    insert new List<Reciprocal_Role__c>{ trusteeAndGrantor, trusteeAgain };

    insert new List<Account_Account_Relationship__c>{
      new Account_Account_Relationship__c(
        Account__c = otherParty.Id,
        Related_Account__c = member.Id,
        Reciprocal_Role__c = trusteeAndGrantor.Id,
        Active__c = true
      ),
      new Account_Account_Relationship__c(
        Account__c = otherParty.Id,
        Related_Account__c = member.Id,
        Reciprocal_Role__c = trusteeAgain.Id,
        Active__c = true
      )
    };

    User runningUser = [
      SELECT FirstName, LastName, Name
      FROM User
      WHERE Id = :UserInfo.getUserId()
    ];
    List<String> nameParts = new List<String>();
    if (String.isNotBlank(runningUser.FirstName)) {
      nameParts.add(runningUser.FirstName.trim());
    }
    if (String.isNotBlank(runningUser.LastName)) {
      nameParts.add(runningUser.LastName.trim());
    }
    String expectedAdvisorName = nameParts.isEmpty()
      ? runningUser.Name
      : String.join(nameParts, ' ');

    Test.startTest();
    ArcRecordSummaryController.RecordSummaryContext context =
      ArcRecordSummaryController.load(member.Id);
    Test.stopTest();

    Assert.areEqual('Business', context.recordTypeDeveloperName);
    Assert.areEqual(household.Id, context.householdId);
    Assert.areEqual('Harrison Household', context.householdName);
    Assert.areEqual(expectedAdvisorName, context.primaryAdvisorName);
    Assert.areEqual('Active Client', context.accountType);

    Set<String> roleSet = new Set<String>(context.roles);
    Assert.isTrue(roleSet.contains('Trustee'), 'Trustee role should be present.');
    Assert.isTrue(roleSet.contains('Grantor'), 'Grantor role should be present.');
    Assert.isTrue(roleSet.contains('Beneficiary'), 'Beneficiary role should be present.');
    Assert.areEqual(
      3,
      context.roles.size(),
      'The duplicate Trustee role across both relationships should be de-duplicated.'
    );
  }
}