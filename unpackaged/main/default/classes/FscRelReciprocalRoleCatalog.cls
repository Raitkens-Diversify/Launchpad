/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-20
 *
 * Canonical allowed Reciprocal_Role__c role names by relationship record type.
 * Relationship modals read from Reciprocal_Role__c records, not AAR picklists.
 */
public without sharing class FscRelReciprocalRoleCatalog {
  public static final String AAR_PERSONAL_AND_FAMILY = 'Personal_and_Family';
  public static final String AAR_COI = 'COI_Referral';
  public static final String AAR_SERVICE_PROVIDER = 'Service_Provider';
  public static final String AAR_BUSINESS = 'Business';
  public static final String AAR_FIDUCIARY_LEGAL = 'Fiduciary_Legal';

  public static Set<String> selectAllowedRoleNamesForAarRecordType(
    String aarRecordTypeDeveloperName
  ) {
    if (String.isBlank(aarRecordTypeDeveloperName)) {
      return new Set<String>();
    }

    String normalizedName = FscRelRecordTypeUtils.normalizeAccountRelationRecordTypeDeveloperName(
      aarRecordTypeDeveloperName.trim()
    );
    Set<String> allowedRoles = buildAarRecordTypeToRoleNames().get(normalizedName);

    return allowedRoles == null ? new Set<String>() : allowedRoles.clone();
  }

  public static Set<String> selectAllowedRoleNamesForReciprocalRoleRecordType(
    String reciprocalRoleRecordTypeDeveloperName
  ) {
    if (String.isBlank(reciprocalRoleRecordTypeDeveloperName)) {
      return new Set<String>();
    }

    for (String aarRecordTypeDeveloperName : buildAarRecordTypeToRoleNames().keySet()) {
      String resolvedReciprocalRoleRecordType = FscRelRecordTypeUtils.resolveReciprocalRoleDeveloperName(
        aarRecordTypeDeveloperName
      );

      if (
        reciprocalRoleRecordTypeDeveloperName == aarRecordTypeDeveloperName ||
        reciprocalRoleRecordTypeDeveloperName == resolvedReciprocalRoleRecordType
      ) {
        return selectAllowedRoleNamesForAarRecordType(aarRecordTypeDeveloperName);
      }
    }

    return new Set<String>();
  }

  public static Set<String> selectManagedReciprocalRoleRecordTypeDeveloperNames() {
    Set<String> recordTypeDeveloperNames = new Set<String>();

    for (String aarRecordTypeDeveloperName : buildAarRecordTypeToRoleNames().keySet()) {
      String reciprocalRoleRecordTypeDeveloperName = FscRelRecordTypeUtils.resolveReciprocalRoleDeveloperName(
        aarRecordTypeDeveloperName
      );

      if (!String.isBlank(reciprocalRoleRecordTypeDeveloperName)) {
        recordTypeDeveloperNames.add(reciprocalRoleRecordTypeDeveloperName);
      }

      recordTypeDeveloperNames.add(aarRecordTypeDeveloperName);
    }

    return recordTypeDeveloperNames;
  }

  public static void ensureRolesExistForAarRecordType(
    String aarRecordTypeDeveloperName
  ) {
    Set<String> allowedRoleNames = selectAllowedRoleNamesForAarRecordType(
      aarRecordTypeDeveloperName
    );

    if (allowedRoleNames.isEmpty()) {
      return;
    }

    Id recordTypeId = FscRelRecordTypeUtils.selectReciprocalRoleRecordTypeId(
      aarRecordTypeDeveloperName
    );

    if (recordTypeId == null) {
      return;
    }

    new FscRelReciprocalRoleRepository().ensureRolesExist(
      recordTypeId,
      allowedRoleNames
    );
  }

  public static void syncAllRoles() {
    for (String aarRecordTypeDeveloperName : buildAarRecordTypeToRoleNames().keySet()) {
      ensureRolesExistForAarRecordType(aarRecordTypeDeveloperName);
    }
  }

  private static Map<String, Set<String>> buildAarRecordTypeToRoleNames() {
    Map<String, Set<String>> aarRecordTypeToRoleNames = new Map<String, Set<String>>();

    aarRecordTypeToRoleNames.put(
      AAR_PERSONAL_AND_FAMILY,
      new Set<String>{
        'Child',
        'Spouse — Current',
        'Spouse — Former',
        'Sibling',
        'Aunt',
        'Uncle',
        'Niece',
        'Nephew',
        'Friend',
        'Parent',
        'Grandparent (or Great)',
        'Grandchild (or Great)'
      }
    );

    aarRecordTypeToRoleNames.put(
      AAR_COI,
      new Set<String>{
        'COI / Strategic Partner',
        'Referrer',
        'Referred'
      }
    );

    aarRecordTypeToRoleNames.put(
      AAR_SERVICE_PROVIDER,
      new Set<String>{
        'CPA / Accountant',
        'Attorney — Estate Planning',
        'Attorney — General / Other',
        'Insurance Agent',
        'Mortgage / Lending Officer',
        'Real Estate Agent',
        'Banker',
        'Physician',
        'Caretaker',
        'Client (CPA / Accountant)',
        'Client (Attorney - Estate Planning)',
        'Client (Attorney - General / Other)',
        'Client (Insurance Agent)',
        'Client (Mortgage / Lending Officer)',
        'Client (Real Estate Agent)',
        'Client (Banker)',
        'Patient (Physician)',
        'Care Recipient'
      }
    );

    aarRecordTypeToRoleNames.put(
      AAR_BUSINESS,
      new Set<String>{
        'Employer',
        'Business Partner',
        'Co-worker / Colleague'
      }
    );

    aarRecordTypeToRoleNames.put(
      AAR_FIDUCIARY_LEGAL,
      new Set<String>{
        'Trustee',
        'Authorized Individual',
        'Beneficial Owner',
        'Control Person',
        'Power of Attorney',
        'Guardian / Conservator',
        'Custodian (Minor)',
        'Executor / Personal Representative',
        'Trusted Contact',
        '529 Beneficiary',
        'Plan Participant',
        'Plan Administrator',
        'Trust Beneficiary',
        'Account Beneficiary'
      }
    );

    return aarRecordTypeToRoleNames;
  }
}