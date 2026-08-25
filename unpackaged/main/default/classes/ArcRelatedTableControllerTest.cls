/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-11
 */
@IsTest
private class ArcRelatedTableControllerTest {
  @IsTest
  static void getTableDataReturnsEnvelopeRowsForMineScope() {
    Envelope__c ownedEnvelope = new Envelope__c(
      Name = 'Mine Envelope',
      Status__c = 'In Progress'
    );
    insert ownedEnvelope;

    Test.startTest();
    ArcRelatedTableModels.TableData result = ArcRelatedTableController.getTableData(
      'Envelope',
      'Mine'
    );
    Test.stopTest();

    System.assertNotEquals(null, result);
    System.assert(result.totalCount >= 1, 'Expected at least one owned envelope.');
    Boolean found = false;
    for (ArcRelatedTableModels.TableRow row : result.rows) {
      if (row.id == String.valueOf(ownedEnvelope.Id)) {
        found = true;
        System.assertEquals('Mine Envelope', row.name);
      }
    }
    System.assertEquals(true, found, 'Owned envelope should be returned.');
  }

  @IsTest
  static void getTableDataRoutesWorkObjectType() {
    Task ownedTask = new Task(
      Subject = 'Mine Task',
      Status = 'Not Started',
      Priority = 'Normal',
      OwnerId = UserInfo.getUserId()
    );
    insert ownedTask;

    Test.startTest();
    ArcRelatedTableModels.TableData result = ArcRelatedTableController.getTableData(
      'Work',
      'Mine'
    );
    Test.stopTest();

    System.assertNotEquals(null, result);
    Boolean foundTask = false;
    for (ArcRelatedTableModels.TableRow row : result.rows) {
      if (row.id == String.valueOf(ownedTask.Id)) {
        foundTask = true;
        System.assertEquals('Task', row.recordType);
        System.assertEquals('Mine Task', row.subject);
      }
    }
    System.assertEquals(true, foundTask, 'Owned task should be returned.');
  }

  @IsTest
  static void getTableDataDefaultsToEnvelopeMine() {
    Test.startTest();
    ArcRelatedTableModels.TableData result = ArcRelatedTableController.getTableData(
      null,
      null
    );
    Test.stopTest();

    System.assertNotEquals(null, result);
    System.assertNotEquals(null, result.rows);
  }
}