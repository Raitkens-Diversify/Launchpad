/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-15
 */
@IsTest
private class FscRelReciprocalRoleRepositoryTest {
  @IsTest
  static void searchByTerm_withRecordTypeId_returnsMatchingRoles() {
    FscDataTestDataFactory.createReciprocalRole('Typed Spouse');
    FscRelReciprocalRoleRepository repository = new FscRelReciprocalRoleRepository();
    Id recordTypeId = repository.selectContactRecordTypeId();

    Test.startTest();
    List<Reciprocal_Role__c> results = repository.searchByTerm('Typed', recordTypeId, 5);
    Test.stopTest();

    System.assertEquals(false, results.isEmpty());
    System.assertEquals('Typed Spouse', results[0].Role__c);
  }

  @IsTest
  static void selectForLookup_returnsRolesSortedByRoleAsc() {
    FscDataTestDataFactory.createReciprocalRole('Zebra Role');
    FscDataTestDataFactory.createReciprocalRole('Alpha Role');

    FscRelReciprocalRoleRepository repository = new FscRelReciprocalRoleRepository();

    Test.startTest();
    List<Reciprocal_Role__c> results = repository.selectForLookup(null, 50);
    Test.stopTest();

    System.assert(results.size() >= 2, 'Expected default reciprocal role lookup results.');
    System.assertEquals('Alpha Role', results[0].Role__c);
  }

  @IsTest
  static void searchByTerm_doesNotMatchInverseRoleNames() {
    FscRelReciprocalRoleRepository repository = new FscRelReciprocalRoleRepository();
    Id recordTypeId = repository.selectContactRecordTypeId();
    Reciprocal_Role__c childRole = repository.insertRole('Child', recordTypeId);
    repository.insertRoleWithInverseLink('Parent', childRole.Id, recordTypeId);

    Test.startTest();
    List<Reciprocal_Role__c> results = repository.searchByTerm('Child', 10);
    Test.stopTest();

    Set<String> roleNames = new Set<String>();
    for (Reciprocal_Role__c role : results) {
      roleNames.add(role.Role__c);
    }

    System.assertEquals(true, roleNames.contains('Child'));
    System.assertEquals(false, roleNames.contains('Parent'));
  }

  @IsTest
  static void searchByTerm_returnsMatchingRoles() {
    FscDataTestDataFactory.createReciprocalRole('Spouse');

    FscRelReciprocalRoleRepository repository = new FscRelReciprocalRoleRepository();

    Test.startTest();
    List<Reciprocal_Role__c> results = repository.searchByTerm('Spouse', 5);
    Test.stopTest();

    System.assertEquals(false, results.isEmpty());
    System.assertEquals('Spouse', results[0].Role__c);
  }

  @IsTest
  static void findSimilarRoleNames_returnsPartialMatches() {
    FscDataTestDataFactory.createReciprocalRole('Child', 'Parent');

    FscRelReciprocalRoleRepository repository = new FscRelReciprocalRoleRepository();

    Test.startTest();
    List<Reciprocal_Role__c> results = repository.findSimilarRoleNames('Beneficiary Child');
    Test.stopTest();

    System.assertEquals(1, results.size());
    System.assertEquals('Child', results[0].Role__c);
  }

  @IsTest
  static void isSimilarRoleName_detectsWordOverlap() {
    System.assertEquals(
      true,
      FscRelReciprocalRoleRepository.isSimilarRoleName('beneficiary child', 'child')
    );
    System.assertEquals(
      false,
      FscRelReciprocalRoleRepository.isSimilarRoleName('parent', 'child')
    );
  }

  @IsTest
  static void ensureRolesExistAndLookupHelpers_coverRepositoryPaths() {
    FscRelReciprocalRoleRepository repository = new FscRelReciprocalRoleRepository();
    Id recordTypeId = repository.selectContactRecordTypeId();
    if (recordTypeId == null) {
      return;
    }

    repository.ensureRolesExist(
      recordTypeId,
      new Set<String>{ 'Coverage Role One', 'Coverage Role Two' }
    );

    Test.startTest();
    Reciprocal_Role__c foundRole = repository.findByRoleName('Coverage Role One');
    Reciprocal_Role__c createdRole = repository.findOrCreateByRoleName(
      'Coverage Role Two',
      recordTypeId
    );
    List<Reciprocal_Role__c> filteredRoles = repository.selectByRecordTypeAndRoleNames(
      recordTypeId,
      new Set<String>{ 'Coverage Role One', 'Coverage Role Two' },
      'Coverage',
      10
    );
    Reciprocal_Role__c selectedRole = repository.selectById(createdRole.Id);
    String displayName = FscRelReciprocalRoleRepository.resolveDisplayName(selectedRole);
    String inverseSubtitle = FscRelReciprocalRoleRepository.resolveInverseSubtitle(
      selectedRole
    );
    List<Reciprocal_Role__c> duplicates = repository.findPotentialDuplicates(
      'Coverage Role One',
      null
    );
    Map<Id, Reciprocal_Role__c> roleById = repository.selectByIds(
      new Set<Id>{ createdRole.Id }
    );
    Test.stopTest();

    System.assertNotEquals(null, foundRole);
    System.assertNotEquals(null, createdRole);
    System.assertEquals(2, filteredRoles.size());
    System.assertNotEquals(null, selectedRole);
    System.assertEquals('Coverage Role Two', displayName);
    System.assertEquals('', inverseSubtitle);
    System.assert(!duplicates.isEmpty());
    System.assert(roleById.containsKey(createdRole.Id));
  }

  @IsTest
  static void searchByTerm_returnsEmptyForBlankSearchTerm() {
    FscRelReciprocalRoleRepository repository = new FscRelReciprocalRoleRepository();

    Test.startTest();
    List<Reciprocal_Role__c> results = repository.searchByTerm('', 5);
    List<Reciprocal_Role__c> lookupResults = repository.selectForLookup(
      repository.selectContactRecordTypeId(),
      10
    );
    Test.stopTest();

    System.assertEquals(true, results.isEmpty());
    System.assertNotEquals(null, lookupResults);
  }

  @IsTest
  static void ensureRolesExist_returnsEarlyForInvalidInput() {
    FscRelReciprocalRoleRepository repository = new FscRelReciprocalRoleRepository();
    Id recordTypeId = repository.selectContactRecordTypeId();
    if (recordTypeId == null) {
      return;
    }

    repository.ensureRolesExist(recordTypeId, new Set<String>{ 'Coverage Role One' });

    Test.startTest();
    repository.ensureRolesExist(null, new Set<String>{ 'Role' });
    repository.ensureRolesExist(recordTypeId, null);
    List<Reciprocal_Role__c> blankSearchResults = repository.selectByRecordTypeAndRoleNames(
      recordTypeId,
      new Set<String>{ 'Coverage Role One' },
      '',
      10
    );
    Test.stopTest();

    System.assertEquals(1, blankSearchResults.size());
  }
}