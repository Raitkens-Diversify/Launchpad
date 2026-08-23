/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-01
 */
@IsTest
private class FscRelRoleUtilsTest {
  @IsTest
  static void parseRoles_splitsSemicolonDelimitedValues() {
    Test.startTest();
    List<String> roles = FscRelRoleUtils.parseRoles('Client; Dependent ;;;Beneficiary');
    Test.stopTest();

    System.assertEquals(3, roles.size());
    System.assertEquals('Client', roles[0]);
    System.assertEquals('Dependent', roles[1]);
    System.assertEquals('Beneficiary', roles[2]);
  }

  @IsTest
  static void parseRoles_blankInputReturnsEmptyList() {
    Test.startTest();
    List<String> roles = FscRelRoleUtils.parseRoles(null);
    Test.stopTest();

    System.assertEquals(true, roles.isEmpty());
  }

  @IsTest
  static void buildRolesString_joinsUniqueValues() {
    Test.startTest();
    String rolesString = FscRelRoleUtils.buildRolesString(
      new List<String>{ 'Client', 'Client', 'Dependent', ' ', null }
    );
    Test.stopTest();

    System.assertEquals('Client;Dependent', rolesString);
  }

  @IsTest
  static void buildRolesString_emptyInputReturnsBlankString() {
    Test.startTest();
    String rolesString = FscRelRoleUtils.buildRolesString(new List<String>());
    Test.stopTest();

    System.assertEquals('', rolesString);
  }
}