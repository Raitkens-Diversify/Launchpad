/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-21
 */
@IsTest
private class FscRelRecordTypeUtilsTest {
  @IsTest
  static void selectActiveAccountRelationRecordTypes_returnsOptions() {
    Test.startTest();
    List<FscRelHouseholdModels.RecordTypeOption> options = FscRelRecordTypeUtils.selectActiveAccountRelationRecordTypes();
    Test.stopTest();

    System.assert(!options.isEmpty(), 'Expected at least one AAR record type.');
  }

  @IsTest
  static void selectManageableAccountRelationRecordTypes_excludesHouseholdRecordType() {
    Test.startTest();
    List<FscRelHouseholdModels.RecordTypeOption> options = FscRelRecordTypeUtils.selectManageableAccountRelationRecordTypes();
    Test.stopTest();

    for (FscRelHouseholdModels.RecordTypeOption option : options) {
      System.assertNotEquals(
        FscRelRecordTypeUtils.HOUSEHOLD_AAR_RECORD_TYPE,
        option.developerName,
        'Household membership record type should not appear in relationship-map actions.'
      );
    }
  }

  @IsTest
  static void normalizeAccountRelationRecordTypeDeveloperName_trimsInput() {
    System.assertEquals(
      'COI_Referral',
      FscRelRecordTypeUtils.normalizeAccountRelationRecordTypeDeveloperName(
        ' COI_Referral '
      )
    );
  }

  @IsTest
  static void resolveReciprocalRoleDeveloperName_matchesCustomMetadataMappings() {
    FscRelRecordTypeUtils.resetMappingCacheForTest();

    System.assertEquals(
      'Personal_and_Family',
      FscRelRecordTypeUtils.resolveReciprocalRoleDeveloperName(
        'Personal_and_Family'
      )
    );
    System.assertEquals(
      'COI_Referral',
      FscRelRecordTypeUtils.resolveReciprocalRoleDeveloperName('COI_Referral')
    );
    System.assertEquals(
      'Business',
      FscRelRecordTypeUtils.resolveReciprocalRoleDeveloperName('Business')
    );
  }

  @IsTest
  static void resolveReciprocalRoleDeveloperNames_includesFiduciaryFallbacks() {
    FscRelRecordTypeUtils.resetMappingCacheForTest();

    Set<String> developerNames = FscRelRecordTypeUtils.resolveReciprocalRoleDeveloperNames(
      'Fiduciary_Legal'
    );

    System.assert(developerNames.contains('Fiduciary_Legal'));
    System.assert(developerNames.contains('Contact'));
    System.assert(developerNames.contains('Personal_and_Family'));
  }

  @IsTest
  static void selectReciprocalRoleRecordTypeId_resolvesServiceProviderRecordType() {
    Id serviceProviderRoleId = FscRelRecordTypeUtils.selectReciprocalRoleRecordTypeId(
      'Service_Provider'
    );
    if (serviceProviderRoleId == null) {
      return;
    }

    RecordType resolvedRecordType = [
      SELECT DeveloperName
      FROM RecordType
      WHERE Id = :serviceProviderRoleId
      LIMIT 1
    ];

    System.assertEquals('Service_Provider', resolvedRecordType.DeveloperName);
  }

  @IsTest
  static void selectDefaultAccountRecordTypeId_returnsPersonAccountRecordType() {
    Test.startTest();
    Id defaultPersonRecordTypeId = FscRelRecordTypeUtils.selectDefaultAccountRecordTypeId(
      true
    );
    Test.stopTest();

    System.assertNotEquals(null, defaultPersonRecordTypeId);
  }

  @IsTest
  static void selectCreateableRecordTypes_returnsAccountOptions() {
    Test.startTest();
    List<FscRelHouseholdModels.CreateRecordTypeOption> options = FscRelRecordTypeUtils.selectCreateableRecordTypes(
      'Account'
    );
    Test.stopTest();

    System.assert(!options.isEmpty(), 'Expected creatable Account record types.');

    for (FscRelHouseholdModels.CreateRecordTypeOption option : options) {
      System.assert(String.isNotBlank(option.label));
      System.assert(String.isNotBlank(option.recordTypeId));
    }
  }

  @IsTest
  static void selectCreateableRecordTypes_returnsEmptyForBlankObject() {
    System.assertEquals(
      0,
      FscRelRecordTypeUtils.selectCreateableRecordTypes('').size()
    );
  }

  @IsTest
  static void selectRecordTypeByDeveloperName_returnsMatchingRecordType() {
    Test.startTest();
    RecordType personRecordType = FscRelRecordTypeUtils.selectRecordTypeByDeveloperName(
      'Account',
      'PersonAccount'
    );
    RecordType missingRecordType = FscRelRecordTypeUtils.selectRecordTypeByDeveloperName(
      '',
      'PersonAccount'
    );
    Test.stopTest();

    System.assert(
      personRecordType == null || personRecordType.DeveloperName == 'PersonAccount'
    );
    System.assertEquals(null, missingRecordType);
  }
}