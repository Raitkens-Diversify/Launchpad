/**
 * Tests for FieldSetController, focused on getMultipleFieldSets and the
 * object / field-set lookup error paths.
 */
@IsTest
private class FieldSetControllerTest {
  private static String resolveAccountFieldSetApiName() {
    Map<String, Schema.FieldSet> fieldSetMap = Account.SObjectType.getDescribe()
      .fieldSets.getMap();
    return fieldSetMap.isEmpty() ? null : new List<String>(fieldSetMap.keySet())[0];
  }

  @IsTest
  static void getFieldSetFieldsReturnsMetadata() {
    String fieldSetApiName = resolveAccountFieldSetApiName();
    if (fieldSetApiName == null) {
      return;
    }

    Test.startTest();
    List<FieldSetController.FieldMetadata> fields = FieldSetController.getFieldSetFields(
      'Account',
      fieldSetApiName
    );
    Test.stopTest();

    System.assertNotEquals(null, fields, 'Fields should not be null.');
    System.assert(!fields.isEmpty(), 'Field set should contain fields.');
    for (FieldSetController.FieldMetadata field : fields) {
      System.assertNotEquals(null, field.fieldPath, 'fieldPath should be populated.');
      System.assertNotEquals(null, field.inputType, 'inputType should be populated.');
      System.assertNotEquals(null, field.type, 'type should be populated.');
    }
  }

  @IsTest
  static void getFieldSetFieldsThrowsForUnknownObject() {
    Boolean threw = false;
    try {
      FieldSetController.getFieldSetFields('ThisObjectDoesNotExist__c', 'Any_Field_Set');
    } catch (AuraHandledException error) {
      threw = true;
    }
    System.assertEquals(true, threw, 'Unknown object should throw.');
  }

  @IsTest
  static void getFieldSetFieldsThrowsForUnknownFieldSet() {
    Boolean threw = false;
    try {
      FieldSetController.getFieldSetFields('Account', 'This_Field_Set_Does_Not_Exist');
    } catch (AuraHandledException error) {
      threw = true;
    }
    System.assertEquals(true, threw, 'Unknown field set should throw.');
  }

  @IsTest
  static void getMultipleFieldSetsReturnsKnownAndUnknownSets() {
    String fieldSetApiName = resolveAccountFieldSetApiName();

    List<String> requested = new List<String>{ 'This_Field_Set_Does_Not_Exist' };
    if (fieldSetApiName != null) {
      requested.add(fieldSetApiName);
    }

    Test.startTest();
    Map<String, List<FieldSetController.FieldMetadata>> result = FieldSetController.getMultipleFieldSets(
      'Account',
      requested
    );
    Test.stopTest();

    System.assertNotEquals(null, result, 'Result should not be null.');
    // Every requested name gets a key, even when the field set does not exist.
    for (String name : requested) {
      System.assert(result.containsKey(name), 'Result should contain key: ' + name);
      System.assertNotEquals(null, result.get(name), 'List for ' + name + ' should not be null.');
    }
    // The missing field set resolves to an empty list.
    System.assert(
      result.get('This_Field_Set_Does_Not_Exist').isEmpty(),
      'Unknown field set should map to an empty list.'
    );
    // A real field set resolves to populated metadata.
    if (fieldSetApiName != null) {
      System.assert(
        !result.get(fieldSetApiName).isEmpty(),
        'Known field set should map to a non-empty list.'
      );
    }
  }

  @IsTest
  static void getMultipleFieldSetsThrowsForUnknownObject() {
    Boolean threw = false;
    try {
      FieldSetController.getMultipleFieldSets(
        'ThisObjectDoesNotExist__c',
        new List<String>{ 'Any_Field_Set' }
      );
    } catch (AuraHandledException error) {
      threw = true;
    }
    System.assertEquals(true, threw, 'Unknown object should throw.');
  }

  @IsTest
  static void picklistOptionConstructorInitializesState() {
    FieldSetController.PicklistOption option = new FieldSetController.PicklistOption(
      'Label A',
      'value_a'
    );
    System.assertEquals('Label A', option.label, 'label should be set.');
    System.assertEquals('value_a', option.value, 'value should be set.');
  }
}