/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-18
 */
@IsTest
private class ArcListViewControllerTest {
  @IsTest
  static void resolveReferenceLabelsReturnsAccountNames() {
    Account account = new Account(Name = 'Lookup Test Account', Type = 'Prospect', Classification__c = 'Unclassified');
    insert account;

    Test.startTest();
    Map<String, String> labelsById = ArcListViewController.resolveReferenceLabels(
      new List<String>{ String.valueOf(account.Id) }
    );
    Test.stopTest();

    System.assertEquals(
      'Lookup Test Account',
      labelsById.get(String.valueOf(account.Id))
    );
  }

  @IsTest
  static void resolveReferenceLabelsIgnoresInvalidIds() {
    Test.startTest();
    Map<String, String> labelsById = ArcListViewController.resolveReferenceLabels(
      new List<String>{ '', 'not-an-id' }
    );
    Test.stopTest();

    System.assertEquals(true, labelsById.isEmpty());
  }

  @IsTest
  static void resolveRecordTypeLabelsReturnsActiveRecordTypeName() {
    Schema.DescribeSObjectResult accountDescribe = Account.SObjectType.getDescribe();
    Id recordTypeId;
    String expectedName;

    for (Schema.RecordTypeInfo recordTypeInfo : accountDescribe.getRecordTypeInfos()) {
      if (
        recordTypeInfo.isActive() &&
        recordTypeInfo.getRecordTypeId() != null &&
        !recordTypeInfo.isMaster()
      ) {
        recordTypeId = recordTypeInfo.getRecordTypeId();
        expectedName = recordTypeInfo.getName();
        break;
      }
    }

    if (recordTypeId == null) {
      return;
    }

    Test.startTest();
    Map<String, String> labelsById = ArcListViewController.resolveRecordTypeLabels(
      'Account',
      new List<String>{ String.valueOf(recordTypeId) }
    );
    Test.stopTest();

    System.assertEquals(
      expectedName,
      labelsById.get(String.valueOf(recordTypeId))
    );
  }
}