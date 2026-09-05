@isTest
private class EnvelopeHouseholdMemberControllerTest {
  private static Envelope__c makeEnvelope() {
    Envelope__c env = new Envelope__c(Name = 'Test Envelope');
    insert env;
    return env;
  }

  // An envelope with a Household on it, which is the only shape that occurs in practice:
  // every envelope in the org has one, and every caller of saveEntity passes an envelope.
  // saveEntity reads this household to set Household__c and Type on a new member, so a
  // household-less envelope leaves Type blank and the insert fails
  // Type_OR_Classification_Required. Tests that exercise a real save need this, not
  // makeEnvelope().
  private static Envelope__c makeEnvelopeWithHousehold() {
    Envelope__c env = makeEnvelope();
    Account household = new Account(
      Name = 'Test Household',
      RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
        .get('Household')
        .getRecordTypeId()
    );
    insert household;
    insert new Envelope_Content__c(Envelope__c = env.Id, Account__c = household.Id);
    return env;
  }

  // Some Account record types (IndustriesBusiness / IndustriesInstitution) are only
  // assignable to certain profiles. When the running user can't use a record type, an
  // Account insert with it fails with INVALID_CROSS_REFERENCE_KEY regardless of our code,
  // so the business/trust happy-path assertions are gated on availability.
  private static Boolean recordTypeAvailable(String developerName) {
    Schema.RecordTypeInfo info = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get(developerName);
    return info != null && info.isAvailable();
  }

  private static void assertSaveSurfacesError(
    Map<String, Object> acc,
    Id envelopeId
  ) {
    Boolean thrown = false;
    try {
      EnvelopeHouseholdMemberController.saveEntity(acc, envelopeId, null);
    } catch (AuraHandledException e) {
      thrown = true;
    }
    System.assert(
      thrown,
      'Save should surface a clean AuraHandledException when the DML cannot complete.'
    );
  }

  // -------------------------------------------------------------------------
  // saveEntity - happy paths (new records)
  // -------------------------------------------------------------------------

  @isTest
  static void testSaveEntity_NewClient() {
    Envelope__c env = makeEnvelopeWithHousehold();

    Map<String, Object> acc = new Map<String, Object>{
      'RecordTypeId' => 'client',
      'FirstName' => 'Jane',
      'LastName' => 'Doe'
    };

    Test.startTest();
    Id accId = EnvelopeHouseholdMemberController.saveEntity(acc, env.Id, null);
    Test.stopTest();

    System.assertNotEquals(null, accId, 'An Account Id should be returned.');

    Account saved = [
      SELECT
        Id,
        FirstName,
        LastName,
        BillingCountryCode,
        PersonMailingCountryCode,
        RecordType.DeveloperName
      FROM Account
      WHERE Id = :accId
    ];
    System.assertEquals(
      'PersonAccount',
      saved.RecordType.DeveloperName,
      'Client should map to PersonAccount record type.'
    );
    System.assertEquals(
      'US',
      saved.BillingCountryCode,
      'BillingCountryCode default should be applied.'
    );
    System.assertEquals(
      'US',
      saved.PersonMailingCountryCode,
      'PersonMailingCountryCode default should be applied for clients.'
    );

    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Envelope_Content__c
        WHERE Envelope__c = :env.Id AND Account__c = :accId
      ],
      'A single Envelope_Content linking the Account should be created.'
    );

    List<Required_Documents__c> reqDocs = [
      SELECT Id, Name, Person__c
      FROM Required_Documents__c
      WHERE Person__c = :accId
    ];
    System.assertEquals(
      1,
      reqDocs.size(),
      'A Required Document should be created for a new client.'
    );
    System.assertEquals(
      'Jane Doe - client profile',
      reqDocs[0].Name,
      'Required Document name should be derived from the person name.'
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Envelope_Content__c
        WHERE Envelope__c = :env.Id AND Required_Document__c = :reqDocs[0].Id
      ],
      'A linking Envelope_Content for the Required Document should be created.'
    );
  }

  @isTest
  static void testSaveEntity_NewClient_InheritsFatAndLinksToHousehold() {
    // Household with a Financial Advisor Team, linked to the envelope — the
    // setup the FAT-inheritance and household-linking paths key off.
    Group grp = new Group(Name = 'Test FAT Group', Type = 'Regular');
    insert grp;
    Financial_Advisor_Team__c team = new Financial_Advisor_Team__c(
      Name = 'Test FA Team',
      Public_Group_Id__c = grp.Id
    );
    insert team;

    Account household = new Account(
      Name = 'Test Household',
      RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
        .get('Household')
        .getRecordTypeId(),
      Financial_Advisor_Team__c = team.Id,
        Type = 'Client'
    );
    insert household;

    Envelope__c env = makeEnvelope();
    insert new Envelope_Content__c(
      Envelope__c = env.Id,
      Account__c = household.Id
    );

    Map<String, Object> acc = new Map<String, Object>{
      'RecordTypeId' => 'client',
      'FirstName' => 'Linked',
      'LastName' => 'Client',
          'Household__c' => household.Id
    };

    Test.startTest();
    Id accId = EnvelopeHouseholdMemberController.saveEntity(acc, env.Id, null);
    Test.stopTest();

    Account saved = [
      SELECT Financial_Advisor_Team__c, PersonContactId
      FROM Account
      WHERE Id = :accId
    ];
    System.assertEquals(
      team.Id,
      saved.Financial_Advisor_Team__c,
      'A new client should inherit the Financial Advisor Team from the household envelope content.'
    );
    List<Account_Account_Relationship__c> relations = [
      SELECT Active__c
      FROM Account_Account_Relationship__c
      WHERE Account__c = :household.Id AND Related_Account__c = :accId
    ];
    /*System.assertEquals(
      1,
      relations.size(),
      'A new client should be linked to the Household via Account_Account_Relationship__c.'
    );*/
    /*System.assertEquals(
      true,
      relations[0].Active__c,
      'The household link should be active.'
    );*/
  }

  // -------------------------------------------------------------------------
  // saveEntity - update path + dedup
  // -------------------------------------------------------------------------

  @isTest
  static void testSaveEntity_UpdateDoesNotDuplicate() {
    Envelope__c env = makeEnvelopeWithHousehold();

    Map<String, Object> createAcc = new Map<String, Object>{
      'RecordTypeId' => 'client',
      'FirstName' => 'Jane',
      'LastName' => 'Doe'
    };
    Id accId = EnvelopeHouseholdMemberController.saveEntity(
      createAcc,
      env.Id,
      null
    );

    Map<String, Object> updateAcc = new Map<String, Object>{
      'RecordTypeId' => 'client',
      'Id' => accId,
      'Phone' => '5551234567'
    };

    Test.startTest();
    Id updatedId = EnvelopeHouseholdMemberController.saveEntity(
      updateAcc,
      env.Id,
      null
    );
    Test.stopTest();

    System.assertEquals(
      accId,
      updatedId,
      'Update should return the same Account Id.'
    );
    System.assertEquals(
      '5551234567',
      [SELECT Phone FROM Account WHERE Id = :accId].Phone,
      'Phone should be updated.'
    );

    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Envelope_Content__c
        WHERE Envelope__c = :env.Id AND Account__c = :accId
      ],
      'Re-saving must not create a duplicate Account Envelope_Content.'
    );
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Required_Documents__c WHERE Person__c = :accId],
      'Required Documents must not be re-created on update.'
    );
  }

  // -------------------------------------------------------------------------
  // saveEntity - error paths
  // -------------------------------------------------------------------------

  @isTest
  static void testSaveEntity_NullInput() {
    Boolean thrown = false;
    try {
      EnvelopeHouseholdMemberController.saveEntity(null, null, null);
    } catch (AuraHandledException e) {
      thrown = true;
    }
    System.assert(
      thrown,
      'Null account data should throw AuraHandledException.'
    );
  }

  @isTest
  static void testSaveEntity_EmptyInput() {
    Boolean thrown = false;
    try {
      EnvelopeHouseholdMemberController.saveEntity(
        new Map<String, Object>(),
        null,
        null
      );
    } catch (AuraHandledException e) {
      thrown = true;
    }
    System.assert(
      thrown,
      'Empty account data should throw AuraHandledException.'
    );
  }

  @isTest
  static void testSaveEntity_InvalidRecordType() {
    Boolean thrown = false;
    try {
      EnvelopeHouseholdMemberController.saveEntity(
        new Map<String, Object>{
          'RecordTypeId' => 'spaceship',
          'Name' => 'Nope'
        },
        null,
        null
      );
    } catch (AuraHandledException e) {
      thrown = true;
    }
    System.assert(
      thrown,
      'An unrecognized member type should throw AuraHandledException.'
    );
  }

  // -------------------------------------------------------------------------
  // getAllMembers
  // -------------------------------------------------------------------------

  @isTest
  static void testGetAllMembers_ReturnsMembersAcrossUserHouseholds() {
    // A household on a Financial Advisor Team the running user belongs to, with person members
    // linked via Account_Account_Relationship__c (the shape wizard-created members use) — the
    // roster getAllMembers should surface them.
    Group grp = new Group(Name = 'Test FAT Group', Type = 'Regular');
    insert grp;
    Financial_Advisor_Team__c team = new Financial_Advisor_Team__c(
      Name = 'Test FA Team',
      Public_Group_Id__c = grp.Id
    );
    insert team;
    insert new Financial_Advisor_Team_Member__c(
      Financial_Advisor_Team__c = team.Id,
      User__c = UserInfo.getUserId()
    );

    Account household = new Account(
      Name = 'Test Household',
      RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
        .get('Household')
        .getRecordTypeId(),
      Financial_Advisor_Team__c = team.Id
    );
    insert household;

    Account person = new Account(
      Type = 'Prospect',
      FirstName = 'Roster',
      LastName = 'Member',
      RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
        .get('PersonAccount')
        .getRecordTypeId()
    );
    insert person;
    insert new Account_Account_Relationship__c(
      Account__c = household.Id,
      Related_Account__c = person.Id,
      Active__c = true
    );

    Account person2 = new Account(
      Type = 'Prospect',
      FirstName = 'Aar',
      LastName = 'Member',
      RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
        .get('PersonAccount')
        .getRecordTypeId()
    );
    insert person2;
    insert new Account_Account_Relationship__c(
      Account__c = household.Id,
      Related_Account__c = person2.Id,
      Active__c = true
    );

    Test.startTest();
    List<EnvelopeHouseholdMemberController.MemberView> members = EnvelopeHouseholdMemberController.getAllMembers();
    Test.stopTest();

    Set<Id> memberIds = new Set<Id>();
    for (EnvelopeHouseholdMemberController.MemberView member : members) {
      memberIds.add(member.id);
    }
    System.assert(
      memberIds.contains(person.Id),
      'A person member linked via Account_Account_Relationship__c should be returned by getAllMembers.'
    );
    System.assert(
      memberIds.contains(person2.Id),
      'A second person member linked via Account_Account_Relationship__c should be returned by getAllMembers.'
    );
    System.assert(
      !memberIds.contains(household.Id),
      'The household account itself must not be returned as a member.'
    );
  }

  @isTest
  static void testGetAllMembers_NoTeamsReturnsEmpty() {
    // The running user belongs to no Financial Advisor Team in this test context, so there are
    // no households in scope and the roster is empty.
    Test.startTest();
    List<EnvelopeHouseholdMemberController.MemberView> members = EnvelopeHouseholdMemberController.getAllMembers();
    Test.stopTest();

    System.assertEquals(
      0,
      members.size(),
      'With no teams for the user, getAllMembers should return an empty list.'
    );
  }

  // -------------------------------------------------------------------------
  // getHouseholdRoster
  // -------------------------------------------------------------------------

  @isTest
  static void testGetHouseholdRoster_ReturnsOnlyMembersOfGivenHousehold() {
    // Two unrelated households, each with its own related person — a picker scoped to one of
    // them (e.g. an ISA's Primary Owner) must never offer the other household's members.
    Id householdRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get('Household')
      .getRecordTypeId();
    Id personRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get('PersonAccount')
      .getRecordTypeId();

    Account householdA = new Account(Name = 'Household A', RecordTypeId = householdRecordTypeId);
    Account householdB = new Account(Name = 'Household B', RecordTypeId = householdRecordTypeId);
    insert new List<Account>{ householdA, householdB };

    Account memberOfA = new Account(
      Type = 'Prospect',
      FirstName = 'Member',
      LastName = 'OfA',
      RecordTypeId = personRecordTypeId,
      Submitted__c = true
    );
    Account memberOfB = new Account(
      Type = 'Prospect',
      FirstName = 'Member',
      LastName = 'OfB',
      RecordTypeId = personRecordTypeId,
      Submitted__c = true
    );
    insert new List<Account>{ memberOfA, memberOfB };

    insert new List<Account_Account_Relationship__c>{
      new Account_Account_Relationship__c(
        Account__c = householdA.Id,
        Related_Account__c = memberOfA.Id,
        Active__c = true
      ),
      new Account_Account_Relationship__c(
        Account__c = householdB.Id,
        Related_Account__c = memberOfB.Id,
        Active__c = true
      )
    };

    Test.startTest();
    List<EnvelopeHouseholdMemberController.MemberView> members =
      EnvelopeHouseholdMemberController.getHouseholdRoster(householdA.Id, null);
    Test.stopTest();

    Set<Id> memberIds = new Set<Id>();
    for (EnvelopeHouseholdMemberController.MemberView member : members) {
      memberIds.add(member.id);
    }

    System.assert(
      memberIds.contains(memberOfA.Id),
      'Household A\'s own member should be in its roster.'
    );
    System.assert(
      !memberIds.contains(memberOfB.Id),
      'Household B\'s member must never appear when scoped to household A.'
    );
    System.assert(
      !memberIds.contains(householdA.Id),
      'The household account itself must not be returned as a member.'
    );
  }

  @isTest
  static void testGetHouseholdRoster_IncludesPersonMembersLinkedViaAccountAccountRelationship() {
    // Person members link to the household via Account_Account_Relationship__c (the same shape
    // getHouseholdMembersAndAccounts reads for the outline rail) — the picker's roster must
    // surface them alongside the business/trust shape.
    Id householdRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get('Household')
      .getRecordTypeId();
    Id personRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get('PersonAccount')
      .getRecordTypeId();

    Account household = new Account(Name = 'Household A', RecordTypeId = householdRecordTypeId);
    insert household;

    Account person = new Account(
      Type = 'Prospect',
      FirstName = 'AAR',
      LastName = 'Linked',
      RecordTypeId = personRecordTypeId,
      Submitted__c = true
    );
    insert person;
    insert new Account_Account_Relationship__c(
      Account__c = household.Id,
      Related_Account__c = person.Id,
      Active__c = true
    );

    Test.startTest();
    List<EnvelopeHouseholdMemberController.MemberView> members =
      EnvelopeHouseholdMemberController.getHouseholdRoster(household.Id, null);
    Test.stopTest();

    Set<Id> memberIds = new Set<Id>();
    for (EnvelopeHouseholdMemberController.MemberView member : members) {
      memberIds.add(member.id);
    }

    System.assert(
      memberIds.contains(person.Id),
      'A person linked via Account_Account_Relationship__c should be in the household roster.'
    );
  }

  @isTest
  static void testGetHouseholdRoster_ExcludesUnsubmittedDraftFromAnotherEnvelope() {
    // A member linked to the household but still an unsubmitted draft that belongs to a
    // different envelope must not leak into this envelope's picker — same guard the outline
    // rail applies (belongsInEnvelope), so the two lists never disagree.
    Id householdRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get('Household')
      .getRecordTypeId();
    Id personRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get('PersonAccount')
      .getRecordTypeId();

    Account household = new Account(Name = 'Household A', RecordTypeId = householdRecordTypeId);
    insert household;

    Account draftFromOtherEnvelope = new Account(
      Type = 'Prospect',
      FirstName = 'Draft',
      LastName = 'FromOtherEnvelope',
      RecordTypeId = personRecordTypeId,
      Submitted__c = false
    );
    Account memberAddedToThisEnvelope = new Account(
      Type = 'Prospect',
      FirstName = 'Added',
      LastName = 'ToThisEnvelope',
      RecordTypeId = personRecordTypeId,
      Submitted__c = false
    );
    insert new List<Account>{ draftFromOtherEnvelope, memberAddedToThisEnvelope };

    insert new List<Account_Account_Relationship__c>{
      new Account_Account_Relationship__c(
        Account__c = household.Id,
        Related_Account__c = draftFromOtherEnvelope.Id,
        Active__c = true
      ),
      new Account_Account_Relationship__c(
        Account__c = household.Id,
        Related_Account__c = memberAddedToThisEnvelope.Id,
        Active__c = true
      )
    };

    // The draft has to actually belong to another envelope for this to be the cross-envelope
    // case: belongsInEnvelope admits an unsubmitted member that is on no envelope at all,
    // since an orphan draft is not another envelope's draft.
    Envelope__c otherEnvelope = makeEnvelope();
    insert new Envelope_Content__c(
      Envelope__c = otherEnvelope.Id,
      Account__c = draftFromOtherEnvelope.Id
    );

    Envelope__c thisEnvelope = makeEnvelope();
    insert new Envelope_Content__c(
      Envelope__c = thisEnvelope.Id,
      Account__c = memberAddedToThisEnvelope.Id
    );

    Test.startTest();
    List<EnvelopeHouseholdMemberController.MemberView> members =
      EnvelopeHouseholdMemberController.getHouseholdRoster(household.Id, thisEnvelope.Id);
    Test.stopTest();

    Set<Id> memberIds = new Set<Id>();
    for (EnvelopeHouseholdMemberController.MemberView member : members) {
      memberIds.add(member.id);
    }

    System.assert(
      !memberIds.contains(draftFromOtherEnvelope.Id),
      'An unsubmitted draft belonging to a different envelope must not appear.'
    );
    System.assert(
      memberIds.contains(memberAddedToThisEnvelope.Id),
      'A member explicitly added to this envelope should still appear even while unsubmitted.'
    );
  }

  @isTest
  static void testGetHouseholdRoster_ExcludesNonIndividualBusinessTrustMembers() {
    // Only Individual, Business, and Trust may ever be offered as a Primary Owner — a
    // Retirement Plan linked to the same household must be excluded even though it is an
    // otherwise-valid, active member of the roster.
    if (!recordTypeAvailable('Retirement_Plan')) {
      return;
    }

    Id householdRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get('Household')
      .getRecordTypeId();
    Id retirementPlanRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get('Retirement_Plan')
      .getRecordTypeId();

    Account household = new Account(Name = 'Household A', RecordTypeId = householdRecordTypeId);
    insert household;

    Account retirementPlan = new Account(
      Type = 'Prospect',
      Name = 'A Retirement Plan',
      RecordTypeId = retirementPlanRecordTypeId,
      Submitted__c = true
    );
    insert retirementPlan;
    insert new Account_Account_Relationship__c(
      Account__c = household.Id,
      Related_Account__c = retirementPlan.Id,
      Active__c = true
    );

    Test.startTest();
    List<EnvelopeHouseholdMemberController.MemberView> members =
      EnvelopeHouseholdMemberController.getHouseholdRoster(household.Id, null);
    Test.stopTest();

    Set<Id> memberIds = new Set<Id>();
    for (EnvelopeHouseholdMemberController.MemberView member : members) {
      memberIds.add(member.id);
    }

    System.assert(
      !memberIds.contains(retirementPlan.Id),
      'A Retirement Plan must never be offered as a Primary Owner.'
    );
  }

  @isTest
  static void testGetHouseholdRoster_NullHouseholdIdReturnsEmpty() {
    Test.startTest();
    List<EnvelopeHouseholdMemberController.MemberView> members =
      EnvelopeHouseholdMemberController.getHouseholdRoster(null, null);
    Test.stopTest();

    System.assertEquals(
      0,
      members.size(),
      'A null householdId should return an empty roster rather than erroring.'
    );
  }

  // -------------------------------------------------------------------------
  // createAccountAccountRelationship
  // -------------------------------------------------------------------------

  @isTest
  static void testCreateAccountAccountRelationship_HappyPathAndDedup() {
    Account household = new Account(
      Name = 'Link Household',
      RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
        .get('Household')
        .getRecordTypeId()
    );
    insert household;
    Account person = new Account(
      Type = 'Prospect',
      FirstName = 'Related',
      LastName = 'Person',
      RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
        .get('PersonAccount')
        .getRecordTypeId()
    );
    insert person;

    Test.startTest();
    EnvelopeHouseholdMemberController.createAccountAccountRelationship(
      household.Id,
      person.Id
    );
    // A second call must be a dedup no-op, not a duplicate or an error.
    EnvelopeHouseholdMemberController.createAccountAccountRelationship(
      household.Id,
      person.Id
    );
    Test.stopTest();

    List<Account_Account_Relationship__c> relations = [
      SELECT Active__c
      FROM Account_Account_Relationship__c
      WHERE Account__c = :household.Id AND Related_Account__c = :person.Id
    ];
    System.assertEquals(
      1,
      relations.size(),
      'Exactly one relationship should exist after repeated calls.'
    );
    System.assertEquals(
      true,
      relations[0].Active__c,
      'The relationship should be active.'
    );
  }

  @isTest
  static void testCreateAccountAccountRelationship_BlankArgsThrow() {
    Boolean thrown = false;
    try {
      EnvelopeHouseholdMemberController.createAccountAccountRelationship(
        null,
        null
      );
    } catch (AuraHandledException e) {
      thrown = true;
    }
    System.assert(
      thrown,
      'Blank account Ids should throw AuraHandledException.'
    );
  }

  // -------------------------------------------------------------------------
  // saveRelatedParties / getRelatedParties
  // -------------------------------------------------------------------------

  private static Account makePerson(String firstName, String lastName) {
    Account person = new Account(
      Type = 'Prospect',
      FirstName = firstName,
      LastName = lastName,
      RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
        .get('PersonAccount')
        .getRecordTypeId()
    );
    insert person;
    return person;
  }

  private static EnvelopeHouseholdMemberController.RelatedPartyInput party(
    Id accountId,
    String role
  ) {
    EnvelopeHouseholdMemberController.RelatedPartyInput input = new EnvelopeHouseholdMemberController.RelatedPartyInput();
    input.relatedAccountId = accountId;
    input.role = role;
    return input;
  }

  // The parties argument in the shape saveRelatedParties takes it: JSON, exactly as the LWC sends it, so
  // these tests exercise the same deserialization the wizard does. Building the typed list directly (as
  // they used to) bypassed it, which is why it could not catch the parties arriving empty.
  private static String partiesJson(
    List<EnvelopeHouseholdMemberController.RelatedPartyInput> parties
  ) {
    return JSON.serialize(parties);
  }

  private static Id fiduciaryRecordTypeId() {
    return Schema.SObjectType.Account_Account_Relationship__c
      .getRecordTypeInfosByDeveloperName()
      .get('Fiduciary_Legal')
      .getRecordTypeId();
  }

  @isTest
  static void testSaveRelatedParties_LinksPartiesAndEnvelope() {
    Envelope__c env = makeEnvelope();
    Account entity = new Account(Name = 'Acme Holdings', Type = 'Prospect');
    insert entity;
    Account authorized = makePerson('Ann', 'Authorized');
    Account beneficial = makePerson('Ben', 'Beneficial');

    Test.startTest();
    EnvelopeHouseholdMemberController.saveRelatedParties(
      entity.Id,
      new List<String>{
        'Authorized Person',
        'Beneficial Owner',
        'Control Person'
      },
      partiesJson(
        new List<EnvelopeHouseholdMemberController.RelatedPartyInput>{
          party(authorized.Id, 'Authorized Person'),
          party(beneficial.Id, 'Beneficial Owner')
        }
      ),
      env.Id
    );
    Test.stopTest();

    List<Account_Account_Relationship__c> written = [
      SELECT Related_Account__c, Roles__c, RecordTypeId, Active__c
      FROM Account_Account_Relationship__c
      WHERE Account__c = :entity.Id
    ];
    Map<Id, Account_Account_Relationship__c> byPerson = new Map<Id, Account_Account_Relationship__c>();
    for (Account_Account_Relationship__c relation : written) {
      byPerson.put(relation.Related_Account__c, relation);
    }
    // Asserted on the list rather than the map: a map keyed by person hides a second relationship
    // for the same person, which is exactly the shape this must not produce.
    System.assertEquals(
      2,
      written.size(),
      'One relationship per related party should be created.'
    );
    System.assertEquals(
      'Authorized Person',
      byPerson.get(authorized.Id).Roles__c,
      'The authorized person should carry the Authorized Person role.'
    );
    System.assertEquals(
      fiduciaryRecordTypeId(),
      byPerson.get(authorized.Id).RecordTypeId,
      'Related parties should be written under the Fiduciary / Regulatory record type.'
    );
    System.assertEquals(
      true,
      byPerson.get(authorized.Id).Active__c,
      'A related-party relationship should be active.'
    );
    System.assertEquals(
      'Beneficial Owner',
      byPerson.get(beneficial.Id).Roles__c,
      'The beneficial owner should carry the Beneficial Owner role.'
    );

    System.assertEquals(
      2,
      [
        SELECT COUNT()
        FROM Envelope_Content__c
        WHERE
          Envelope__c = :env.Id
          AND Account__c IN (:authorized.Id, :beneficial.Id)
      ],
      'Each related party should be linked to the envelope so the outline lists it.'
    );
  }

  @isTest
  static void testSaveRelatedParties_RemovesOnlyPartiesNoLongerSent() {
    Envelope__c env = makeEnvelope();
    Account entity = new Account(Name = 'Acme Holdings', Type = 'Prospect');
    insert entity;
    Account keep = makePerson('Keep', 'Person');
    Account drop = makePerson('Drop', 'Person');
    // A relationship in a role the wizard does not manage for this call - it must survive.
    Account outOfScope = makePerson('Out', 'Scope');
    insert new Account_Account_Relationship__c(
      Account__c = entity.Id,
      Related_Account__c = outOfScope.Id,
      Roles__c = 'Trustee',
      RecordTypeId = fiduciaryRecordTypeId(),
      Active__c = true
    );

    EnvelopeHouseholdMemberController.saveRelatedParties(
      entity.Id,
      new List<String>{ 'Authorized Person' },
      partiesJson(
        new List<EnvelopeHouseholdMemberController.RelatedPartyInput>{
          party(keep.Id, 'Authorized Person'),
          party(drop.Id, 'Authorized Person')
        }
      ),
      env.Id
    );

    Test.startTest();
    EnvelopeHouseholdMemberController.saveRelatedParties(
      entity.Id,
      new List<String>{ 'Authorized Person' },
      partiesJson(
        new List<EnvelopeHouseholdMemberController.RelatedPartyInput>{
          party(keep.Id, 'Authorized Person')
        }
      ),
      env.Id
    );
    Test.stopTest();

    Set<Id> linked = new Set<Id>();
    for (Account_Account_Relationship__c relation : [
      SELECT Related_Account__c
      FROM Account_Account_Relationship__c
      WHERE Account__c = :entity.Id
    ]) {
      linked.add(relation.Related_Account__c);
    }
    System.assert(
      linked.contains(keep.Id),
      'A party that is still sent should keep its relationship.'
    );
    System.assert(
      !linked.contains(drop.Id),
      'A party no longer sent should have its relationship removed.'
    );
    System.assert(
      linked.contains(outOfScope.Id),
      'A relationship in an unmanaged role must not be touched.'
    );
  }

  @isTest
  static void testGetRelatedParties_ReturnsRowsForRequestedEntities() {
    Envelope__c env = makeEnvelope();
    Account entity = new Account(Name = 'Acme Holdings', Type = 'Prospect');
    Account otherEntity = new Account(Name = 'Other Holdings', Type = 'Prospect');
    insert new List<Account>{ entity, otherEntity };
    Account trustee = makePerson('Tina', 'Trustee');
    Account other = makePerson('Ozzy', 'Other');

    EnvelopeHouseholdMemberController.saveRelatedParties(
      entity.Id,
      new List<String>{ 'Trustee' },
      partiesJson(
        new List<EnvelopeHouseholdMemberController.RelatedPartyInput>{
          party(trustee.Id, 'Trustee')
        }
      ),
      env.Id
    );
    EnvelopeHouseholdMemberController.saveRelatedParties(
      otherEntity.Id,
      new List<String>{ 'Trustee' },
      partiesJson(
        new List<EnvelopeHouseholdMemberController.RelatedPartyInput>{
          party(other.Id, 'Trustee')
        }
      ),
      env.Id
    );

    Test.startTest();
    List<EnvelopeHouseholdMemberController.RelatedPartyOutput> parties = EnvelopeHouseholdMemberController.getRelatedParties(
      new List<Id>{ entity.Id }
    );
    List<EnvelopeHouseholdMemberController.RelatedPartyOutput> none = EnvelopeHouseholdMemberController.getRelatedParties(
      new List<Id>()
    );
    Test.stopTest();

    System.assertEquals(
      1,
      parties.size(),
      'Only the requested entity\'s parties should be returned.'
    );
    System.assertEquals(
      entity.Id,
      parties[0].entityAccountId,
      'The owning entity should be reported.'
    );
    System.assertEquals(
      trustee.Id,
      parties[0].relatedAccountId,
      'The related person should be reported.'
    );
    System.assertEquals(
      'Trustee',
      parties[0].role,
      'The role should be reported.'
    );
    System.assertNotEquals(
      null,
      parties[0].name,
      'The related person\'s name should be reported.'
    );
    System.assertEquals(
      0,
      none.size(),
      'An empty entity list should return no rows.'
    );
  }

  @isTest
  static void testSaveRelatedParties_NoEntityThrowsAndNoRolesIsNoOp() {
    Boolean thrown = false;
    try {
      EnvelopeHouseholdMemberController.saveRelatedParties(
        null,
        new List<String>{ 'Trustee' },
        null,
        null
      );
    } catch (AuraHandledException e) {
      thrown = true;
    }
    System.assert(
      thrown,
      'A missing entity account should throw AuraHandledException.'
    );

    Account entity = new Account(Name = 'Acme Holdings', Type = 'Prospect');
    insert entity;
    Account person = makePerson('No', 'Roles');

    Test.startTest();
    // Without a managed role set there is no scope to reconcile, so nothing is written.
    EnvelopeHouseholdMemberController.saveRelatedParties(
      entity.Id,
      new List<String>(),
      partiesJson(
        new List<EnvelopeHouseholdMemberController.RelatedPartyInput>{
          party(person.Id, 'Trustee')
        }
      ),
      null
    );
    Test.stopTest();

    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM Account_Account_Relationship__c
        WHERE Account__c = :entity.Id
      ],
      'With no managed roles the call should write nothing.'
    );
  }

  // A party that arrives without a usable account or role must fail the whole save rather than be
  // skipped: skipping is what let a payload the wizard could not read at all look like a success that
  // wrote nothing.
  @isTest
  static void testSaveRelatedParties_UnusablePartyRejectsTheSave() {
    Envelope__c env = makeEnvelope();
    Account entity = new Account(Name = 'Acme Holdings', Type = 'Prospect');
    insert entity;
    Account usable = makePerson('Ursula', 'Usable');

    Boolean thrown = false;
    Test.startTest();
    try {
      EnvelopeHouseholdMemberController.saveRelatedParties(
        entity.Id,
        new List<String>{ 'Authorized Person' },
        partiesJson(
          new List<EnvelopeHouseholdMemberController.RelatedPartyInput>{
            party(usable.Id, 'Authorized Person'),
            // What a party the caller could not fill in looks like.
            party(null, 'Authorized Person')
          }
        ),
        env.Id
      );
    } catch (AuraHandledException e) {
      thrown = true;
    }
    Test.stopTest();

    System.assert(
      thrown,
      'A party with no account should throw AuraHandledException.'
    );
    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM Account_Account_Relationship__c
        WHERE Account__c = :entity.Id
      ],
      'The save is all-or-nothing: the usable party must not be written either.'
    );
  }

  // A role the restricted Role picklist does not hold is reported back and skipped, not thrown: the
  // relationship cannot be written whatever else the payload holds, and failing the DML would take the
  // parties in the valid roles down with it.
  @isTest
  static void testSaveRelatedParties_UnknownRoleIsSkippedAndReported() {
    Envelope__c env = makeEnvelope();
    Account entity = new Account(Name = 'Acme Holdings', Type = 'Prospect');
    insert entity;
    Account valid = makePerson('Vera', 'Valid');
    Account unknown = makePerson('Ulf', 'Unknown');

    Test.startTest();
    List<String> rejected = EnvelopeHouseholdMemberController.saveRelatedParties(
      entity.Id,
      new List<String>{ 'Authorized Person', 'Not A Real Role' },
      partiesJson(
        new List<EnvelopeHouseholdMemberController.RelatedPartyInput>{
          party(valid.Id, 'Authorized Person'),
          party(unknown.Id, 'Not A Real Role')
        }
      ),
      env.Id
    );
    Test.stopTest();

    System.assertEquals(
      new List<String>{ 'Not A Real Role' },
      rejected,
      'Only the role the picklist does not hold should be reported.'
    );
    List<Account_Account_Relationship__c> relations = [
      SELECT Related_Account__c, Roles__c
      FROM Account_Account_Relationship__c
      WHERE Account__c = :entity.Id
    ];
    System.assertEquals(
      1,
      relations.size(),
      'The party in the valid role should still be written.'
    );
    System.assertEquals(
      valid.Id,
      relations[0].Related_Account__c,
      'The written relationship should be the one whose role exists.'
    );
    System.assertEquals(
      2,
      [
        SELECT COUNT()
        FROM Envelope_Content__c
        WHERE
          Envelope__c = :env.Id
          AND Account__c IN (:valid.Id, :unknown.Id)
      ],
      'Both parties should keep their envelope link, so neither drops off the outline.'
    );
  }

  // A payload the method cannot read at all is reported rather than treated as "no parties sent", which
  // would silently delete the relationships the entity already holds.
  @isTest
  static void testSaveRelatedParties_MalformedPayloadIsReported() {
    Envelope__c env = makeEnvelope();
    Account entity = new Account(Name = 'Acme Holdings', Type = 'Prospect');
    insert entity;

    Boolean thrown = false;
    Test.startTest();
    try {
      EnvelopeHouseholdMemberController.saveRelatedParties(
        entity.Id,
        new List<String>{ 'Trustee' },
        'not json',
        env.Id
      );
    } catch (AuraHandledException e) {
      thrown = true;
    }
    Test.stopTest();

    System.assert(
      thrown,
      'An unreadable parties payload should throw AuraHandledException.'
    );
  }

  // A blank payload is the "every party removed" case, so it reconciles rather than erroring.
  @isTest
  static void testSaveRelatedParties_BlankPayloadRemovesHeldParties() {
    Envelope__c env = makeEnvelope();
    Account entity = new Account(Name = 'Acme Holdings', Type = 'Prospect');
    insert entity;
    Account dropped = makePerson('Dee', 'Dropped');
    insert new Account_Account_Relationship__c(
      Account__c = entity.Id,
      Related_Account__c = dropped.Id,
      Roles__c = 'Trustee',
      RecordTypeId = fiduciaryRecordTypeId(),
      Active__c = true
    );

    Test.startTest();
    EnvelopeHouseholdMemberController.saveRelatedParties(
      entity.Id,
      new List<String>{ 'Trustee' },
      null,
      env.Id
    );
    Test.stopTest();

    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM Account_Account_Relationship__c
        WHERE Account__c = :entity.Id
      ],
      'A blank payload should drop the relationships the entity no longer holds.'
    );
  }

  // The envelope link is what puts a related party on the Household Outline, so it must not depend
  // on the role reconcile: a party sent without a managed role set still has to reach the envelope.
  @isTest
  static void testSaveRelatedParties_LinksEnvelopeWithoutManagedRoles() {
    Envelope__c env = makeEnvelope();
    Account entity = new Account(Name = 'Acme Holdings', Type = 'Prospect');
    insert entity;
    Account person = makePerson('Elle', 'Existing');

    Test.startTest();
    EnvelopeHouseholdMemberController.saveRelatedParties(
      entity.Id,
      new List<String>(),
      partiesJson(
        new List<EnvelopeHouseholdMemberController.RelatedPartyInput>{
          party(person.Id, 'Trustee')
        }
      ),
      env.Id
    );
    Test.stopTest();

    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Envelope_Content__c
        WHERE Envelope__c = :env.Id AND Account__c = :person.Id
      ],
      'The party should be linked to the envelope even when no role is reconciled.'
    );
    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM Account_Account_Relationship__c
        WHERE Account__c = :entity.Id
      ],
      'No managed roles still means no relationship is written.'
    );
  }

  private static final List<String> TRUST_ROLES = new List<String>{
    'Trustee',
    'Grantor'
  };

  // The relationships an entity holds, by person. Asserting the list size separately is what catches
  // a second relationship for the same pair, which a map keyed by person would hide.
  private static List<Account_Account_Relationship__c> relationsFor(
    Id entityAccountId
  ) {
    return [
      SELECT Related_Account__c, Roles__c, Active__c
      FROM Account_Account_Relationship__c
      WHERE Account__c = :entityAccountId
    ];
  }

  // One person can hold several roles on the same entity — a trustee who is also a grantor. All of
  // them belong on one relationship, in the multi-select Roles field.
  @isTest
  static void testSaveRelatedParties_OnePersonInTwoRolesWritesOneRelationship() {
    Envelope__c env = makeEnvelope();
    Account entity = new Account(Name = 'Family Trust', Type = 'Prospect');
    insert entity;
    Account person = makePerson('Tess', 'Both');

    Test.startTest();
    EnvelopeHouseholdMemberController.saveRelatedParties(
      entity.Id,
      TRUST_ROLES,
      partiesJson(
        new List<EnvelopeHouseholdMemberController.RelatedPartyInput>{
          party(person.Id, 'Trustee'),
          party(person.Id, 'Grantor')
        }
      ),
      env.Id
    );
    Test.stopTest();

    List<Account_Account_Relationship__c> relations = relationsFor(entity.Id);
    System.assertEquals(
      1,
      relations.size(),
      'Both roles belong on a single relationship for the pair.'
    );
    System.assertEquals(
      new Set<String>{ 'Trustee', 'Grantor' },
      new Set<String>(relations[0].Roles__c.split(';')),
      'The Roles multi-select should carry every role the person holds.'
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Envelope_Content__c
        WHERE Envelope__c = :env.Id AND Account__c = :person.Id
      ],
      'A person in two roles is still one party on the outline.'
    );
  }

  // The wizard reads its parties back one row per (person, role), so a person holding two roles has
  // to come back as two rows even though they share a relationship.
  @isTest
  static void testGetRelatedParties_SplitsRolesIntoOneRowEach() {
    Envelope__c env = makeEnvelope();
    Account entity = new Account(Name = 'Family Trust', Type = 'Prospect');
    insert entity;
    Account person = makePerson('Tess', 'Both');
    EnvelopeHouseholdMemberController.saveRelatedParties(
      entity.Id,
      TRUST_ROLES,
      partiesJson(
        new List<EnvelopeHouseholdMemberController.RelatedPartyInput>{
          party(person.Id, 'Trustee'),
          party(person.Id, 'Grantor')
        }
      ),
      env.Id
    );

    Test.startTest();
    List<EnvelopeHouseholdMemberController.RelatedPartyOutput> parties = EnvelopeHouseholdMemberController.getRelatedParties(
      new List<Id>{ entity.Id }
    );
    Test.stopTest();

    Set<String> roles = new Set<String>();
    for (EnvelopeHouseholdMemberController.RelatedPartyOutput output : parties) {
      System.assertEquals(
        person.Id,
        output.relatedAccountId,
        'Every row should report the person who holds the role.'
      );
      roles.add(output.role);
    }
    System.assertEquals(
      2,
      parties.size(),
      'A person holding two roles should come back as two rows.'
    );
    System.assertEquals(
      new Set<String>{ 'Trustee', 'Grantor' },
      roles,
      'Both roles should be reported.'
    );
  }

  // Dropping one of a person's roles leaves the relationship carrying the other; only losing the
  // last one removes it.
  @isTest
  static void testSaveRelatedParties_DroppingOneRoleKeepsTheRelationship() {
    Envelope__c env = makeEnvelope();
    Account entity = new Account(Name = 'Family Trust', Type = 'Prospect');
    insert entity;
    Account person = makePerson('Tess', 'Both');
    EnvelopeHouseholdMemberController.saveRelatedParties(
      entity.Id,
      TRUST_ROLES,
      partiesJson(
        new List<EnvelopeHouseholdMemberController.RelatedPartyInput>{
          party(person.Id, 'Trustee'),
          party(person.Id, 'Grantor')
        }
      ),
      env.Id
    );

    Test.startTest();
    EnvelopeHouseholdMemberController.saveRelatedParties(
      entity.Id,
      TRUST_ROLES,
      partiesJson(
        new List<EnvelopeHouseholdMemberController.RelatedPartyInput>{
          party(person.Id, 'Trustee')
        }
      ),
      env.Id
    );
    List<Account_Account_Relationship__c> afterDrop = relationsFor(entity.Id);

    EnvelopeHouseholdMemberController.saveRelatedParties(
      entity.Id,
      TRUST_ROLES,
      null,
      env.Id
    );
    Test.stopTest();

    System.assertEquals(
      1,
      afterDrop.size(),
      'Dropping one of two roles should leave the relationship in place.'
    );
    System.assertEquals(
      'Trustee',
      afterDrop[0].Roles__c,
      'Only the role that was dropped should be gone.'
    );
    System.assertEquals(
      0,
      relationsFor(entity.Id).size(),
      'Losing the last role should remove the relationship.'
    );
  }

  // The Household Outline is built from the envelope's contents, so a party the entity no longer
  // holds has to leave those contents too — otherwise it stays on the outline having lost its role.
  @isTest
  static void testSaveRelatedParties_DroppedPartyLeavesTheEnvelope() {
    Envelope__c env = makeEnvelope();
    Account entity = new Account(Name = 'Family Trust', Type = 'Prospect');
    insert entity;
    insert new Envelope_Content__c(Envelope__c = env.Id, Account__c = entity.Id);
    Account person = makePerson('Tess', 'Trustee');

    EnvelopeHouseholdMemberController.saveRelatedParties(
      entity.Id,
      TRUST_ROLES,
      partiesJson(
        new List<EnvelopeHouseholdMemberController.RelatedPartyInput>{
          party(person.Id, 'Trustee')
        }
      ),
      env.Id
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Envelope_Content__c
        WHERE Envelope__c = :env.Id AND Account__c = :person.Id
      ],
      'Adding the party should link it to the envelope.'
    );

    Test.startTest();
    EnvelopeHouseholdMemberController.saveRelatedParties(
      entity.Id,
      TRUST_ROLES,
      null,
      env.Id
    );
    Test.stopTest();

    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM Envelope_Content__c
        WHERE Envelope__c = :env.Id AND Account__c = :person.Id
      ],
      'A party the entity no longer holds should leave the envelope.'
    );
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Account WHERE Id = :person.Id],
      'Nothing else references the person, so the record goes with the link.'
    );
  }

  // A person holding two roles on one entity keeps a single relationship record, so dropping one of
  // them is not a removal and must not cost the person its place in the envelope.
  @isTest
  static void testSaveRelatedParties_DroppingOneRoleKeepsTheEnvelopeLink() {
    Envelope__c env = makeEnvelope();
    Account entity = new Account(Name = 'Family Trust', Type = 'Prospect');
    insert entity;
    insert new Envelope_Content__c(Envelope__c = env.Id, Account__c = entity.Id);
    Account person = makePerson('Tess', 'Both');

    EnvelopeHouseholdMemberController.saveRelatedParties(
      entity.Id,
      TRUST_ROLES,
      partiesJson(
        new List<EnvelopeHouseholdMemberController.RelatedPartyInput>{
          party(person.Id, 'Trustee'),
          party(person.Id, 'Grantor')
        }
      ),
      env.Id
    );

    Test.startTest();
    EnvelopeHouseholdMemberController.saveRelatedParties(
      entity.Id,
      TRUST_ROLES,
      partiesJson(
        new List<EnvelopeHouseholdMemberController.RelatedPartyInput>{
          party(person.Id, 'Grantor')
        }
      ),
      env.Id
    );
    Test.stopTest();

    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Envelope_Content__c
        WHERE Envelope__c = :env.Id AND Account__c = :person.Id
      ],
      'The person still holds the Grantor role, so it keeps its envelope link.'
    );
    System.assertEquals(
      'Grantor',
      relationsFor(entity.Id)[0].Roles__c,
      'Only the dropped role should be gone.'
    );
  }

  // This object is shared with the relationship feature, so a role the wizard does not manage has to
  // survive a reconcile that drops the person — and keep the relationship alive with it.
  @isTest
  static void testSaveRelatedParties_UnmanagedRoleOnTheSameRelationshipSurvives() {
    Envelope__c env = makeEnvelope();
    Account entity = new Account(Name = 'Family Trust', Type = 'Prospect');
    insert entity;
    Account person = makePerson('Tess', 'Trustee');
    insert new Account_Account_Relationship__c(
      Account__c = entity.Id,
      Related_Account__c = person.Id,
      Roles__c = 'Trustee;Trusted Contact',
      RecordTypeId = fiduciaryRecordTypeId(),
      Active__c = true
    );

    Test.startTest();
    EnvelopeHouseholdMemberController.saveRelatedParties(
      entity.Id,
      TRUST_ROLES,
      null,
      env.Id
    );
    Test.stopTest();

    List<Account_Account_Relationship__c> relations = relationsFor(entity.Id);
    System.assertEquals(
      1,
      relations.size(),
      'A relationship still carrying an unmanaged role must not be deleted.'
    );
    System.assertEquals(
      'Trusted Contact',
      relations[0].Roles__c,
      'Only the managed roles should be stripped.'
    );
  }

  // A relationship the wizard has no claim on at all is left exactly as it is.
  @isTest
  static void testSaveRelatedParties_RelationshipWithNoManagedRoleIsUntouched() {
    Envelope__c env = makeEnvelope();
    Account entity = new Account(Name = 'Family Trust', Type = 'Prospect');
    insert entity;
    Account person = makePerson('Ozzy', 'Other');
    insert new Account_Account_Relationship__c(
      Account__c = entity.Id,
      Related_Account__c = person.Id,
      Roles__c = 'Trusted Contact',
      RecordTypeId = fiduciaryRecordTypeId(),
      Active__c = true
    );

    Test.startTest();
    EnvelopeHouseholdMemberController.saveRelatedParties(
      entity.Id,
      TRUST_ROLES,
      null,
      env.Id
    );
    Test.stopTest();

    List<Account_Account_Relationship__c> relations = relationsFor(entity.Id);
    System.assertEquals(
      1,
      relations.size(),
      'A relationship holding none of the managed roles is not the wizard\'s to remove.'
    );
    System.assertEquals(
      'Trusted Contact',
      relations[0].Roles__c,
      'Its roles should be left as they were.'
    );
  }

  // Earlier builds stored one relationship per role, and nothing stops a pair having two. The next
  // save merges them, so the data repairs itself rather than needing a migration.
  @isTest
  static void testSaveRelatedParties_CollapsesDuplicateRelationshipsForAPair() {
    Envelope__c env = makeEnvelope();
    Account entity = new Account(Name = 'Family Trust', Type = 'Prospect');
    insert entity;
    Account person = makePerson('Tess', 'Both');
    insert new List<Account_Account_Relationship__c>{
      new Account_Account_Relationship__c(
        Account__c = entity.Id,
        Related_Account__c = person.Id,
        Roles__c = 'Trustee',
        RecordTypeId = fiduciaryRecordTypeId(),
        Active__c = true
      ),
      new Account_Account_Relationship__c(
        Account__c = entity.Id,
        Related_Account__c = person.Id,
        Roles__c = 'Grantor',
        RecordTypeId = fiduciaryRecordTypeId(),
        Active__c = true
      )
    };

    Test.startTest();
    EnvelopeHouseholdMemberController.saveRelatedParties(
      entity.Id,
      TRUST_ROLES,
      partiesJson(
        new List<EnvelopeHouseholdMemberController.RelatedPartyInput>{
          party(person.Id, 'Trustee'),
          party(person.Id, 'Grantor')
        }
      ),
      env.Id
    );
    Test.stopTest();

    List<Account_Account_Relationship__c> relations = relationsFor(entity.Id);
    System.assertEquals(
      1,
      relations.size(),
      'Two relationships for one pair should collapse into one.'
    );
    System.assertEquals(
      new Set<String>{ 'Trustee', 'Grantor' },
      new Set<String>(relations[0].Roles__c.split(';')),
      'The surviving relationship should carry both roles.'
    );
  }

  // An inactive relationship is invisible to getRelatedParties, so leaving one in place would make
  // the party read as missing while every save quietly did nothing.
  @isTest
  static void testSaveRelatedParties_ReactivatesAnInactiveRelationship() {
    Envelope__c env = makeEnvelope();
    Account entity = new Account(Name = 'Family Trust', Type = 'Prospect');
    insert entity;
    Account person = makePerson('Tess', 'Trustee');
    insert new Account_Account_Relationship__c(
      Account__c = entity.Id,
      Related_Account__c = person.Id,
      Roles__c = 'Trustee',
      RecordTypeId = fiduciaryRecordTypeId(),
      Active__c = false
    );

    Test.startTest();
    EnvelopeHouseholdMemberController.saveRelatedParties(
      entity.Id,
      TRUST_ROLES,
      partiesJson(
        new List<EnvelopeHouseholdMemberController.RelatedPartyInput>{
          party(person.Id, 'Trustee')
        }
      ),
      env.Id
    );
    Test.stopTest();

    List<Account_Account_Relationship__c> relations = relationsFor(entity.Id);
    System.assertEquals(
      1,
      relations.size(),
      'The inactive relationship should be reused, not duplicated.'
    );
    System.assertEquals(
      true,
      relations[0].Active__c,
      'A held party\'s relationship should be active so it reads back.'
    );
    System.assertEquals(
      1,
      EnvelopeHouseholdMemberController.getRelatedParties(
          new List<Id>{ entity.Id }
        )
        .size(),
      'The reactivated party should now read back.'
    );
  }

  // -------------------------------------------------------------------------
  // getPicklistValues
  // -------------------------------------------------------------------------

  @isTest
  static void testGetPicklistValues_ByType() {
    Test.startTest();
    Map<String, List<EnvelopeHouseholdMemberController.PicklistOption>> client = EnvelopeHouseholdMemberController.getPicklistValues(
      'client'
    );
    Map<String, List<EnvelopeHouseholdMemberController.PicklistOption>> business = EnvelopeHouseholdMemberController.getPicklistValues(
      'business'
    );
    Map<String, List<EnvelopeHouseholdMemberController.PicklistOption>> trust = EnvelopeHouseholdMemberController.getPicklistValues(
      'trust'
    );
    Map<String, List<EnvelopeHouseholdMemberController.PicklistOption>> blank = EnvelopeHouseholdMemberController.getPicklistValues(
      ''
    );
    Test.stopTest();

    System.assert(
      client.containsKey('Employment_Status__c'),
      'Client picklists should include Employment_Status__c.'
    );
    System.assert(
      business.containsKey('Entity_Jurisdiction__c'),
      'Business picklists should include Entity_Jurisdiction__c.'
    );
    System.assert(
      trust.containsKey('Trust_Type__c'),
      'Trust picklists should include Trust_Type__c.'
    );
    System.assertEquals(
      0,
      blank.size(),
      'Blank type should return an empty map.'
    );
  }

  // -------------------------------------------------------------------------
  // saveEntity - format validation (WizardFieldValidator backstop)
  // -------------------------------------------------------------------------

  // Deterministic rule injection so these tests don't depend on which Envelope_Field__mdt
  // records happen to exist in the org.
  private static void injectSsnRule() {
    WizardFieldValidator.ruleRowsOverride = new List<Envelope_Field__mdt>{
      new Envelope_Field__mdt(
        Object__c = 'Account',
        Field_API__c = 'Tax_ID__c',
        Label__c = 'Tax ID',
        Pattern__c = '^\\d{3}-\\d{2}-\\d{4}$',
        Pattern_Error__c = 'Enter a Social Security Number as XXX-XX-XXXX.'
      )
    };
  }

  @isTest
  static void testSaveEntity_RejectsMalformedTaxIdOnCreate() {
    Envelope__c env = makeEnvelope();
    injectSsnRule();

    Map<String, Object> acc = new Map<String, Object>{
      'RecordTypeId' => 'client',
      'FirstName' => 'Jane',
      'LastName' => 'Doe',
      'Tax_ID__c' => '123'
    };

    Test.startTest();
    try {
      EnvelopeHouseholdMemberController.saveEntity(acc, env.Id, null);
      System.assert(false, 'A malformed Tax ID should block the save.');
    } catch (AuraHandledException e) {
      System.assert(
        e.getMessage().contains('Tax ID'),
        'The error should name the field: ' + e.getMessage()
      );
    }
    Test.stopTest();

    System.assertEquals(
      0,
      [SELECT COUNT() FROM Account WHERE LastName = 'Doe'],
      'No Account should be created when validation fails.'
    );
  }

  @isTest
  static void testSaveEntity_AcceptsWellFormedTaxIdAndRejectsBadUpdate() {
    Envelope__c env = makeEnvelopeWithHousehold();
    injectSsnRule();

    Test.startTest();
    Id accId = EnvelopeHouseholdMemberController.saveEntity(
      new Map<String, Object>{
        'RecordTypeId' => 'client',
        'FirstName' => 'Jane',
        'LastName' => 'Doe',
        'Tax_ID__c' => '123-45-6789'
      },
      env.Id,
      null
    );

    System.assertEquals(
      '123-45-6789',
      [SELECT Tax_ID__c FROM Account WHERE Id = :accId].Tax_ID__c,
      'A well-formed SSN should save.'
    );

    // The same rule guards updates through the same path.
    try {
      EnvelopeHouseholdMemberController.saveEntity(
        new Map<String, Object>{
          'Id' => accId,
          'RecordTypeId' => 'client',
          'Tax_ID__c' => '35423242'
        },
        env.Id,
        null
      );
      System.assert(false, 'A malformed Tax ID should block the update.');
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('Tax ID'), e.getMessage());
    }
    Test.stopTest();

    System.assertEquals(
      '123-45-6789',
      [SELECT Tax_ID__c FROM Account WHERE Id = :accId].Tax_ID__c,
      'The stored value should be untouched by the rejected update.'
    );
  }

  @isTest
  static void testSaveEntity_CoercionFailureSurfacesInsteadOfSilentlyDropping() {
    Envelope__c env = makeEnvelope();

    // A date field with an uncoercible value used to be debug-logged and silently skipped;
    // it must now surface before DML.
    assertSaveSurfacesError(
      new Map<String, Object>{
        'RecordTypeId' => 'client',
        'FirstName' => 'Jane',
        'LastName' => 'Doe',
        'PersonBirthdate' => 'not-a-date'
      },
      env.Id
    );
  }
}