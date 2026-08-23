/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-15
 *
 * Repository for Reciprocal_Role__c search and reads.
 */
public without sharing class FscRelReciprocalRoleRepository {
  public static final String CONTACT_RECORD_TYPE_DEVELOPER_NAME = 'Personal_and_Family';

  public List<Reciprocal_Role__c> searchByTerm(String searchTerm, Integer rowLimit) {
    return searchByTerm(searchTerm, null, rowLimit);
  }

  public List<Reciprocal_Role__c> searchByTerm(
    String searchTerm,
    Id recordTypeId,
    Integer rowLimit
  ) {
    if (String.isBlank(searchTerm)) {
      return new List<Reciprocal_Role__c>();
    }

    Integer resolvedLimit = rowLimit == null || rowLimit <= 0 ? 8 : rowLimit;
    String escapedTerm = String.escapeSingleQuotes(searchTerm.trim());
    String likeTerm = '%' + escapedTerm + '%';

    if (recordTypeId == null) {
      return [
        SELECT Id, Name, Role__c, Inverse_Role__c, Inverse_Role__r.Role__c
        FROM Reciprocal_Role__c
        WHERE Role__c LIKE :likeTerm OR Name LIKE :likeTerm
        ORDER BY Role__c, Name
        LIMIT :resolvedLimit
      ];
    }

    return [
      SELECT Id, Name, Role__c, Inverse_Role__c, Inverse_Role__r.Role__c
      FROM Reciprocal_Role__c
      WHERE
        RecordTypeId = :recordTypeId
        AND (Role__c LIKE :likeTerm OR Name LIKE :likeTerm)
      ORDER BY Role__c, Name
      LIMIT :resolvedLimit
    ];
  }

  public List<Reciprocal_Role__c> selectForLookup(Id recordTypeId, Integer rowLimit) {
    Integer resolvedLimit = rowLimit == null || rowLimit <= 0 ? 50 : rowLimit;

    if (recordTypeId == null) {
      return [
        SELECT Id, Name, Role__c, Inverse_Role__c, Inverse_Role__r.Role__c
        FROM Reciprocal_Role__c
        ORDER BY Role__c ASC, Name ASC
        LIMIT :resolvedLimit
      ];
    }

    return [
      SELECT Id, Name, Role__c, Inverse_Role__c, Inverse_Role__r.Role__c
      FROM Reciprocal_Role__c
      WHERE RecordTypeId = :recordTypeId
      ORDER BY Role__c ASC NULLS LAST, Name ASC
      LIMIT :resolvedLimit
    ];
  }

  public void ensureRolesExist(Id recordTypeId, Set<String> roleNames) {
    if (recordTypeId == null || roleNames == null || roleNames.isEmpty()) {
      return;
    }

    Set<String> existingRoleNames = new Set<String>();

    for (Reciprocal_Role__c existingRole : [
      SELECT Role__c
      FROM Reciprocal_Role__c
      WHERE RecordTypeId = :recordTypeId AND Role__c IN :roleNames
    ]) {
      existingRoleNames.add(existingRole.Role__c);
    }

    for (String roleName : roleNames) {
      if (existingRoleNames.contains(roleName)) {
        continue;
      }

      findOrCreateByRoleName(roleName, recordTypeId);
    }
  }

  public List<Reciprocal_Role__c> selectByRecordTypeAndRoleNames(
    Id recordTypeId,
    Set<String> roleNames,
    String searchTerm,
    Integer rowLimit
  ) {
    Integer resolvedLimit = rowLimit == null || rowLimit <= 0 ? 50 : rowLimit;

    if (recordTypeId == null || roleNames == null || roleNames.isEmpty()) {
      return new List<Reciprocal_Role__c>();
    }

    if (String.isBlank(searchTerm)) {
      return [
        SELECT Id, Name, Role__c, Inverse_Role__c, Inverse_Role__r.Role__c
        FROM Reciprocal_Role__c
        WHERE RecordTypeId = :recordTypeId AND Role__c IN :roleNames
        ORDER BY Role__c ASC, Name ASC
        LIMIT :resolvedLimit
      ];
    }

    String escapedTerm = String.escapeSingleQuotes(searchTerm.trim());
    String likeTerm = '%' + escapedTerm + '%';

    return [
      SELECT Id, Name, Role__c, Inverse_Role__c, Inverse_Role__r.Role__c
      FROM Reciprocal_Role__c
      WHERE
        RecordTypeId = :recordTypeId
        AND Role__c IN :roleNames
        AND (Role__c LIKE :likeTerm OR Name LIKE :likeTerm)
      ORDER BY Role__c ASC, Name ASC
      LIMIT :resolvedLimit
    ];
  }

  public Id selectRecordTypeIdForCategory(String aarRecordTypeDeveloperName) {
    return FscRelRecordTypeUtils.selectReciprocalRoleRecordTypeId(
      aarRecordTypeDeveloperName
    );
  }

  public List<Reciprocal_Role__c> findPotentialDuplicates(
    String role,
    Id inverseReciprocalRoleId
  ) {
    String normalizedRole = normalizeValue(role);

    if (String.isBlank(normalizedRole) && inverseReciprocalRoleId == null) {
      return new List<Reciprocal_Role__c>();
    }

    List<Reciprocal_Role__c> matches = new List<Reciprocal_Role__c>();
    for (Reciprocal_Role__c existingRole : selectAllRoles()) {
      if (isPotentialDuplicate(existingRole, normalizedRole, inverseReciprocalRoleId)) {
        matches.add(existingRole);
      }
    }

    return matches;
  }

  public List<Reciprocal_Role__c> findSimilarRoleNames(String role) {
    String normalizedRole = normalizeValue(role);

    if (String.isBlank(normalizedRole)) {
      return new List<Reciprocal_Role__c>();
    }

    List<Reciprocal_Role__c> similarRoles = new List<Reciprocal_Role__c>();

    for (Reciprocal_Role__c existingRole : selectAllRoles()) {
      String existingRoleValue = normalizeValue(existingRole.Role__c);

      if (existingRoleValue == normalizedRole) {
        continue;
      }

      if (isSimilarRoleName(normalizedRole, existingRoleValue)) {
        similarRoles.add(existingRole);
      }
    }

    return similarRoles;
  }

  public Reciprocal_Role__c findByRoleName(String roleName) {
    return findByRoleName(roleName, null);
  }

  public Reciprocal_Role__c findByRoleName(String roleName, Id recordTypeId) {
    if (String.isBlank(roleName)) {
      return null;
    }

    String trimmedRoleName = roleName.trim();

    if (recordTypeId != null) {
      List<Reciprocal_Role__c> typedMatches = [
        SELECT Id, Name, Role__c, RecordTypeId, Inverse_Role__c
        FROM Reciprocal_Role__c
        WHERE RecordTypeId = :recordTypeId AND Role__c = :trimmedRoleName
        LIMIT 1
      ];

      return typedMatches.isEmpty() ? null : typedMatches[0];
    }

    List<Reciprocal_Role__c> matches = [
      SELECT Id, Name, Role__c, RecordTypeId, Inverse_Role__c
      FROM Reciprocal_Role__c
      WHERE Role__c = :trimmedRoleName
      LIMIT 1
    ];

    return matches.isEmpty() ? null : matches[0];
  }

  public Reciprocal_Role__c findOrCreateByRoleName(String roleName, Id recordTypeId) {
    if (String.isBlank(roleName)) {
      return null;
    }

    Reciprocal_Role__c existingRole = findByRoleName(roleName, recordTypeId);
    if (existingRole != null) {
      return existingRole;
    }

    return insertRole(roleName, recordTypeId);
  }

  public Reciprocal_Role__c insertRole(String role, Id recordTypeId) {
    Reciprocal_Role__c reciprocalRole = new Reciprocal_Role__c(
      Role__c = role.trim(),
      RecordTypeId = recordTypeId
    );
    insert reciprocalRole;
    return reciprocalRole;
  }

  public Reciprocal_Role__c insertRoleWithInverseLink(
    String role,
    Id inverseReciprocalRoleId,
    Id recordTypeId
  ) {
    Reciprocal_Role__c reciprocalRole = new Reciprocal_Role__c(
      Role__c = role,
      Inverse_Role__c = inverseReciprocalRoleId,
      RecordTypeId = recordTypeId
    );
    insert reciprocalRole;

    if (inverseReciprocalRoleId != null) {
      update new Reciprocal_Role__c(
        Id = inverseReciprocalRoleId,
        Inverse_Role__c = reciprocalRole.Id
      );
    }

    return reciprocalRole;
  }

  public Id selectContactRecordTypeId() {
    Schema.DescribeSObjectResult describe = Reciprocal_Role__c.SObjectType.getDescribe();
    Map<String, Schema.RecordTypeInfo> nameToRecordTypeInfo = describe.getRecordTypeInfosByDeveloperName();
    List<String> preferredDeveloperNames = new List<String>{
      CONTACT_RECORD_TYPE_DEVELOPER_NAME,
      FscRelRecordTypeUtils.PERSONAL_AND_FAMILY_RECORD_TYPE
    };

    for (String developerName : preferredDeveloperNames) {
      Schema.RecordTypeInfo recordTypeInfo = nameToRecordTypeInfo.get(developerName);
      if (recordTypeInfo != null && recordTypeInfo.isAvailable() && recordTypeInfo.isActive()) {
        return recordTypeInfo.getRecordTypeId();
      }
    }

    for (Schema.RecordTypeInfo recordTypeInfo : nameToRecordTypeInfo.values()) {
      if (recordTypeInfo.isAvailable() && recordTypeInfo.isActive() && recordTypeInfo.isMaster() == false) {
        return recordTypeInfo.getRecordTypeId();
      }
    }

    return null;
  }

  public Reciprocal_Role__c selectById(Id reciprocalRoleId) {
    if (reciprocalRoleId == null) {
      return null;
    }

    List<Reciprocal_Role__c> roles = [
      SELECT
        Id,
        Name,
        Role__c,
        RecordTypeId,
        Inverse_Role__c,
        Inverse_Role__r.Id,
        Inverse_Role__r.Role__c,
        Inverse_Role__r.Name
      FROM Reciprocal_Role__c
      WHERE Id = :reciprocalRoleId
      LIMIT 1
    ];

    return roles.isEmpty() ? null : roles[0];
  }

  public String selectDisplayNameById(Id reciprocalRoleId) {
    Reciprocal_Role__c role = selectById(reciprocalRoleId);
    return resolveDisplayName(role);
  }

  public Map<Id, Reciprocal_Role__c> selectByIds(Set<Id> reciprocalRoleIds) {
    Map<Id, Reciprocal_Role__c> idToRole = new Map<Id, Reciprocal_Role__c>();

    if (reciprocalRoleIds == null || reciprocalRoleIds.isEmpty()) {
      return idToRole;
    }

    for (Reciprocal_Role__c role : [
      SELECT
        Id,
        Name,
        Role__c,
        Inverse_Role__c,
        Inverse_Role__r.Id,
        Inverse_Role__r.Role__c,
        Inverse_Role__r.Name
      FROM Reciprocal_Role__c
      WHERE Id IN :reciprocalRoleIds
    ]) {
      idToRole.put(role.Id, role);
    }

    return idToRole;
  }

  public static String resolveDisplayName(Reciprocal_Role__c role) {
    if (role == null) {
      return '';
    }

    if (!String.isBlank(role.Role__c)) {
      return role.Role__c;
    }

    return role.Name;
  }

  public static String resolveInverseRoleLabel(Reciprocal_Role__c role) {
    if (role == null) {
      return '';
    }

    if (role.Inverse_Role__r != null) {
      return resolveDisplayName(role.Inverse_Role__r);
    }

    return '';
  }

  public static String resolveInverseSubtitle(Reciprocal_Role__c role) {
    String inverseLabel = resolveInverseRoleLabel(role);
    if (String.isBlank(inverseLabel)) {
      return '';
    }

    return 'Inverse: ' + inverseLabel;
  }

  public static Boolean isSimilarRoleName(String normalizedRole, String normalizedExistingRole) {
    if (
      String.isBlank(normalizedRole) ||
      String.isBlank(normalizedExistingRole) ||
      normalizedRole == normalizedExistingRole
    ) {
      return false;
    }

    return containsAsWord(normalizedRole, normalizedExistingRole) ||
      containsAsWord(normalizedExistingRole, normalizedRole);
  }

  public static Boolean containsAsWord(String haystack, String needle) {
    if (String.isBlank(haystack) || String.isBlank(needle) || haystack == needle) {
      return false;
    }

    String escapedNeedle = Pattern.quote(needle);
    Pattern wordPattern = Pattern.compile('(^|\\s)' + escapedNeedle + '(\\s|$)');
    return wordPattern.matcher(haystack).find();
  }

  private List<Reciprocal_Role__c> selectAllRoles() {
    return [
      SELECT
        Id,
        Name,
        Role__c,
        Inverse_Role__c,
        Inverse_Role__r.Id,
        Inverse_Role__r.Role__c,
        Inverse_Role__r.Name,
        RecordTypeId
      FROM Reciprocal_Role__c
      LIMIT 5000
    ];
  }

  private static Boolean isPotentialDuplicate(
    Reciprocal_Role__c existingRole,
    String normalizedRole,
    Id inverseReciprocalRoleId
  ) {
    String existingRoleValue = normalizeValue(existingRole.Role__c);

    if (
      !String.isBlank(normalizedRole) &&
      normalizedRole == existingRoleValue &&
      existingRole.Inverse_Role__c == inverseReciprocalRoleId
    ) {
      return true;
    }

    if (!String.isBlank(normalizedRole) && normalizedRole == existingRoleValue) {
      return true;
    }

    if (inverseReciprocalRoleId != null && existingRole.Inverse_Role__c == inverseReciprocalRoleId) {
      return true;
    }

    if (
      inverseReciprocalRoleId != null &&
      existingRole.Id == inverseReciprocalRoleId &&
      !String.isBlank(normalizedRole) &&
      normalizedRole == existingRoleValue
    ) {
      return true;
    }

    return false;
  }

  private static String normalizeValue(String value) {
    return String.isBlank(value) ? '' : value.trim().toLowerCase();
  }
}