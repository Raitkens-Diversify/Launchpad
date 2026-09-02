/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-11
 */
@IsTest
private class FscRelPicklistServiceTest {
  @IsTest
  static void getAccountRelationRoleNamesForRecordType_returnsCatalogValuesForFiduciaryLegal() {
    Test.startTest();
    List<String> roleNames = FscRelPicklistService.getAccountRelationRoleNamesForRecordType(
      FscRelReciprocalRoleCatalog.AAR_FIDUCIARY_LEGAL
    );
    Test.stopTest();

    System.assert(!roleNames.isEmpty(), 'Expected fiduciary reciprocal role names.');
    System.assert(
      roleNames.contains('Trustee'),
      'Expected Trustee from the reciprocal role catalog.'
    );
  }

  @IsTest
  static void getAccountRelationRoleNamesForRecordType_returnsEmptyForBlankName() {
    Test.startTest();
    List<String> roleNames = FscRelPicklistService.getAccountRelationRoleNamesForRecordType(
      ''
    );
    Test.stopTest();

    System.assertEquals(true, roleNames.isEmpty());
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