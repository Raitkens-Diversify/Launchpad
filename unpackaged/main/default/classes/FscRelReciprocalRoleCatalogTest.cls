/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-20
 */
@IsTest
private class FscRelReciprocalRoleCatalogTest {
  @IsTest
  static void selectAllowedRoleNamesForAarRecordType_returnsFamilyRoles() {
    Set<String> allowedRoles = FscRelReciprocalRoleCatalog.selectAllowedRoleNamesForAarRecordType(
      FscRelReciprocalRoleCatalog.AAR_PERSONAL_AND_FAMILY
    );

    System.assertEquals(12, allowedRoles.size());
    System.assert(allowedRoles.contains('Child'));
    System.assert(allowedRoles.contains('Spouse — Current'));
    System.assert(allowedRoles.contains('Grandparent (or Great)'));
  }

  @IsTest
  static void selectAllowedRoleNamesForReciprocalRoleRecordType_mapsFamilyRoleRecordType() {
    Set<String> allowedRoles = FscRelReciprocalRoleCatalog.selectAllowedRoleNamesForReciprocalRoleRecordType(
      'Personal_and_Family'
    );

    System.assert(allowedRoles.contains('Parent'));
    System.assert(!allowedRoles.contains('Spouse'));
  }

  @IsTest
  static void ensureRolesExistForAarRecordType_createsMissingRecords() {
    Id familyRecordTypeId = FscRelRecordTypeUtils.selectReciprocalRoleRecordTypeId(
      FscRelReciprocalRoleCatalog.AAR_PERSONAL_AND_FAMILY
    );

    if (familyRecordTypeId == null) {
      return;
    }

    Test.startTest();
    FscRelReciprocalRoleCatalog.ensureRolesExistForAarRecordType(
      FscRelReciprocalRoleCatalog.AAR_PERSONAL_AND_FAMILY
    );
    Test.stopTest();

    Set<String> allowedRoles = FscRelReciprocalRoleCatalog.selectAllowedRoleNamesForAarRecordType(
      FscRelReciprocalRoleCatalog.AAR_PERSONAL_AND_FAMILY
    );
    Integer roleCount = [
      SELECT COUNT()
      FROM Reciprocal_Role__c
      WHERE RecordTypeId = :familyRecordTypeId AND Role__c IN :allowedRoles
    ];

    System.assertEquals(allowedRoles.size(), roleCount);
  }

  @IsTest
  static void selectAllowedRoleNamesForAarRecordType_returnsEmptyForBlankInput() {
    System.assertEquals(
      0,
      FscRelReciprocalRoleCatalog.selectAllowedRoleNamesForAarRecordType(null).size()
    );
    System.assertEquals(
      0,
      FscRelReciprocalRoleCatalog.selectAllowedRoleNamesForAarRecordType('').size()
    );
  }

  @IsTest
  static void selectAllowedRoleNamesForReciprocalRoleRecordType_returnsEmptyForUnknownType() {
    System.assertEquals(
      0,
      FscRelReciprocalRoleCatalog.selectAllowedRoleNamesForReciprocalRoleRecordType(
        'Unknown_Record_Type'
      ).size()
    );
  }

  @IsTest
  static void selectAllowedRoleNamesForAarRecordType_returnsCatalogValuesForCoiAndBusiness() {
    Set<String> coiRoles = FscRelReciprocalRoleCatalog.selectAllowedRoleNamesForAarRecordType(
      FscRelReciprocalRoleCatalog.AAR_COI
    );
    Set<String> businessRoles = FscRelReciprocalRoleCatalog.selectAllowedRoleNamesForAarRecordType(
      FscRelReciprocalRoleCatalog.AAR_BUSINESS
    );

    System.assert(coiRoles.contains('Referrer'));
    System.assert(coiRoles.contains('Referred'));
    System.assert(businessRoles.contains('Employer'));
    System.assert(businessRoles.contains('Business Partner'));
  }

  @IsTest
  static void selectManagedReciprocalRoleRecordTypeDeveloperNames_returnsConfiguredValues() {
    Set<String> recordTypeDeveloperNames = FscRelReciprocalRoleCatalog.selectManagedReciprocalRoleRecordTypeDeveloperNames();

    System.assert(recordTypeDeveloperNames.contains('Business'));
    System.assert(recordTypeDeveloperNames.contains('COI_Referral'));
    System.assert(recordTypeDeveloperNames.contains('Personal_and_Family'));
    System.assert(recordTypeDeveloperNames.contains('Service_Provider'));
  }

  @IsTest
  static void ensureRolesExistForAarRecordType_createsServiceProviderRoles() {
    Id serviceProviderRecordTypeId = FscRelRecordTypeUtils.selectReciprocalRoleRecordTypeId(
      FscRelReciprocalRoleCatalog.AAR_SERVICE_PROVIDER
    );

    if (serviceProviderRecordTypeId == null) {
      return;
    }

    Test.startTest();
    FscRelReciprocalRoleCatalog.ensureRolesExistForAarRecordType(
      FscRelReciprocalRoleCatalog.AAR_SERVICE_PROVIDER
    );
    Test.stopTest();

    Set<String> allowedRoles = FscRelReciprocalRoleCatalog.selectAllowedRoleNamesForAarRecordType(
      FscRelReciprocalRoleCatalog.AAR_SERVICE_PROVIDER
    );
    Integer roleCount = [
      SELECT COUNT()
      FROM Reciprocal_Role__c
      WHERE RecordTypeId = :serviceProviderRecordTypeId AND Role__c IN :allowedRoles
    ];

    System.assertEquals(allowedRoles.size(), roleCount);
    System.assert(allowedRoles.contains('CPA / Accountant'));
    System.assert(allowedRoles.contains('Care Recipient'));
  }

  @IsTest
  static void ensureRolesExistForAarRecordType_createsBusinessRoles() {
    Id businessRecordTypeId = FscRelRecordTypeUtils.selectReciprocalRoleRecordTypeId(
      FscRelReciprocalRoleCatalog.AAR_BUSINESS
    );

    if (businessRecordTypeId == null) {
      return;
    }

    Test.startTest();
    FscRelReciprocalRoleCatalog.ensureRolesExistForAarRecordType(
      FscRelReciprocalRoleCatalog.AAR_BUSINESS
    );
    Test.stopTest();

    Set<String> allowedRoles = FscRelReciprocalRoleCatalog.selectAllowedRoleNamesForAarRecordType(
      FscRelReciprocalRoleCatalog.AAR_BUSINESS
    );
    Integer roleCount = [
      SELECT COUNT()
      FROM Reciprocal_Role__c
      WHERE RecordTypeId = :businessRecordTypeId AND Role__c IN :allowedRoles
    ];

    System.assertEquals(allowedRoles.size(), roleCount);
  }
}