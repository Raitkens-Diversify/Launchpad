@isTest
private class EnvelopeNewAccountAgreementServiceTest {
  private static final String INDIVIDUAL_NAME = 'New Account Agreement';

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

  private static Account newPerson(String first, String last) {
    Account p = new Account(
      FirstName = first,
      LastName = last,
      Type = 'Prospect',
      RecordTypeId = rtId('PersonAccount')
    );
    insert p;
    return p;
  }

  private static Account newEntity(String name, String dev) {
    Account e = new Account(Name = name, Type = 'Prospect', RecordTypeId = rtId(dev));
    insert e;
    return e;
  }

  private static Envelope__c newEnvelope() {
    Envelope__c env = new Envelope__c(Name = 'Env');
    insert env;
    return env;
  }

  private static Id newBdAccount(Id envelopeId, String name, List<Id> ownerIds) {
    return newAccount(envelopeId, name, 'BD', ownerIds);
  }

  private static Id newAccount(
    Id envelopeId,
    String name,
    String bdOrRia,
    List<Id> ownerIds
  ) {
    // Brokerage + account number avoid the unrelated setReportAcctNumber_AfterInsert read-only path
    // for BD accounts without them.
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
    String name = entityName + ' - New Account Agreement';
    return [SELECT COUNT() FROM Required_Documents__c WHERE Name = :name];
  }

  private static Integer signeesOn(String docName) {
    return [SELECT COUNT() FROM Signee__c WHERE Required_Document__r.Name = :docName];
  }

  // A single individual owner of a BD account gets one New Account Agreement, signed by that owner.
  @isTest
  static void testSingleIndividual() {
    Envelope__c env = newEnvelope();
    Account jane = newPerson('Jane', 'Doe');
    newBdAccount(env.Id, 'Acct 1', new List<Id>{ jane.Id });

    Test.startTest();
    EnvelopeNewAccountAgreementService.reconcile(env.Id);
    Test.stopTest();

    System.assertEquals(1, individualForms(), 'One agreement for one individual.');
    System.assertEquals(1, signeesOn(INDIVIDUAL_NAME), 'One signee.');
  }

  // Individuals pool two per form; a third starts a second form.
  @isTest
  static void testIndividualsPoolAndSplit() {
    Envelope__c env = newEnvelope();
    Account a = newPerson('A', 'One');
    Account b = newPerson('B', 'Two');
    Account c = newPerson('C', 'Three');
    newBdAccount(env.Id, 'Acct 1', new List<Id>{ a.Id, b.Id });
    newBdAccount(env.Id, 'Acct 2', new List<Id>{ c.Id });

    Test.startTest();
    EnvelopeNewAccountAgreementService.reconcile(env.Id);
    Test.stopTest();

    System.assertEquals(2, individualForms(), 'Three individuals need two forms (2 + 1).');
    System.assertEquals(3, signeesOn(INDIVIDUAL_NAME), 'Three signers total.');
  }

  // A non-BD (RIA) account earns no New Account Agreement.
  @isTest
  static void testNonBdIgnored() {
    Envelope__c env = newEnvelope();
    Account jane = newPerson('Jane', 'Doe');
    newAccount(env.Id, 'Acct 1', 'RIA', new List<Id>{ jane.Id });

    Test.startTest();
    EnvelopeNewAccountAgreementService.reconcile(env.Id);
    Test.stopTest();

    System.assertEquals(0, individualForms(), 'An RIA account earns no NAA.');
  }

  // A business owner gets ONE agreement signed by ALL its Authorized Persons (not one per person).
  @isTest
  static void testBusinessOneDocAllSigners() {
    if (!rtAvailable('Business')) {
      return;
    }
    Envelope__c env = newEnvelope();
    Account acme = newEntity('Acme', 'Business');
    Account ap1 = newPerson('Jane', 'Doe');
    Account ap2 = newPerson('John', 'Roe');
    makeParty(acme.Id, ap1.Id, 'Authorized Person');
    makeParty(acme.Id, ap2.Id, 'Authorized Person');
    newBdAccount(env.Id, 'Acme Acct', new List<Id>{ acme.Id });

    Test.startTest();
    EnvelopeNewAccountAgreementService.reconcile(env.Id);
    Test.stopTest();

    System.assertEquals(1, entityForms('Acme'), 'One document for the business.');
    System.assertEquals(
      2,
      signeesOn('Acme - New Account Agreement'),
      'Both Authorized Persons sign the one document.'
    );
  }

  // A business with no parties yet still gets its agreement, signee-less ("To be assigned..."); it
  // fills in and reconciles as parties come and go.
  @isTest
  static void testBusinessTbdThenSignersReconcile() {
    if (!rtAvailable('Business')) {
      return;
    }
    Envelope__c env = newEnvelope();
    Account acme = newEntity('Acme', 'Business');
    newBdAccount(env.Id, 'Acme Acct', new List<Id>{ acme.Id });

    Test.startTest();
    EnvelopeNewAccountAgreementService.reconcile(env.Id);
    System.assertEquals(1, entityForms('Acme'), 'Agreement created with no parties.');
    System.assertEquals(0, signeesOn('Acme - New Account Agreement'), 'To be assigned.');

    Account ap1 = newPerson('Jane', 'Doe');
    Account ap2 = newPerson('John', 'Roe');
    makeParty(acme.Id, ap1.Id, 'Authorized Person');
    makeParty(acme.Id, ap2.Id, 'Authorized Person');
    EnvelopeNewAccountAgreementService.reconcile(env.Id);
    System.assertEquals(1, entityForms('Acme'), 'Still one document.');
    System.assertEquals(2, signeesOn('Acme - New Account Agreement'), 'Both parties now sign.');

    // Deactivate one party; the agreement drops that signee.
    Account_Account_Relationship__c rel = [
      SELECT Id
      FROM Account_Account_Relationship__c
      WHERE Account__c = :acme.Id AND Related_Account__c = :ap2.Id
      LIMIT 1
    ];
    rel.Active__c = false;
    update rel;
    EnvelopeNewAccountAgreementService.reconcile(env.Id);
    Test.stopTest();

    System.assertEquals(1, signeesOn('Acme - New Account Agreement'), 'Down to one signer.');
  }

  // A trust owner gets one "<Trust> - New Account Agreement" signed by its Trustees.
  @isTest
  static void testTrustTrusteesOneDoc() {
    if (!rtAvailable('Trust')) {
      return;
    }
    Envelope__c env = newEnvelope();
    Account trust = newEntity('Family Trust', 'Trust');
    Account t1 = newPerson('Jane', 'Doe');
    Account t2 = newPerson('John', 'Roe');
    makeParty(trust.Id, t1.Id, 'Trustee');
    makeParty(trust.Id, t2.Id, 'Trustee');
    newBdAccount(env.Id, 'Trust Acct', new List<Id>{ trust.Id });

    Test.startTest();
    EnvelopeNewAccountAgreementService.reconcile(env.Id);
    Test.stopTest();

    System.assertEquals(1, entityForms('Family Trust'), 'One trust agreement.');
    System.assertEquals(2, signeesOn('Family Trust - New Account Agreement'), 'Both Trustees sign it.');
  }

  // Idempotent.
  @isTest
  static void testIdempotent() {
    Envelope__c env = newEnvelope();
    Account jane = newPerson('Jane', 'Doe');
    Account bob = newPerson('Bob', 'Roe');
    newBdAccount(env.Id, 'Acct 1', new List<Id>{ jane.Id, bob.Id });

    Test.startTest();
    EnvelopeNewAccountAgreementService.reconcile(env.Id);
    EnvelopeNewAccountAgreementService.reconcile(env.Id);
    Test.stopTest();

    System.assertEquals(1, individualForms(), 'No duplicate on re-run.');
    System.assertEquals(2, signeesOn(INDIVIDUAL_NAME), 'Still two signers.');
  }

  // Removing the account clears the agreement.
  @isTest
  static void testRemovalClears() {
    Envelope__c env = newEnvelope();
    Account jane = newPerson('Jane', 'Doe');
    Id acct = newBdAccount(env.Id, 'Acct 1', new List<Id>{ jane.Id });
    EnvelopeNewAccountAgreementService.reconcile(env.Id);
    System.assertEquals(1, individualForms(), 'Precondition: one form.');

    delete [
      SELECT Id
      FROM Envelope_Content__c
      WHERE Wizard_Financial_Account__c = :acct
    ];

    Test.startTest();
    EnvelopeNewAccountAgreementService.reconcile(env.Id);
    Test.stopTest();

    System.assertEquals(0, individualForms(), 'Removed once the BD account is gone.');
  }

  @isTest
  static void testNullEnvelopeNoOp() {
    Test.startTest();
    EnvelopeNewAccountAgreementService.reconcile(null);
    Test.stopTest();
    System.assertEquals(0, individualForms(), 'Null envelope creates nothing.');
  }
}