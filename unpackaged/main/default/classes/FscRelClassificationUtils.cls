/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-20
 *
 * Helpers for Account.Classification__c used by the relationship map.
 */
public class FscRelClassificationUtils {
  public static final String COI = 'COI';
  public static final String VENDOR = 'Vendor';
  public static final String UNCLASSIFIED = 'Unclassified';

  public static List<String> parseClassifications(String rawValue) {
    List<String> classifications = new List<String>();

    if (String.isBlank(rawValue)) {
      return classifications;
    }

    for (String value : rawValue.split(';')) {
      String trimmedValue = String.valueOf(value).trim();

      if (String.isNotBlank(trimmedValue)) {
        classifications.add(trimmedValue);
      }
    }

    return classifications;
  }

  public static Boolean includesClassification(
    Account account,
    String classificationValue
  ) {
    if (account == null || String.isBlank(classificationValue)) {
      return false;
    }

    for (String value : parseClassifications(account.Classification__c)) {
      if (classificationValue.equalsIgnoreCase(value)) {
        return true;
      }
    }

    return false;
  }
}