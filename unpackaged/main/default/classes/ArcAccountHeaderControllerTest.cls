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
}