/**
 * Tests for ObjectFieldController.
 */
@IsTest
private class ObjectFieldControllerTest {
  @IsTest
  static void getAccessibleFieldsReturnsSortedDisplayableFields() {
    Test.startTest();
    List<ObjectFieldController.FieldOption> options = ObjectFieldController.getAccessibleFields(
      'Account'
    );
    Test.stopTest();

    System.assertNotEquals(null, options, 'Options should not be null.');
    System.assert(!options.isEmpty(), 'Account should expose accessible fields.');

    // Results are sorted case-insensitively by label.
    for (Integer i = 1; i < options.size(); i++) {
      String previous = options.get(i - 1).label.toLowerCase();
      String current = options.get(i).label.toLowerCase();
      System.assert(
        previous.compareTo(current) <= 0,
        'Options should be sorted by label. Found "' +
          previous +
          '" before "' +
          current +
          '".'
      );
    }

    // Excluded/compound field types must never be present.
    Set<String> excludedTypes = new Set<String>{
      'ADDRESS',
      'BASE64',
      'ENCRYPTEDSTRING',
      'LOCATION'
    };
    Boolean sawName = false;
    for (ObjectFieldController.FieldOption option : options) {
      System.assert(
        !excludedTypes.contains(option.type),
        'Displayable results should exclude ' + option.type + ' fields.'
      );
      System.assertNotEquals(null, option.apiName, 'apiName should be populated.');
      System.assertNotEquals(null, option.label, 'label should be populated.');
      System.assertNotEquals(null, option.sortable, 'sortable should be populated.');
      if (option.apiName == 'Name') {
        sawName = true;
      }
    }
    System.assert(sawName, 'Account.Name should be returned as an accessible field.');
  }

  @IsTest
  static void getAccessibleFieldsThrowsForBlankName() {
    Boolean threw = false;
    try {
      ObjectFieldController.getAccessibleFields('   ');
    } catch (AuraHandledException error) {
      threw = true;
    }
    System.assertEquals(true, threw, 'Blank object API name should throw.');
  }

  @IsTest
  static void getAccessibleFieldsThrowsForNullName() {
    Boolean threw = false;
    try {
      ObjectFieldController.getAccessibleFields(null);
    } catch (AuraHandledException error) {
      threw = true;
    }
    System.assertEquals(true, threw, 'Null object API name should throw.');
  }

  @IsTest
  static void getAccessibleFieldsThrowsForUnknownObject() {
    Boolean threw = false;
    try {
      ObjectFieldController.getAccessibleFields('ThisObjectDoesNotExist__c');
    } catch (AuraHandledException error) {
      threw = true;
    }
    System.assertEquals(true, threw, 'Unknown object should throw.');
  }

  @IsTest
  static void fieldOptionConstructorsInitializeState() {
    ObjectFieldController.FieldOption populated = new ObjectFieldController.FieldOption(
      'CustomField__c',
      'Custom Field',
      'STRING',
      true
    );
    System.assertEquals('CustomField__c', populated.apiName, 'apiName should be set.');
    System.assertEquals('Custom Field', populated.label, 'label should be set.');
    System.assertEquals('STRING', populated.type, 'type should be set.');
    System.assertEquals(true, populated.sortable, 'sortable should be set.');

    ObjectFieldController.FieldOption empty = new ObjectFieldController.FieldOption();
    System.assertEquals(false, empty.sortable, 'Default sortable should be false.');
    System.assertEquals(null, empty.apiName, 'Default apiName should be null.');
  }
}