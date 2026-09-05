/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-13
 */
@IsTest
private class ArcAccountHeaderControllerTest {

  @IsTest
  static void loadReturnsPersonAccountHeaderContext() {
    Account member = new Account(
      FirstName = 'Sarah',
      LastName = 'Harrison',
      Type = 'Active Client',
      RecordTypeId = Schema.SObjectType.Account
        .getRecordTypeInfosByDeveloperName()
        .get('PersonAccount')
        .getRecordTypeId()
    );
    insert member;

    Test.startTest();
    ArcAccountHeaderController.AccountHeaderContext context =
      ArcAccountHeaderController.load(member.Id);
    Test.stopTest();

    System.assertEquals(member.Id, context.accountId);
    System.assertEquals('Sarah Harrison', context.name);
    System.assertEquals('PersonAccount', context.recordTypeDeveloperName);
    System.assertEquals('Active Client', context.accountType);
    System.assertEquals(true, context.isPersonAccount);
  }

  @IsTest
  static void loadRequiresAccountId() {
    Boolean threw = false;

    try {
      ArcAccountHeaderController.load(null);
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
      ArcAccountHeaderController.load(aCase.Id);
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
      ArcAccountHeaderController.load(deletedId);
    } catch (AuraHandledException error) {
      threw = true;
    }

    Assert.isTrue(threw, 'A record that no longer exists must be reported as not found.');
  }

  @IsTest
  static void loadReturnsBusinessAccountNameAndMemberRoles() {
    Account business = new Account(Name = 'Harrison Holdings', Type = 'Active Client');
    insert business;

    Account otherParty = new Account(Name = 'Related Party', Type = 'Prospect');
    insert otherParty;

    Reciprocal_Role__c role = new Reciprocal_Role__c(Role__c = 'Beneficial Owner');
    insert role;

    insert new Account_Account_Relationship__c(
      Account__c = otherParty.Id,
      Related_Account__c = business.Id,
      Reciprocal_Role__c = role.Id,
      Active__c = true
    );

    Test.startTest();
    ArcAccountHeaderController.AccountHeaderContext context =
      ArcAccountHeaderController.load(business.Id);
    Test.stopTest();

    Assert.areEqual('Harrison Holdings', context.name, 'A business account keeps its Name.');
    Assert.areEqual(false, context.isPersonAccount);
    Assert.isTrue(
      context.roles.contains('Beneficial Owner'),
      'The active relationship role should surface on the header.'
    );
  }
}