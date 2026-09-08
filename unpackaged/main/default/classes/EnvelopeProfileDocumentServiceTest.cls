@isTest
private class EnvelopeProfileDocumentServiceTest {
  private static Id personRecordTypeId() {
    return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get('PersonAccount')
      .getRecordTypeId();
  }

  private static Account newPerson(String first, String last) {
    Account person = new Account(
      FirstName = first,
      LastName = last,
      Type = 'Prospect',
      RecordTypeId = personRecordTypeId()
    );
    insert person;
    return person;
  }

  private static Envelope__c newEnvelope() {
    Envelope__c env = new Envelope__c(Name = 'Test Envelope');
    insert env;
    return env;
  }

  // A retirement plan that becomes an owner earns its own Consents and Disclosures profile — the
  // record type key must match the account's DeveloperName ('Retirement_Plan') for this to fire.
  @isTest
  static void testRetirementPlanEarnsProfile() {
    Schema.RecordTypeInfo info = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get('Retirement_Plan');
    if (info == null || !info.isAvailable()) {
      return;
    }
    Account plan = new Account(
      Name = 'Acme 401k',
      Type = 'Prospect',
      RecordTypeId = info.getRecordTypeId()
    );
    insert plan;
    Envelope__c env = newEnvelope();

    Test.startTest();
    EnvelopeProfileDocumentService.ensureProfileDocuments(
      new Set<Id>{ plan.Id },
      env.Id
    );
    // Re-running must not create a second profile (create-once must recognise the retirement plan).
    EnvelopeProfileDocumentService.ensureProfileDocuments(
      new Set<Id>{ plan.Id },
      env.Id
    );
    Test.stopTest();

    List<Required_Documents__c> docs = [
      SELECT Id, Name
      FROM Required_Documents__c
      WHERE Retirement_Plan__c = :plan.Id
    ];
    System.assertEquals(1, docs.size(), 'One retirement plan profile, created once.');
    System.assertEquals(
      'Acme 401k - Retirement Plan Client Consents and Disclosures',
      docs[0].Name,
      'Profile named from the plan.'
    );
  }

  // Owning an account (or DPI, or service) is what earns a person its client profile: the document
  // is created, named from the person, linked to the envelope, and the person is made its signee.
  @isTest
  static void testOwnerEarnsClientProfile() {
    Account person = newPerson('Jane', 'Doe');
    Envelope__c env = newEnvelope();

    Test.startTest();
    EnvelopeProfileDocumentService.ensureProfileDocuments(
      new Set<Id>{ person.Id },
      env.Id
    );
    Test.stopTest();

    List<Required_Documents__c> docs = [
      SELECT Id, Name, Person__c
      FROM Required_Documents__c
      WHERE Person__c = :person.Id
    ];
    System.assertEquals(1, docs.size(), 'An owner should earn one client profile.');
    System.assertEquals(
      'Jane Doe - Individual Client Consents and Disclosures',
      docs[0].Name,
      'The profile name is derived from the owner name.'
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Envelope_Content__c
        WHERE Envelope__c = :env.Id AND Required_Document__c = :docs[0].Id
      ],
      'The profile is linked to the envelope.'
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Signee__c
        WHERE Required_Document__c = :docs[0].Id AND Account__c = :person.Id
      ],
      'A person owner signs its own profile.'
    );
  }

  // A person owns many things but keeps a single profile: ensuring twice, and across two envelopes,
  // adds no second document, no duplicate signee, and only one link per envelope.
  @isTest
  static void testProfileIsCreatedOnce() {
    Account person = newPerson('Jane', 'Doe');
    Envelope__c envA = newEnvelope();
    Envelope__c envB = newEnvelope();

    Test.startTest();
    EnvelopeProfileDocumentService.ensureProfileDocuments(
      new Set<Id>{ person.Id },
      envA.Id
    );
    EnvelopeProfileDocumentService.ensureProfileDocuments(
      new Set<Id>{ person.Id },
      envA.Id
    );
    EnvelopeProfileDocumentService.ensureProfileDocuments(
      new Set<Id>{ person.Id },
      envB.Id
    );
    Test.stopTest();

    System.assertEquals(
      1,
      [SELECT COUNT() FROM Required_Documents__c WHERE Person__c = :person.Id],
      'An owner keeps exactly one profile no matter how many times it is ensured.'
    );
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Signee__c WHERE Account__c = :person.Id],
      'The self-signee is not duplicated.'
    );
    Id docId = [SELECT Id FROM Required_Documents__c WHERE Person__c = :person.Id]
      .Id;
    System.assertEquals(
      2,
      [
        SELECT COUNT()
        FROM Envelope_Content__c
        WHERE Required_Document__c = :docId
      ],
      'Each envelope gets its own single link to the shared profile.'
    );
  }

  // A signed profile (CCD_Signed_Date__c set) is never replaced by a fresh blank one.
  @isTest
  static void testSignedProfileIsNotRecreated() {
    Account person = newPerson('Jane', 'Doe');
    person.CCD_Signed_Date__c = Date.today();
    update person;
    Envelope__c env = newEnvelope();

    Test.startTest();
    EnvelopeProfileDocumentService.ensureProfileDocuments(
      new Set<Id>{ person.Id },
      env.Id
    );
    Test.stopTest();

    System.assertEquals(
      0,
      [SELECT COUNT() FROM Required_Documents__c WHERE Person__c = :person.Id],
      'A person whose CCD is already signed gets no new profile.'
    );
  }

  // Removing an owner's last ownership deletes its profile, along with the signee and link.
  @isTest
  static void testOrphanedProfileIsRemoved() {
    Account person = newPerson('Jane', 'Doe');
    Envelope__c env = newEnvelope();
    EnvelopeProfileDocumentService.ensureProfileDocuments(
      new Set<Id>{ person.Id },
      env.Id
    );
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Required_Documents__c WHERE Person__c = :person.Id],
      'Precondition: the owner has a profile.'
    );

    Test.startTest();
    // The person owns nothing now (no Financial_Account_Role, no Service).
    EnvelopeProfileDocumentService.removeOrphanedProfiles(new Set<Id>{ person.Id });
    Test.stopTest();

    System.assertEquals(
      0,
      [SELECT COUNT() FROM Required_Documents__c WHERE Person__c = :person.Id],
      'An owner that owns nothing loses its profile.'
    );
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Signee__c WHERE Account__c = :person.Id],
      'The profile signee is removed with the profile.'
    );
    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM Envelope_Content__c
        WHERE Envelope__c = :env.Id AND Required_Document__c != NULL
      ],
      'The profile envelope link is removed with the profile.'
    );
  }

  // A still-owner is left alone: holding a signing role on any account keeps the profile.
  @isTest
  static void testStillOwningKeepsProfile() {
    Account person = newPerson('Jane', 'Doe');
    Envelope__c env = newEnvelope();
    EnvelopeProfileDocumentService.ensureProfileDocuments(
      new Set<Id>{ person.Id },
      env.Id
    );

    Financial_Account__c fa = new Financial_Account__c(Name = 'Acct');
    insert fa;
    insert new Financial_Account_Role__c(
      Financial_Account__c = fa.Id,
      Account__c = person.Id,
      Role__c = 'Primary Owner'
    );

    Test.startTest();
    EnvelopeProfileDocumentService.removeOrphanedProfiles(new Set<Id>{ person.Id });
    Test.stopTest();

    System.assertEquals(
      1,
      [SELECT COUNT() FROM Required_Documents__c WHERE Person__c = :person.Id],
      'An owner still holding a signing role keeps its profile.'
    );
  }

  // Null / empty inputs are no-ops rather than errors.
  @isTest
  static void testEmptyInputsAreNoOps() {
    Test.startTest();
    EnvelopeProfileDocumentService.ensureProfileDocuments(null, null);
    EnvelopeProfileDocumentService.ensureProfileDocuments(new Set<Id>(), null);
    EnvelopeProfileDocumentService.removeOrphanedProfiles(null);
    EnvelopeProfileDocumentService.removeOrphanedProfiles(new Set<Id>());
    Test.stopTest();

    System.assertEquals(
      0,
      [SELECT COUNT() FROM Required_Documents__c],
      'No profiles are created or touched for empty input.'
    );
  }
}