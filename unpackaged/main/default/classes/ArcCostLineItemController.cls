/**
 * Backend for c/arcFlowCostLineItems, the ARC-site replacement for the
 * aura/cmp_FlowCreateMultiple screens in the Advertising Review flows. All
 * three usages are the same shape: rows of Name_of_Party__c + Amount__c on a
 * cost-line object, parented to the running flow interview through
 * Flow_Interview_ID__c so the flow can collect them after the screen.
 */
public with sharing class ArcCostLineItemController {
  private static final Set<String> ALLOWED_OBJECTS = new Set<String>{
    'Event_Cost_Line_Item__c',
    'Radio_TV_Ad_Cost_Line_Item__c',
    'Sponsorship_Cost_Line_Item__c'
  };
  private static final String PARENT_FIELD = 'Flow_Interview_ID__c';
  private static final String NAME_FIELD = 'Name_of_Party__c';
  private static final String AMOUNT_FIELD = 'Amount__c';

  @AuraEnabled
  public static List<Map<String, Object>> getLineItems(String objectApiName, String parentId) {
    validateObject(objectApiName);
    if (String.isBlank(parentId)) {
      return new List<Map<String, Object>>();
    }
    List<Map<String, Object>> rows = new List<Map<String, Object>>();
    for (SObject row : Database.queryWithBinds(
      'SELECT Id, ' + NAME_FIELD + ', ' + AMOUNT_FIELD +
        ' FROM ' + objectApiName +
        ' WHERE ' + PARENT_FIELD + ' = :parentId ORDER BY CreatedDate',
      new Map<String, Object>{ 'parentId' => parentId },
      AccessLevel.USER_MODE
    )) {
      rows.add(
        new Map<String, Object>{
          'recordId' => row.Id,
          'nameOfParty' => row.get(NAME_FIELD),
          'amount' => row.get(AMOUNT_FIELD)
        }
      );
    }
    return rows;
  }

  @AuraEnabled
  public static Id saveLineItem(
    String objectApiName,
    String parentId,
    Id recordId,
    String nameOfParty,
    Decimal amount
  ) {
    validateObject(objectApiName);
    if (String.isBlank(parentId)) {
      throw new AuraHandledException('A parent interview id is required.');
    }

    SObject row = Schema.getGlobalDescribe().get(objectApiName).newSObject();
    if (recordId != null) {
      row.Id = recordId;
    } else {
      row.put(PARENT_FIELD, parentId);
    }
    row.put(NAME_FIELD, nameOfParty);
    row.put(AMOUNT_FIELD, amount);
    upsert row;
    return row.Id;
  }

  @AuraEnabled
  public static void deleteLineItem(String objectApiName, Id recordId) {
    validateObject(objectApiName);
    if (recordId == null) {
      return;
    }
    SObject row = Schema.getGlobalDescribe().get(objectApiName).newSObject(recordId);
    delete row;
  }

  private static void validateObject(String objectApiName) {
    if (!ALLOWED_OBJECTS.contains(objectApiName)) {
      throw new AuraHandledException('Unsupported line item object.');
    }
  }
}