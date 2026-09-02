/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-11
 *
 * Loads picklist metadata for LWC comboboxes without depending on field-level security.
 */
public without sharing class FscRelPicklistService {
  public static List<FscRelHouseholdModels.PicklistOption> getAccountAccountRelationshipRoleOptions() {
    List<FscRelHouseholdModels.PicklistOption> roleOptions = getActivePicklistOptions(
      Account_Account_Relationship__c.Roles__c
    );

    if (!roleOptions.isEmpty()) {
      return roleOptions;
    }

    return getActivePicklistOptions(Account_Account_Relationship__c.Role__c);
  }

  public static List<String> getAccountRelationRoleNamesForRecordType(
    String recordTypeDeveloperName
  ) {
    if (String.isBlank(recordTypeDeveloperName)) {
      return new List<String>();
    }

    Id recordTypeId = FscRelRecordTypeUtils.selectAccountRelationRecordTypeId(
      recordTypeDeveloperName
    );

    if (recordTypeId == null) {
      return new List<String>();
    }

    return getPicklistValuesForRecordType(
      Account_Account_Relationship__c.SObjectType,
      recordTypeId,
      'Role__c'
    );
  }

  public static List<String> getPicklistValuesForRecordType(
    Schema.SObjectType objectType,
    Id recordTypeId,
    String fieldApiName
  ) {
    List<String> values = new List<String>();

    if (objectType == null || recordTypeId == null || String.isBlank(fieldApiName)) {
      return values;
    }

    Schema.SObjectField field = objectType.getDescribe()
      .fields.getMap()
      .get(fieldApiName);

    if (field == null) {
      return values;
    }

    try {
      ConnectApi.PicklistValuesCollection picklistCollection = ConnectApi.RecordUi.getPicklistValuesByRecordType(
        objectType.getDescribe().getName(),
        recordTypeId
      );

      if (
        picklistCollection != null &&
        picklistCollection.picklistFieldValues != null
      ) {
        ConnectApi.PicklistValues picklistValues = picklistCollection.picklistFieldValues.get(
          fieldApiName
        );

        if (picklistValues != null && picklistValues.values != null) {
          for (ConnectApi.PicklistValue picklistValue : picklistValues.values) {
            if (picklistValue == null || String.isBlank(picklistValue.value)) {
              continue;
            }

            values.add(picklistValue.value);
          }
        }
      }
    } catch (Exception ex) {
      values.clear();
    }

    if (!values.isEmpty()) {
      return values;
    }

    return getActivePicklistValueStrings(field);
  }

  private static List<String> getActivePicklistValueStrings(Schema.SObjectField field) {
    List<String> values = new List<String>();

    for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
      if (!entry.isActive()) {
        continue;
      }

      values.add(entry.getValue());
    }

    return values;
  }

  private static List<FscRelHouseholdModels.PicklistOption> getActivePicklistOptions(
    Schema.SObjectField field
  ) {
    List<FscRelHouseholdModels.PicklistOption> options = new List<FscRelHouseholdModels.PicklistOption>();

    if (field == null) {
      return options;
    }

    for (
      Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()
    ) {
      if (!entry.isActive()) {
        continue;
      }

      options.add(
        new FscRelHouseholdModels.PicklistOption(
          entry.getLabel(),
          entry.getValue()
        )
      );
    }

    return options;
  }
}