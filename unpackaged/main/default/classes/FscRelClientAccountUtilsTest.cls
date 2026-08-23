/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-17
 */
@IsTest
private class FscRelClientAccountUtilsTest {
  @IsTest
  static void isClientAccount_returnsTrueForSupportedRecordTypesAndTypes() {
    System.assertEquals(
      true,
      FscRelClientAccountUtils.isClientAccount(
        'Person Account',
        'PersonAccount',
        'Active Client'
      )
    );
    System.assertEquals(
      true,
      FscRelClientAccountUtils.isClientAccount(
        'Business',
        'IndustriesBusiness',
        'Former Client'
      )
    );
    System.assertEquals(
      true,
      FscRelClientAccountUtils.isClientAccount(
        'Trust',
        'Trust',
        'Active Client'
      )
    );
    System.assertEquals(
      true,
      FscRelClientAccountUtils.isClientAccount(
        'Retirement Plan',
        'Retirement Plan',
        'Former Client'
      )
    );
  }

  @IsTest
  static void isClientAccount_returnsFalseForUnsupportedValues() {
    System.assertEquals(
      false,
      FscRelClientAccountUtils.isClientAccount(
        'Household',
        'IndustriesHousehold',
        'Active Client'
      )
    );
    System.assertEquals(
      false,
      FscRelClientAccountUtils.isClientAccount(
        'Person Account',
        'PersonAccount',
        null
      )
    );
    System.assertEquals(
      false,
      FscRelClientAccountUtils.isClientAccount(
        'Person Account',
        'PersonAccount',
        'Prospect'
      )
    );
  }

  @IsTest
  static void isLeadProspectAccount_returnsTrueForSupportedRecordTypesAndTypes() {
    System.assertEquals(
      true,
      FscRelClientAccountUtils.isLeadProspectAccount(
        'Person Account',
        'PersonAccount',
        'Prospect'
      )
    );
    System.assertEquals(
      true,
      FscRelClientAccountUtils.isLeadProspectAccount(
        'Business',
        'IndustriesBusiness',
        'Lead'
      )
    );
  }

  @IsTest
  static void isLeadProspectAccount_returnsFalseForUnsupportedValues() {
    System.assertEquals(
      false,
      FscRelClientAccountUtils.isLeadProspectAccount(
        'Person Account',
        'PersonAccount',
        'Active Client'
      )
    );
  }

  @IsTest
  static void resolveClientAccountTypeForDataSetup_returnsOrgValue() {
    String assignableType = FscRelClientAccountUtils.resolveClientAccountTypeForDataSetup();

    if (assignableType == null) {
      return;
    }

    System.assertEquals(true, FscRelClientAccountUtils.isClientAccountType(assignableType));
  }
}