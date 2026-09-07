@isTest
private class EnvelopeBusinessAuthorizedSigneeTest {
  private static Id personRecordTypeId() {
    return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get('PersonAccount')
      .getRecordTypeId();
  }

  private static Id businessRecordTypeId() {
    return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get('Business')
      .getRecordTypeId();
  }

  private static Boolean businessAvailable() {
    Schema.RecordTypeInfo info = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get('Business');
    return info != null && info.isAvailable();
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

  private static Account newBusiness(String name) {
    Account business = new Account(
      Name = name,
      Type = 'Prospect',
      RecordTypeId = businessRecordTypeId()
    );
    insert business;
    return business;
  }

  // The business's profile document (created by EnvelopeProfileDocumentService when the business
  // becomes an owner). Made directly here to isolate the signee behavior under test.
  private static Required_Documents__c newBusinessProfile(Id businessId) {
    Required_Documents__c doc = new Required_Documents__c(
      Name = 'Acme - Business Client Consents and Disclosures',
      Business__c = businessId
    );
    insert doc;
    return doc;
  }

  // The relationship record type that permits the fiduciary roles ('Authorized Person', etc.) on the
  // restricted Roles__c picklist — the same one saveRelatedParties writes them under.
  private static Id fiduciaryRecordTypeId() {
    return Schema.SObjectType.Account_Account_Relationship__c.getRecordTypeInfosByDeveloperName()
      .get('Fiduciary_Legal')
      .getRecordTypeId();
  }

  private static void makeAuthorizedPerson(Id businessId, Id personId, Boolean active) {
    insert new Account_Account_Relationship__c(
      Account__c = businessId,
      Related_Account__c = personId,
      Roles__c = 'Authorized Person',
      RecordTypeId = fiduciaryRecordTypeId(),
      Active__c = active
    );
  }

  private static Integer signeeCount(Id docId) {
    return [SELECT COUNT() FROM Signee__c WHERE Required_Document__c = :docId];
  }

  // Authorized Persons that already exist become signees when the profile's signees are synced (the
  // "document added after the people" direction).
  @isTest
  static void testExistingAuthorizedPersonsBecomeSignees() {
    if (!businessAvailable()) {
      return;
    }
    Account business = newBusiness('Acme');
    Account ap1 = newPerson('Jane', 'Doe');
    Account ap2 = newPerson('John', 'Roe');
    makeAuthorizedPerson(business.Id, ap1.Id, true);
    makeAuthorizedPerson(business.Id, ap2.Id, true);
    Required_Documents__c doc = newBusinessProfile(business.Id);

    Test.startTest();
    EnvelopeProfileDocumentService.syncFiduciarySignees(
      new Set<Id>{ business.Id }
    );
    Test.stopTest();

    System.assertEquals(2, signeeCount(doc.Id), 'Both Authorized Persons sign the profile.');
    System.assertEquals(
      2,
      [
        SELECT COUNT()
        FROM Signee__c
        WHERE
          Required_Document__c = :doc.Id
          AND Account__c IN (:ap1.Id, :ap2.Id)
      ],
      'The signees are the two Authorized Persons.'
    );
  }

  // Only Authorized Persons sign: a Beneficial Owner is not added by this sync.
  @isTest
  static void testOnlyAuthorizedPersonsSign() {
    if (!businessAvailable()) {
      return;
    }
    Account business = newBusiness('Acme');
    Account authorized = newPerson('Jane', 'Doe');
    Account beneficial = newPerson('John', 'Roe');
    makeAuthorizedPerson(business.Id, authorized.Id, true);
    insert new Account_Account_Relationship__c(
      Account__c = business.Id,
      Related_Account__c = beneficial.Id,
      Roles__c = 'Beneficial Owner',
      RecordTypeId = fiduciaryRecordTypeId(),
      Active__c = true
    );
    Required_Documents__c doc = newBusinessProfile(business.Id);

    Test.startTest();
    EnvelopeProfileDocumentService.syncFiduciarySignees(
      new Set<Id>{ business.Id }
    );
    Test.stopTest();

    System.assertEquals(1, signeeCount(doc.Id), 'Only the Authorized Person signs.');
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Signee__c
        WHERE Required_Document__c = :doc.Id AND Account__c = :authorized.Id
      ],
      'The signee is the Authorized Person, not the Beneficial Owner.'
    );
  }

  // The sync is idempotent — running twice does not duplicate a signee.
  @isTest
  static void testSyncIsIdempotent() {
    if (!businessAvailable()) {
      return;
    }
    Account business = newBusiness('Acme');
    Account ap = newPerson('Jane', 'Doe');
    makeAuthorizedPerson(business.Id, ap.Id, true);
    Required_Documents__c doc = newBusinessProfile(business.Id);

    Test.startTest();
    EnvelopeProfileDocumentService.syncFiduciarySignees(
      new Set<Id>{ business.Id }
    );
    EnvelopeProfileDocumentService.syncFiduciarySignees(
      new Set<Id>{ business.Id }
    );
    Test.stopTest();

    System.assertEquals(1, signeeCount(doc.Id), 'No duplicate signee on re-run.');
  }

  // An inactive Authorized Person relationship does not produce a signee.
  @isTest
  static void testInactiveRelationshipIgnored() {
    if (!businessAvailable()) {
      return;
    }
    Account business = newBusiness('Acme');
    Account ap = newPerson('Jane', 'Doe');
    makeAuthorizedPerson(business.Id, ap.Id, false);
    Required_Documents__c doc = newBusinessProfile(business.Id);

    Test.startTest();
    EnvelopeProfileDocumentService.syncFiduciarySignees(
      new Set<Id>{ business.Id }
    );
    Test.stopTest();

    System.assertEquals(0, signeeCount(doc.Id), 'An inactive relationship adds no signee.');
  }

  // No Business profile yet -> nothing happens (the "people before the document" case is a no-op
  // until the document exists).
  @isTest
  static void testNoProfileIsNoOp() {
    if (!businessAvailable()) {
      return;
    }
    Account business = newBusiness('Acme');
    Account ap = newPerson('Jane', 'Doe');
    makeAuthorizedPerson(business.Id, ap.Id, true);

    Test.startTest();
    EnvelopeProfileDocumentService.syncFiduciarySignees(
      new Set<Id>{ business.Id }
    );
    Test.stopTest();

    System.assertEquals(
      0,
      [SELECT COUNT() FROM Signee__c],
      'With no profile document, no signee is created.'
    );
  }

  // ----------------------------------------------------------------------
  // Trust / Trustee
  // ----------------------------------------------------------------------

  private static Boolean trustAvailable() {
    Schema.RecordTypeInfo info = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get('Trust');
    return info != null && info.isAvailable();
  }

  private static Account newTrust(String name) {
    Account trust = new Account(
      Name = name,
      Type = 'Prospect',
      RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
        .get('Trust')
        .getRecordTypeId()
    );
    insert trust;
    return trust;
  }

  private static Required_Documents__c newTrustProfile(Id trustId) {
    Required_Documents__c doc = new Required_Documents__c(
      Name = 'Family Trust - Trust Client Consents and Disclosures',
      Trust__c = trustId
    );
    insert doc;
    return doc;
  }

  private static void makeRelatedParty(
    Id entityId,
    Id personId,
    String role,
    Boolean active
  ) {
    insert new Account_Account_Relationship__c(
      Account__c = entityId,
      Related_Account__c = personId,
      Roles__c = role,
      RecordTypeId = fiduciaryRecordTypeId(),
      Active__c = active
    );
  }

  // Trustees of a trust become signees on its Trust Client Consents and Disclosures profile.
  @isTest
  static void testTrusteesBecomeSignees() {
    if (!trustAvailable()) {
      return;
    }
    Account trust = newTrust('Family Trust');
    Account t1 = newPerson('Jane', 'Doe');
    Account t2 = newPerson('John', 'Roe');
    makeRelatedParty(trust.Id, t1.Id, 'Trustee', true);
    makeRelatedParty(trust.Id, t2.Id, 'Trustee', true);
    Required_Documents__c doc = newTrustProfile(trust.Id);

    Test.startTest();
    EnvelopeProfileDocumentService.syncFiduciarySignees(new Set<Id>{ trust.Id });
    Test.stopTest();

    System.assertEquals(2, signeeCount(doc.Id), 'Both Trustees sign the trust profile.');
  }

  // Only Trustees sign the trust profile: a Grantor is not added by this sync.
  @isTest
  static void testOnlyTrusteesSignTrustProfile() {
    if (!trustAvailable()) {
      return;
    }
    Account trust = newTrust('Family Trust');
    Account trustee = newPerson('Jane', 'Doe');
    Account grantor = newPerson('John', 'Roe');
    makeRelatedParty(trust.Id, trustee.Id, 'Trustee', true);
    makeRelatedParty(trust.Id, grantor.Id, 'Grantor', true);
    Required_Documents__c doc = newTrustProfile(trust.Id);

    Test.startTest();
    EnvelopeProfileDocumentService.syncFiduciarySignees(new Set<Id>{ trust.Id });
    Test.stopTest();

    System.assertEquals(1, signeeCount(doc.Id), 'Only the Trustee signs.');
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Signee__c
        WHERE Required_Document__c = :doc.Id AND Account__c = :trustee.Id
      ],
      'The signee is the Trustee, not the Grantor.'
    );
  }

  // ----------------------------------------------------------------------
  // Retirement Plan / Authorized Person
  // ----------------------------------------------------------------------

  private static Boolean retirementPlanAvailable() {
    Schema.RecordTypeInfo info = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get('Retirement_Plan');
    return info != null && info.isAvailable();
  }

  private static Account newRetirementPlan(String name) {
    Account plan = new Account(
      Name = name,
      Type = 'Prospect',
      RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
        .get('Retirement_Plan')
        .getRecordTypeId()
    );
    insert plan;
    return plan;
  }

  private static Required_Documents__c newRetirementPlanProfile(Id planId) {
    Required_Documents__c doc = new Required_Documents__c(
      Name = 'Acme 401k - Retirement Plan Client Consents and Disclosures',
      Retirement_Plan__c = planId
    );
    insert doc;
    return doc;
  }

  // Authorized Persons of a retirement plan become signees on its Retirement Plan Client Consents and
  // Disclosures profile.
  @isTest
  static void testRetirementPlanAuthorizedPersonsSign() {
    if (!retirementPlanAvailable()) {
      return;
    }
    Account plan = newRetirementPlan('Acme 401k');
    Account ap1 = newPerson('Jane', 'Doe');
    Account ap2 = newPerson('John', 'Roe');
    makeRelatedParty(plan.Id, ap1.Id, 'Authorized Person', true);
    makeRelatedParty(plan.Id, ap2.Id, 'Authorized Person', true);
    Required_Documents__c doc = newRetirementPlanProfile(plan.Id);

    Test.startTest();
    EnvelopeProfileDocumentService.syncFiduciarySignees(new Set<Id>{ plan.Id });
    Test.stopTest();

    System.assertEquals(
      2,
      signeeCount(doc.Id),
      'Both Authorized Persons sign the retirement plan profile.'
    );
  }

  @isTest
  static void testEmptyInputIsNoOp() {
    Test.startTest();
    EnvelopeProfileDocumentService.syncFiduciarySignees(null);
    EnvelopeProfileDocumentService.syncFiduciarySignees(new Set<Id>());
    Test.stopTest();
    System.assertEquals(0, [SELECT COUNT() FROM Signee__c], 'Empty input does nothing.');
  }
}