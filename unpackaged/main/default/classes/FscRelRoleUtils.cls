/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-01
 */
public class FscRelRoleUtils {
  public static String resolveReciprocalRoleName(
    Account_Account_Relationship__c relation
  ) {
    if (relation == null) {
      return null;
    }

    if (relation.Reciprocal_Role__r != null) {
      String roleName = FscRelReciprocalRoleRepository.resolveDisplayName(
        relation.Reciprocal_Role__r
      );
      if (!String.isBlank(roleName)) {
        return roleName;
      }
    }

    return null;
  }

  public static String resolveRelatedAccountRoleName(
    Account_Account_Relationship__c relation
  ) {
    if (relation == null) {
      return null;
    }

    if (relation.Inverse_Reciprocal_Role__r != null) {
      String inverseRoleName = FscRelReciprocalRoleRepository.resolveDisplayName(
        relation.Inverse_Reciprocal_Role__r
      );
      if (!String.isBlank(inverseRoleName)) {
        return inverseRoleName;
      }
    }

    return resolveReciprocalRoleName(relation);
  }

  public static List<String> parseRoles(String rolesString) {
    List<String> result = new List<String>();
    if (String.isBlank(rolesString)) {
      return result;
    }

    for (String label : rolesString.split(';')) {
      String trimmed = label.trim();
      if (String.isBlank(trimmed)) {
        continue;
      }
      result.add(trimmed);
    }

    return result;
  }

  public static String buildRolesString(List<String> selectedRoles) {
    if (selectedRoles == null || selectedRoles.isEmpty()) {
      return '';
    }

    List<String> values = new List<String>();
    Set<String> seen = new Set<String>();

    for (String value : selectedRoles) {
      if (String.isBlank(value)) {
        continue;
      }

      String trimmed = value.trim();
      if (seen.contains(trimmed)) {
        continue;
      }

      seen.add(trimmed);
      values.add(trimmed);
    }

    return String.join(values, ';');
  }
}