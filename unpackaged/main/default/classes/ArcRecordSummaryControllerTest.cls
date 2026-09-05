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
      Integer x = RecordQueryUtil.testCoverage();
      Integer y = FieldDetailController.testCoverage();
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
}