/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-19
 */
@IsTest
private class FscRelAccountRelationShareServiceTest {
  @IsTest
  static void syncSharesForRelations_grantsReadAccessFromRelatedAccountShare() {
    User advisor = createAdvisorUser();
    User unrelatedUser = createAdvisorUser();

    Account memberAccount;
    Account relatedAccount;
    Account_Account_Relationship__c relation;

    System.runAs(advisor) {
      memberAccount = createPersonAccount('FscAarShare Member');
      relatedAccount = createPersonAccount('FscAarShare Related');

      insert new AccountShare(
        AccountId = relatedAccount.Id,
        UserOrGroupId = unrelatedUser.Id,
        AccountAccessLevel = 'Read',
        OpportunityAccessLevel = 'None',
        RowCause = Schema.AccountShare.RowCause.Manual
      );
    }

    System.runAs(advisor) {
      relation = new Account_Account_Relationship__c(
        Account__c = memberAccount.Id,
        Related_Account__c = relatedAccount.Id,
        Active__c = true
      );
      insert relation;
    }

    Test.startTest();
    FscRelAccountRelationShareService.syncSharesForRelations(
      new List<Account_Account_Relationship__c>{ relation }
    );
    Test.stopTest();

    System.runAs(unrelatedUser) {
      List<Account_Account_Relationship__c> visibleRelations = [
        SELECT Id
        FROM Account_Account_Relationship__c
        WHERE Id = :relation.Id
      ];

      System.assertEquals(
        1,
        visibleRelations.size(),
        'Users with related account access should be able to read the AAR.'
      );
    }
  }

  @IsTest
  static void accountRelationshipTrigger_syncsSharesOnInsert() {
    User advisor = createAdvisorUser();
    User unrelatedUser = createAdvisorUser();

    Account memberAccount;
    Account relatedAccount;

    System.runAs(advisor) {
      memberAccount = createPersonAccount('FscAarTrigger Member');
      relatedAccount = createPersonAccount('FscAarTrigger Related');

      insert new AccountShare(
        AccountId = relatedAccount.Id,
        UserOrGroupId = unrelatedUser.Id,
        AccountAccessLevel = 'Read',
        OpportunityAccessLevel = 'None',
        RowCause = Schema.AccountShare.RowCause.Manual
      );
    }

    Account_Account_Relationship__c relation;

    Test.startTest();
    System.runAs(advisor) {
      relation = new Account_Account_Relationship__c(
        Account__c = memberAccount.Id,
        Related_Account__c = relatedAccount.Id,
        Active__c = true
      );
      insert relation;
    }
    Test.stopTest();

    System.runAs(unrelatedUser) {
      List<Account_Account_Relationship__c> visibleRelations = [
        SELECT Id
        FROM Account_Account_Relationship__c
        WHERE Id = :relation.Id
      ];

      System.assertEquals(
        1,
        visibleRelations.size(),
        'Trigger should mirror related account sharing onto the AAR.'
      );
    }
  }

  private static User createAdvisorUser() {
    Profile advisorProfile = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Standard User'
      LIMIT 1
    ];

    String suffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));

    User advisorUser = new User(
      Alias = ('adv' + suffix).left(8),
      Email = 'fsc.aar.share.' + suffix + '@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Advisor ' + suffix,
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = advisorProfile.Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      Username = 'fsc.aar.share.' + suffix + '@example.com.testclass'
    );
    insert advisorUser;
    return advisorUser;
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
}