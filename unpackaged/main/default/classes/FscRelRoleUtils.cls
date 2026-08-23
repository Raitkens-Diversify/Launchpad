/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-01
 */
public class FscRelRoleUtils {
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