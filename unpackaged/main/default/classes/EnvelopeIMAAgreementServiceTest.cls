@isTest
private class EnvelopeIMAAgreementServiceTest {
  private static final String INDIVIDUAL_NAME = 'Investment Management Agreement';

  private static Id rtId(String dev) {
    return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get(dev)
      .getRecordTypeId();
  }

  private static Boolean rtAvailable(String dev) {
    Schema.RecordTypeInfo info = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get(dev);
    return info != null && info.isAvailable();
  }

  private static Id fiduciaryRtId() {
    return Schema.SObjectType.Account_Account_Relationship__c.getRecordTypeInfosByDeveloperName()
      .get('Fiduciary_Legal')
      .getRecordTypeId();
  }

  private static Id newHousehold() {
    Account hh = new Account(Name = 'HH', RecordTypeId = rtId('Household'));
    insert hh;
    return hh.Id;
  }

  private static Account newPerson(String first, String last, Date imaSigned) {
    Account p = new Account(
      FirstName = first,
      LastName = last,
      Type = 'Prospect',
      RecordTypeId = rtId('PersonAccount'),
      IMA_Signed_Date__c = imaSigned
    );
    insert p;
    return p;
  }

  private static Account newEntity(String name, String dev, Date imaSigned) {
    Account e = new Account(
      Name = name,
      Type = 'Prospect',
      RecordTypeId = rtId(dev),
      IMA_Signed_Date__c = imaSigned
    );
    insert e;
    return e;
  }

  private static Envelope__c newEnvelope() {
    Envelope__c env = new Envelope__c(Name = 'Env');
    insert env;
    return env;
  }

  private static Id newRiaAccount(Id envelopeId, String name, List<Id> ownerIds) {
    return newAccount(envelopeId, name, 'RIA', ownerIds);
  }

  private static Id newAccount(
    Id envelopeId,
    String name,
    String bdOrRia,
    List<Id> ownerIds
  ) {
    // Brokerage + account number set to avoid an unrelated after-insert trigger path
    // (setReportAcctNumber_AfterInsert) that mutates read-only records for BD accounts without them.
    Financial_Account__c fa = new Financial_Account__c(
      Name = name,
      BD_or_RIA__c = bdOrRia,
      Brokerage__c = true,
      Account_Number__c = '00012345',
      Household__c = newHousehold()
    );
    insert fa;
    insert new Envelope_Content__c(
      Envelope__c = envelopeId,
      Wizard_Financial_Account__c = fa.Id
    );
    List<Financial_Account_Role__c> roles = new List<Financial_Account_Role__c>();
    for (Id ownerId : ownerIds) {
      roles.add(
        new Financial_Account_Role__c(
          Financial_Account__c = fa.Id,
          Account__c = ownerId,
          Role__c = 'Primary Owner'
        )
      );
    }
    if (!roles.isEmpty()) {
      insert roles;
    }
    return fa.Id;
  }

  private static void makeParty(Id entityId, Id personId, String role) {
    insert new Account_Account_Relationship__c(
      Account__c = entityId,
      Related_Account__c = personId,
      Roles__c = role,
      RecordTypeId = fiduciaryRtId(),
      Active__c = true
    );
  }

  private static Integer individualForms() {
    return [SELECT COUNT() FROM Required_Documents__c WHERE Name = :INDIVIDUAL_NAME];
  }

  private static Integer entityForms(String entityName) {
    String name = entityName + ' - Investment Management Agreement';
    return [SELECT COUNT() FROM Required_Documents__c WHERE Name = :name];
  }

  private static Integer signeesOn(String docName) {
    return [
      SELECT COUNT()
      FROM Signee__c
      WHERE Required_Document__r.Name = :docName
    ];
  }

  // A single individual owner of an RIA account earns one Investment Management Agreement, signed by
  // that owner.
  @isTest
  static void testSingleIndividual() {
    Envelope__c env = newEnvelope();
    Account jane = newPerson('Jane', 'Doe', null);
    newRiaAccount(env.Id, 'Acct 1', new List<Id>{ jane.Id });

    Test.startTest();
    EnvelopeIMAAgreementService.reconcile(env.Id);
    Test.stopTest();

    System.assertEquals(1, individualForms(), 'One IMA for one individual.');
    System.assertEquals(1, signeesOn(INDIVIDUAL_NAME), 'One signee.');
  }

  // Two individuals from different RIA accounts pool onto one form (two signers).
  @isTest
  static void testTwoIndividualsPool() {
    Envelope__c env = newEnvelope();
    Account jane = newPerson('Jane', 'Doe', null);
    Account bob = newPerson('Bob', 'Roe', null);
    newRiaAccount(env.Id, 'Acct 1', new List<Id>{ jane.Id });
    newRiaAccount(env.Id, 'Acct 2', new List<Id>{ bob.Id });

    Test.startTest();
    EnvelopeIMAAgreementService.reconcile(env.Id);
    Test.stopTest();

    System.assertEquals(1, individualForms(), 'Two individuals share one form.');
    System.assertEquals(2, signeesOn(INDIVIDUAL_NAME), 'Both are signers on it.');
  }

  // A third individual starts a second form.
  @isTest
  static void testThreeIndividualsSplit() {
    Envelope__c env = newEnvelope();
    Account a = newPerson('A', 'One', null);
    Account b = newPerson('B', 'Two', null);
    Account c = newPerson('C', 'Three', null);
    newRiaAccount(env.Id, 'Acct 1', new List<Id>{ a.Id, b.Id });
    newRiaAccount(env.Id, 'Acct 2', new List<Id>{ c.Id });

    Test.startTest();
    EnvelopeIMAAgreementService.reconcile(env.Id);
    Test.stopTest();

    System.assertEquals(2, individualForms(), 'Three individuals need two forms (2 + 1).');
    System.assertEquals(3, signeesOn(INDIVIDUAL_NAME), 'Three signers across the two forms.');
  }

  // An individual who has already signed (IMA_Signed_Date set) is not included.
  @isTest
  static void testSignedIndividualExcluded() {
    Envelope__c env = newEnvelope();
    Account jane = newPerson('Jane', 'Doe', Date.today());
    newRiaAccount(env.Id, 'Acct 1', new List<Id>{ jane.Id });

    Test.startTest();
    EnvelopeIMAAgreementService.reconcile(env.Id);
    Test.stopTest();

    System.assertEquals(0, individualForms(), 'A signed individual earns no IMA.');
  }

  // A non-RIA account earns no IMA.
  @isTest
  static void testNonRiaIgnored() {
    Envelope__c env = newEnvelope();
    Account jane = newPerson('Jane', 'Doe', null);
    newAccount(env.Id, 'Acct 1', 'BD', new List<Id>{ jane.Id });

    Test.startTest();
    EnvelopeIMAAgreementService.reconcile(env.Id);
    Test.stopTest();

    System.assertEquals(0, individualForms(), 'A BD account earns no IMA.');
  }

  // Reconcile is idempotent — running twice does not duplicate forms.
  @isTest
  static void testIdempotent() {
    Envelope__c env = newEnvelope();
    Account jane = newPerson('Jane', 'Doe', null);
    Account bob = newPerson('Bob', 'Roe', null);
    newRiaAccount(env.Id, 'Acct 1', new List<Id>{ jane.Id, bob.Id });

    Test.startTest();
    EnvelopeIMAAgreementService.reconcile(env.Id);
    EnvelopeIMAAgreementService.reconcile(env.Id);
    Test.stopTest();

    System.assertEquals(1, individualForms(), 'No duplicate on re-run.');
    System.assertEquals(2, signeesOn(INDIVIDUAL_NAME), 'Still two signers.');
  }

  // A business owner's Authorized Persons each get their own "<Business> - Investment Management
  // Agreement", not pooled and not mixed with individuals.
  @isTest
  static void testBusinessRelatedPartiesGetOwnForms() {
    if (!rtAvailable('Business')) {
      return;
    }
    Envelope__c env = newEnvelope();
    Account acme = newEntity('Acme', 'Business', null);
    Account ap1 = newPerson('Jane', 'Doe', null);
    Account ap2 = newPerson('John', 'Roe', null);
    makeParty(acme.Id, ap1.Id, 'Authorized Person');
    makeParty(acme.Id, ap2.Id, 'Authorized Person');
    // An individual owner in the same envelope, to prove they are not grouped with the entity's people.
    Account solo = newPerson('Solo', 'Owner', null);
    newRiaAccount(env.Id, 'Acme Acct', new List<Id>{ acme.Id });
    newRiaAccount(env.Id, 'Solo Acct', new List<Id>{ solo.Id });

    Test.startTest();
    EnvelopeIMAAgreementService.reconcile(env.Id);
    Test.stopTest();

    System.assertEquals(2, entityForms('Acme'), 'One IMA per Authorized Person of the business.');
    System.assertEquals(
      2,
      signeesOn('Acme - Investment Management Agreement'),
      'One signee per entity form, two Authorized Persons.'
    );
    System.assertEquals(1, individualForms(), 'The individual owner has a separate pooled form.');
  }

  // A business that owns an RIA account but has no Authorized Persons yet still gets its agreement,
  // with no signee (shown as "To be assigned..."), and it fills in once a party is added.
  @isTest
  static void testBusinessWithNoPartiesIsToBeAssigned() {
    if (!rtAvailable('Business')) {
      return;
    }
    Envelope__c env = newEnvelope();
    Account acme = newEntity('Acme', 'Business', null);
    newRiaAccount(env.Id, 'Acme Acct', new List<Id>{ acme.Id });

    Test.startTest();
    EnvelopeIMAAgreementService.reconcile(env.Id);
    System.assertEquals(1, entityForms('Acme'), 'The business agreement is created with no parties.');
    System.assertEquals(
      0,
      signeesOn('Acme - Investment Management Agreement'),
      'It has no signee yet — "To be assigned...".'
    );

    // Add an Authorized Person; the agreement now carries that signer.
    Account ap = newPerson('Jane', 'Doe', null);
    makeParty(acme.Id, ap.Id, 'Authorized Person');
    EnvelopeIMAAgreementService.reconcile(env.Id);
    Test.stopTest();

    System.assertEquals(1, entityForms('Acme'), 'Still one agreement.');
    System.assertEquals(
      1,
      signeesOn('Acme - Investment Management Agreement'),
      'The Authorized Person is now the signer.'
    );
  }

  // A trust owner's Trustees each get their own "<Trust> - Investment Management Agreement".
  @isTest
  static void testTrustTrusteesGetOwnForms() {
    if (!rtAvailable('Trust')) {
      return;
    }
    Envelope__c env = newEnvelope();
    Account trust = newEntity('Family Trust', 'Trust', null);
    Account t1 = newPerson('Jane', 'Doe', null);
    makeParty(trust.Id, t1.Id, 'Trustee');
    newRiaAccount(env.Id, 'Trust Acct', new List<Id>{ trust.Id });

    Test.startTest();
    EnvelopeIMAAgreementService.reconcile(env.Id);
    Test.stopTest();

    System.assertEquals(1, entityForms('Family Trust'), 'The Trustee gets a trust IMA.');
  }

  // Removing the account (unlinking it) removes the individual's form on the next reconcile.
  @isTest
  static void testRemovalClearsForms() {
    Envelope__c env = newEnvelope();
    Account jane = newPerson('Jane', 'Doe', null);
    Id acct = newRiaAccount(env.Id, 'Acct 1', new List<Id>{ jane.Id });
    EnvelopeIMAAgreementService.reconcile(env.Id);
    System.assertEquals(1, individualForms(), 'Precondition: one form.');

    delete [
      SELECT Id
      FROM Envelope_Content__c
      WHERE Wizard_Financial_Account__c = :acct
    ];

    Test.startTest();
    EnvelopeIMAAgreementService.reconcile(env.Id);
    Test.stopTest();

    System.assertEquals(0, individualForms(), 'The form is removed once the RIA account is gone.');
  }

  @isTest
  static void testNullEnvelopeNoOp() {
    Test.startTest();
    EnvelopeIMAAgreementService.reconcile(null);
    Test.stopTest();
    System.assertEquals(0, individualForms(), 'Null envelope creates nothing.');
  }
}