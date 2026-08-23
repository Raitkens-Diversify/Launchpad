/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-20
 */
@IsTest
private class FscRelClassificationUtilsTest {
  @IsTest
  static void parseClassifications_returnsEmptyForBlankInput() {
    System.assertEquals(
      0,
      FscRelClassificationUtils.parseClassifications(null).size()
    );
    System.assertEquals(
      0,
      FscRelClassificationUtils.parseClassifications('').size()
    );
    System.assertEquals(
      0,
      FscRelClassificationUtils.parseClassifications('   ').size()
    );
  }

  @IsTest
  static void parseClassifications_splitsSemicolonValues() {
    List<String> classifications = FscRelClassificationUtils.parseClassifications(
      'Vendor;Unclassified'
    );

    System.assertEquals(2, classifications.size());
    System.assertEquals('Vendor', classifications[0]);
    System.assertEquals('Unclassified', classifications[1]);
  }

  @IsTest
  static void parseClassifications_trimsValuesAndSkipsBlanks() {
    List<String> classifications = FscRelClassificationUtils.parseClassifications(
      ' COI ; ; Vendor '
    );

    System.assertEquals(2, classifications.size());
    System.assertEquals('COI', classifications[0]);
    System.assertEquals('Vendor', classifications[1]);
  }

  @IsTest
  static void includesClassification_returnsFalseForInvalidInput() {
    System.assertEquals(
      false,
      FscRelClassificationUtils.includesClassification(null, 'Vendor')
    );
    System.assertEquals(
      false,
      FscRelClassificationUtils.includesClassification(
        new Account(),
        null
      )
    );
    System.assertEquals(
      false,
      FscRelClassificationUtils.includesClassification(
        new Account(Classification__c = 'Vendor'),
        ''
      )
    );
  }

  @IsTest
  static void includesClassification_matchesCaseInsensitive() {
    Account account = new Account(Classification__c = 'Vendor;COI');

    System.assertEquals(
      true,
      FscRelClassificationUtils.includesClassification(account, 'vendor')
    );
    System.assertEquals(
      true,
      FscRelClassificationUtils.includesClassification(account, 'coi')
    );
    System.assertEquals(
      false,
      FscRelClassificationUtils.includesClassification(account, 'Unclassified')
    );
  }

  @IsTest
  static void constants_exposeExpectedValues() {
    System.assertEquals('COI', FscRelClassificationUtils.COI);
    System.assertEquals('Vendor', FscRelClassificationUtils.VENDOR);
    System.assertEquals(
      'Unclassified',
      FscRelClassificationUtils.UNCLASSIFIED
    );
  }
}