/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-01
 */
@IsTest
private class FscRelRoleUtilsTest {
  @IsTest
  static void resolveReciprocalRoleName_returnsReciprocalRoleDisplayName() {
    FscDataTestDataFactory.createTreeScenario();
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    Reciprocal_Role__c role = FscDataTestDataFactory.createReciprocalRoleForMemberRelationship(
      FscRelReciprocalRoleCatalog.AAR_PERSONAL_AND_FAMILY,
      'Sibling',
      'Sibling'
    );
    Account_Account_Relationship__c relation = new Account_Account_Relationship__c(
      Account__c = scenario.rootAccount.Id,
      Related_Account__c = scenario.secondPersonAccount.Id,
      Reciprocal_Role__c = role.Id,
      Inverse_Reciprocal_Role__c = role.Id,
      Active__c = true
    );
    insert relation;

    relation = [
      SELECT
        Id,
        Reciprocal_Role__c,
        Reciprocal_Role__r.Role__c,
        Reciprocal_Role__r.Name
      FROM Account_Account_Relationship__c
      WHERE Id = :relation.Id
      LIMIT 1
    ];

    Test.startTest();
    String roleName = FscRelRoleUtils.resolveReciprocalRoleName(relation);
    Test.stopTest();

    System.assertEquals('Sibling', roleName);
  }

  @IsTest
  static void resolveRelatedAccountRoleName_returnsInverseRoleForRelatedAccount() {
    FscDataTestDataFactory.createTreeScenario();
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    String recordTypeDeveloperName = FscRelRecordTypeUtils.BUSINESS_RECORD_TYPE;
    Id recordTypeId = FscRelRecordTypeUtils.selectAccountRelationRecordTypeId(
      recordTypeDeveloperName
    );

    if (recordTypeId == null) {
      return;
    }

    Reciprocal_Role__c employeeRole = FscDataTestDataFactory.createReciprocalRoleForMemberRelationship(
      recordTypeDeveloperName,
      'Employee',
      'Employer'
    );
    Reciprocal_Role__c employerRole = [
      SELECT Id, Role__c
      FROM Reciprocal_Role__c
      WHERE Role__c = 'Employer'
      LIMIT 1
    ];
    Account_Account_Relationship__c relation = new Account_Account_Relationship__c(
      Account__c = scenario.relatedBusinessAccount.Id,
      Related_Account__c = scenario.linkedPersonAccount.Id,
      RecordTypeId = recordTypeId,
      Reciprocal_Role__c = employerRole.Id,
      Inverse_Reciprocal_Role__c = employeeRole.Id,
      Active__c = true
    );
    insert relation;

    relation = [
      SELECT
        Id,
        Reciprocal_Role__c,
        Reciprocal_Role__r.Role__c,
        Reciprocal_Role__r.Name,
        Inverse_Reciprocal_Role__c,
        Inverse_Reciprocal_Role__r.Role__c,
        Inverse_Reciprocal_Role__r.Name
      FROM Account_Account_Relationship__c
      WHERE Id = :relation.Id
      LIMIT 1
    ];

    Test.startTest();
    String roleName = FscRelRoleUtils.resolveRelatedAccountRoleName(relation);
    Test.stopTest();

    System.assertEquals('Employee', roleName);
  }

  @IsTest
  static void resolveReciprocalRoleName_returnsNullWhenMissingRole() {
    Test.startTest();
    String roleName = FscRelRoleUtils.resolveReciprocalRoleName(null);
    Test.stopTest();

    System.assertEquals(null, roleName);
  }

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