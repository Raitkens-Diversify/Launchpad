/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-11
 */
@IsTest
private class FscRelPicklistServiceTest {
  @IsTest
  static void getAccountAccountRelationshipRoleOptions_returnsActiveValues() {
    Test.startTest();
    List<FscRelHouseholdModels.PicklistOption> options = FscRelPicklistService.getAccountAccountRelationshipRoleOptions();
    Test.stopTest();

    System.assertNotEquals(null, options);
    System.assert(options.size() > 0, 'Expected at least one role picklist value');

    for (FscRelHouseholdModels.PicklistOption option : options) {
      System.assert(String.isNotBlank(option.label));
      System.assert(String.isNotBlank(option.value));
    }
  }

  @IsTest
  static void getAccountRelationRoleNamesForRecordType_returnsValuesForFiduciaryLegal() {
    Test.startTest();
    List<String> roleNames = FscRelPicklistService.getAccountRelationRoleNamesForRecordType(
      'Fiduciary_Legal'
    );
    Test.stopTest();

    System.assert(!roleNames.isEmpty(), 'Expected fiduciary role picklist values.');
    System.assert(
      roleNames.contains('Trustee'),
      'Expected Trustee to be available for Fiduciary / Regulatory.'
    );
  }

  @IsTest
  static void getAccountRelationRoleNamesForRecordType_returnsEmptyForBlankName() {
    Test.startTest();
    List<String> roleNames = FscRelPicklistService.getAccountRelationRoleNamesForRecordType(
      ''
    );
    List<String> picklistValues = FscRelPicklistService.getPicklistValuesForRecordType(
      null,
      null,
      null
    );
    Test.stopTest();

    System.assertEquals(true, roleNames.isEmpty());
    System.assertEquals(true, picklistValues.isEmpty());
  }

  @IsTest
  static void getPicklistValuesForRecordType_returnsFallbackValues() {
    Id recordTypeId = FscRelRecordTypeUtils.selectAccountRelationRecordTypeId(
      FscRelRecordTypeUtils.PERSONAL_AND_FAMILY_RECORD_TYPE
    );
    if (recordTypeId == null) {
      return;
    }

    Test.startTest();
    List<String> values = FscRelPicklistService.getPicklistValuesForRecordType(
      Account_Account_Relationship__c.SObjectType,
      recordTypeId,
      'Roles__c'
    );
    Test.stopTest();

    System.assert(!values.isEmpty());
  }

  @IsTest
  static void getAccountRelationRoleNamesForRecordType_returnsEmptyForUnknownRecordType() {
    Test.startTest();
    List<String> roleNames = FscRelPicklistService.getAccountRelationRoleNamesForRecordType(
      'Unknown_Record_Type'
    );
    Test.stopTest();

    System.assertEquals(true, roleNames.isEmpty());
  }
}