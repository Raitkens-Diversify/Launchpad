/**
 * Tests for ArcCostLineItemController, the backend for c/arcFlowCostLineItems.
 *
 * Event_Cost_Line_Item__c stands in for all three allowed objects since the
 * controller treats them identically (same field names, same validation) --
 * the object name itself is the only thing that varies per call site.
 */
@IsTest
private class ArcCostLineItemControllerTest {
  private static final String OBJ = 'Event_Cost_Line_Item__c';

  @IsTest
  static void getLineItemsThrowsForUnsupportedObject() {
    Test.startTest();
    try {
      ArcCostLineItemController.getLineItems('Account', 'flow-1');
      Assert.fail('Expected an exception for an unsupported object');
    } catch (AuraHandledException e) {
      Assert.isTrue(true, 'Unsupported line item object should be rejected');
    }
    Test.stopTest();
  }

  @IsTest
  static void getLineItemsReturnsEmptyForBlankParent() {
    Test.startTest();
    List<Map<String, Object>> rows = ArcCostLineItemController.getLineItems(
      OBJ,
      null
    );
    Test.stopTest();

    Assert.areEqual(
      0,
      rows.size(),
      'A blank parent interview id should return no rows'
    );
  }

  @IsTest
  static void getLineItemsReturnsRowsForTheParent() {
    String flowId = 'flow-interview-123';
    insert new Event_Cost_Line_Item__c(
      Flow_Interview_ID__c = flowId,
      Name_of_Party__c = 'Acme Sponsor',
      Amount__c = 250
    );

    Test.startTest();
    List<Map<String, Object>> rows = ArcCostLineItemController.getLineItems(
      OBJ,
      flowId
    );
    Test.stopTest();

    Assert.areEqual(1, rows.size(), 'One row is parented to this interview');
    Assert.areEqual('Acme Sponsor', rows[0].get('nameOfParty'));
    Assert.areEqual(
      250,
      ((Decimal) rows[0].get('amount')).intValue()
    );
    Assert.isNotNull(rows[0].get('recordId'));
  }

  @IsTest
  static void saveLineItemInsertsANewRow() {
    String flowId = 'flow-interview-456';

    Test.startTest();
    Id savedId = ArcCostLineItemController.saveLineItem(
      OBJ,
      flowId,
      null,
      'New Party',
      100
    );
    Test.stopTest();

    Event_Cost_Line_Item__c saved = [
      SELECT Name_of_Party__c, Amount__c, Flow_Interview_ID__c
      FROM Event_Cost_Line_Item__c
      WHERE Id = :savedId
    ];
    Assert.areEqual('New Party', saved.Name_of_Party__c);
    Assert.areEqual(100, saved.Amount__c.intValue());
    Assert.areEqual(flowId, saved.Flow_Interview_ID__c);
  }

  @IsTest
  static void saveLineItemUpdatesAnExistingRowByRecordId() {
    Event_Cost_Line_Item__c row = new Event_Cost_Line_Item__c(
      Flow_Interview_ID__c = 'flow-interview-789',
      Name_of_Party__c = 'Old Party',
      Amount__c = 50
    );
    insert row;

    Test.startTest();
    Id savedId = ArcCostLineItemController.saveLineItem(
      OBJ,
      'flow-interview-789',
      row.Id,
      'Updated Party',
      75
    );
    Test.stopTest();

    Assert.areEqual(row.Id, savedId, 'Updating returns the same record id');
    Event_Cost_Line_Item__c updated = [
      SELECT Name_of_Party__c, Amount__c
      FROM Event_Cost_Line_Item__c
      WHERE Id = :row.Id
    ];
    Assert.areEqual('Updated Party', updated.Name_of_Party__c);
    Assert.areEqual(75, updated.Amount__c.intValue());
  }

  @IsTest
  static void saveLineItemThrowsWhenParentIsBlank() {
    Test.startTest();
    try {
      ArcCostLineItemController.saveLineItem(OBJ, null, null, 'Party', 10);
      Assert.fail('Expected an exception for a blank parent interview id');
    } catch (AuraHandledException e) {
      Assert.isTrue(true, 'A parent interview id is required to save');
    }
    Test.stopTest();
  }

  @IsTest
  static void deleteLineItemIsANoOpForANullId() {
    Test.startTest();
    ArcCostLineItemController.deleteLineItem(OBJ, null);
    Test.stopTest();

    Assert.isTrue(true, 'No exception means the no-op path ran cleanly');
  }

  @IsTest
  static void deleteLineItemDeletesTheRow() {
    Event_Cost_Line_Item__c row = new Event_Cost_Line_Item__c(
      Flow_Interview_ID__c = 'flow-interview-999',
      Name_of_Party__c = 'Deletable',
      Amount__c = 20
    );
    insert row;

    Test.startTest();
    ArcCostLineItemController.deleteLineItem(OBJ, row.Id);
    Test.stopTest();

    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Event_Cost_Line_Item__c WHERE Id = :row.Id],
      'The row should be gone after delete'
    );
  }

  @IsTest
  static void deleteLineItemThrowsForUnsupportedObjectEvenWithNullId() {
    Test.startTest();
    try {
      ArcCostLineItemController.deleteLineItem('Account', null);
      Assert.fail('Expected an exception for an unsupported object');
    } catch (AuraHandledException e) {
      Assert.isTrue(true, 'Object validation runs before the null-id check');
    }
    Test.stopTest();
  }
}