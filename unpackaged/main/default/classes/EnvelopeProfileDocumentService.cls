public with sharing class EnvelopeProfileDocumentService {
  // The Financial_Account_Role__c roles that make their holder an owner for profile purposes. Kept
  // in step with EnvelopeHouseholdMemberController.SIGNING_ACCOUNT_ROLES: those are the roles whose
  // holders sign the account's paperwork, and they are exactly the ones a profile is owed for.
  // Beneficiaries and other roles do not earn a profile.
  private static final Set<String> OWNER_ROLES = new Set<String>{
    'Primary Owner',
    'Joint Owner'
  };

  // The profile shape for each owner record type: the Required_Documents__c lookup the profile
  // hangs off, the suffix appended to the owner's name, and whether the owner signs its own
  // profile. A Retirement Plan is deliberately absent — Required_Documents__c carries no lookup to
  // one, so it can hold no profile — as is any record type that is never an entity here.
  private class ProfileShape {
    String lookupField;
    String nameSuffix;
    Boolean ownerSigns;
    ProfileShape(String lookupField, String nameSuffix, Boolean ownerSigns) {
      this.lookupField = lookupField;
      this.nameSuffix = nameSuffix;
      this.ownerSigns = ownerSigns;
    }
  }

  private static final Map<String, ProfileShape> SHAPE_BY_RECORD_TYPE = new Map<String, ProfileShape>{
    'PersonAccount' => new ProfileShape('Person__c', ' - Individual Client Consents and Disclosures', true),
    'Business' => new ProfileShape('Business__c', ' - Business Client Consents and Disclosures', false),
    'Trust' => new ProfileShape('Trust__c', ' - Trust Client Consents and Disclosures', false),
    'Retirement Plan' => new ProfileShape('Retirement_Plan__c', ' - Retirement Plan Client Consents and Disclosures', false)
  };

  // Ensures each owner has its profile document, linked to the envelope, with the owner as a signee
  // on a person profile. Idempotent and create-once: an owner keeps a single profile no matter how
  // many accounts, DPIs or services it owns, so this can be called after every ownership change.
  //
  // An owner whose CCD_Signed_Date__c is already set is skipped — the profile has been signed, and a
  // new blank one must not replace it. Record types with no profile shape (a Retirement Plan) are
  // skipped too. A blank envelopeId means the profile is created but not linked to any envelope.
  public static void ensureProfileDocuments(
    Set<Id> ownerAccountIds,
    Id envelopeId
  ) {
    if (ownerAccountIds == null || ownerAccountIds.isEmpty()) {
      return;
    }

    // The owners eligible for a profile, keyed by Id: a known record type whose profile has not
    // already been signed.
    Map<Id, Account> eligibleById = new Map<Id, Account>();
    for (Account owner : [
      SELECT Id, Name, RecordType.DeveloperName, CCD_Signed_Date__c
      FROM Account
      WHERE Id IN :ownerAccountIds
    ]) {
      if (!SHAPE_BY_RECORD_TYPE.containsKey(owner.RecordType.DeveloperName)) {
        continue;
      }
      if (owner.CCD_Signed_Date__c != null) {
        continue;
      }
      eligibleById.put(owner.Id, owner);
    }
    if (eligibleById.isEmpty()) {
      return;
    }

    // Owner Id -> the profile document it already holds. Read so a create-once check can skip owners
    // that have one, and so an existing profile can still be linked to this envelope and given its
    // signee when either is missing.
    Map<Id, Id> docIdByOwner = new Map<Id, Id>();
    for (Required_Documents__c doc : [
      SELECT Id, Person__c, Business__c, Trust__c
      FROM Required_Documents__c
      WHERE
        Person__c IN :eligibleById.keySet()
        OR Business__c IN :eligibleById.keySet()
        OR Trust__c IN :eligibleById.keySet()
        OR Retirement_Plan__c IN :eligibleById.keySet()
    ]) {
      Id ownerId = doc.Person__c != null
        ? doc.Person__c
        : (doc.Business__c != null ? doc.Business__c : doc.Trust__c);
      if (ownerId != null && !docIdByOwner.containsKey(ownerId)) {
        docIdByOwner.put(ownerId, doc.Id);
      }
    }

    // Insert a profile for each eligible owner that has none. The owner order is tracked alongside
    // the insert so the new Ids can be folded back into docIdByOwner for the envelope link and
    // signee steps below.
    List<Required_Documents__c> toInsert = new List<Required_Documents__c>();
    List<Id> insertOwnerOrder = new List<Id>();
    for (Id ownerId : eligibleById.keySet()) {
      if (docIdByOwner.containsKey(ownerId)) {
        continue;
      }
      Account owner = eligibleById.get(ownerId);
      ProfileShape shape = SHAPE_BY_RECORD_TYPE.get(owner.RecordType.DeveloperName);
      Required_Documents__c doc = new Required_Documents__c(
        Name = owner.Name + shape.nameSuffix
      );
      doc.put(shape.lookupField, ownerId);
      toInsert.add(doc);
      insertOwnerOrder.add(ownerId);
    }
    if (!toInsert.isEmpty()) {
      insert toInsert;
      for (Integer i = 0; i < toInsert.size(); i++) {
        docIdByOwner.put(insertOwnerOrder[i], toInsert[i].Id);
      }
    }

    linkDocsToEnvelope(new List<Id>(docIdByOwner.values()), envelopeId);
    ensureSelfSignees(eligibleById, docIdByOwner);

    // A Business profile is signed by its Authorized Persons and a Trust profile by its Trustees, so
    // any that already exist become signees the moment the profile does. (When one is added later,
    // saveRelatedParties calls this again.) An owner with neither profile is simply skipped.
    syncFiduciarySignees(eligibleById.keySet());
  }

  // The fiduciary role that signs each entity profile, keyed by the Required_Documents__c lookup the
  // profile hangs off: a business's "Business Client Consents and Disclosures" is signed by its
  // Authorized Persons, a trust's "Trust Client Consents and Disclosures" by its Trustees, and a
  // retirement plan's "Retirement Plan Client Consents and Disclosures" by its Authorized Persons. A
  // person profile is self-signed (handled in ensureSelfSignees) and is not here.
  private static final Map<String, String> SIGNING_ROLE_BY_ENTITY_LOOKUP = new Map<String, String>{
    'Business__c' => 'Authorized Person',
    'Trust__c' => 'Trustee',
    'Retirement_Plan__c' => 'Authorized Person'
  };

  // Ensures every person holding an entity profile's signing fiduciary role is a signee on that
  // profile — a business's Authorized Persons on its profile, a trust's Trustees on its. Additive and
  // idempotent: it adds the ones that are missing and leaves existing signees alone, so it is safe to
  // call after the profile is created and after the entity's related parties change. An id with no
  // Business or Trust profile — a person, or an entity not yet an owner — matches nothing and is
  // skipped.
  public static void syncFiduciarySignees(Set<Id> entityAccountIds) {
    if (entityAccountIds == null || entityAccountIds.isEmpty()) {
      return;
    }

    // The Business/Trust profile documents grouped by entity, plus the fiduciary role that signs each
    // entity (Authorized Person for a business, Trustee for a trust).
    Map<Id, List<Id>> docsByEntity = new Map<Id, List<Id>>();
    Map<Id, String> roleByEntity = new Map<Id, String>();
    Set<Id> docIds = new Set<Id>();
    for (Required_Documents__c doc : [
      SELECT Id, Business__c, Trust__c, Retirement_Plan__c
      FROM Required_Documents__c
      WHERE
        Business__c IN :entityAccountIds
        OR Trust__c IN :entityAccountIds
        OR Retirement_Plan__c IN :entityAccountIds
    ]) {
      Id entityId;
      String role;
      if (doc.Business__c != null) {
        entityId = doc.Business__c;
        role = SIGNING_ROLE_BY_ENTITY_LOOKUP.get('Business__c');
      } else if (doc.Trust__c != null) {
        entityId = doc.Trust__c;
        role = SIGNING_ROLE_BY_ENTITY_LOOKUP.get('Trust__c');
      } else if (doc.Retirement_Plan__c != null) {
        entityId = doc.Retirement_Plan__c;
        role = SIGNING_ROLE_BY_ENTITY_LOOKUP.get('Retirement_Plan__c');
      } else {
        continue;
      }
      if (!docsByEntity.containsKey(entityId)) {
        docsByEntity.put(entityId, new List<Id>());
      }
      docsByEntity.get(entityId).add(doc.Id);
      roleByEntity.put(entityId, role);
      docIds.add(doc.Id);
    }
    if (docIds.isEmpty()) {
      return;
    }

    // The people holding each entity's signing role, from its active fiduciary relationships. Roles__c
    // is a multi-select, so the role is matched against every value the relationship carries.
    Map<Id, Set<Id>> signersByEntity = new Map<Id, Set<Id>>();
    for (Account_Account_Relationship__c relation : [
      SELECT Account__c, Related_Account__c, Roles__c
      FROM Account_Account_Relationship__c
      WHERE
        Account__c IN :docsByEntity.keySet()
        AND Related_Account__c != NULL
        AND Active__c = TRUE
    ]) {
      String requiredRole = roleByEntity.get(relation.Account__c);
      if (requiredRole == null || !rolesContain(relation.Roles__c, requiredRole)) {
        continue;
      }
      if (!signersByEntity.containsKey(relation.Account__c)) {
        signersByEntity.put(relation.Account__c, new Set<Id>());
      }
      signersByEntity.get(relation.Account__c).add(relation.Related_Account__c);
    }
    if (signersByEntity.isEmpty()) {
      return;
    }

    // Existing signees, so only the missing ones are added.
    Set<String> alreadySigning = new Set<String>();
    for (Signee__c signee : [
      SELECT Account__c, Required_Document__c
      FROM Signee__c
      WHERE Required_Document__c IN :docIds
    ]) {
      alreadySigning.add(
        String.valueOf(signee.Account__c) +
        '|' +
        String.valueOf(signee.Required_Document__c)
      );
    }

    List<Signee__c> toInsert = new List<Signee__c>();
    for (Id entityId : docsByEntity.keySet()) {
      Set<Id> persons = signersByEntity.get(entityId);
      if (persons == null) {
        continue;
      }
      for (Id docId : docsByEntity.get(entityId)) {
        for (Id personId : persons) {
          String key = String.valueOf(personId) + '|' + String.valueOf(docId);
          if (!alreadySigning.contains(key)) {
            alreadySigning.add(key);
            toInsert.add(
              new Signee__c(Required_Document__c = docId, Account__c = personId)
            );
          }
        }
      }
    }
    if (!toInsert.isEmpty()) {
      insert toInsert;
    }
  }

  // True when a multi-select Roles__c value carries the given role. Split on the ';' separator the
  // field stores, trimming each entry so a stray space cannot hide a match.
  private static Boolean rolesContain(String roles, String role) {
    if (String.isBlank(roles)) {
      return false;
    }
    for (String value : roles.split(';')) {
      if (value.trim() == role) {
        return true;
      }
    }
    return false;
  }

  // Deletes the profile of any owner in the set that no longer owns anything — no account or DPI
  // signing role, and no service as primary or secondary owner. An owner still holding one keeps its
  // profile. Called with the owners an ownership change removed, so a person taken off one account
  // but still on another is correctly left alone.
  //
  // A profile already handed to DocuSign (DocuSign_Envelope__c set) is left in place: it is in
  // flight, and deleting it would discard a sent request. Its signees and envelope links go with it
  // for the profiles that are deleted.
  public static void removeOrphanedProfiles(Set<Id> ownerAccountIds) {
    if (ownerAccountIds == null || ownerAccountIds.isEmpty()) {
      return;
    }

    Set<Id> stillOwning = new Set<Id>();
    for (Financial_Account_Role__c role : [
      SELECT Account__c
      FROM Financial_Account_Role__c
      WHERE Account__c IN :ownerAccountIds AND Role__c IN :OWNER_ROLES
    ]) {
      stillOwning.add(role.Account__c);
    }
    for (Service__c svc : [
      SELECT Primary_Owner__c, Secondary_Owner__c
      FROM Service__c
      WHERE
        Primary_Owner__c IN :ownerAccountIds
        OR Secondary_Owner__c IN :ownerAccountIds
    ]) {
      if (ownerAccountIds.contains(svc.Primary_Owner__c)) {
        stillOwning.add(svc.Primary_Owner__c);
      }
      if (ownerAccountIds.contains(svc.Secondary_Owner__c)) {
        stillOwning.add(svc.Secondary_Owner__c);
      }
    }

    Set<Id> orphaned = new Set<Id>(ownerAccountIds);
    orphaned.removeAll(stillOwning);
    if (orphaned.isEmpty()) {
      return;
    }

    List<Required_Documents__c> docs = [
      SELECT Id
      FROM Required_Documents__c
      WHERE
        (Person__c IN :orphaned
        OR Business__c IN :orphaned
        OR Trust__c IN :orphaned)
        AND DocuSign_Envelope__c = NULL
    ];
    if (docs.isEmpty()) {
      return;
    }
    Set<Id> docIds = new Map<Id, Required_Documents__c>(docs).keySet();

    List<Signee__c> signees = [
      SELECT Id
      FROM Signee__c
      WHERE Required_Document__c IN :docIds
    ];
    List<Envelope_Content__c> links = [
      SELECT Id
      FROM Envelope_Content__c
      WHERE Required_Document__c IN :docIds
    ];
    if (!signees.isEmpty()) {
      delete signees;
    }
    if (!links.isEmpty()) {
      delete links;
    }
    delete docs;
  }

  // Links each profile document to the envelope unless it is already linked. Mirrors the outline's
  // other links: the Household Outline lists a profile from the envelope's contents, so the link is
  // what puts it there.
  private static void linkDocsToEnvelope(List<Id> docIds, Id envelopeId) {
    if (envelopeId == null || docIds == null || docIds.isEmpty()) {
      return;
    }
    Set<Id> alreadyLinked = new Set<Id>();
    for (Envelope_Content__c ec : [
      SELECT Required_Document__c
      FROM Envelope_Content__c
      WHERE Envelope__c = :envelopeId AND Required_Document__c IN :docIds
    ]) {
      alreadyLinked.add(ec.Required_Document__c);
    }
    List<Envelope_Content__c> newLinks = new List<Envelope_Content__c>();
    for (Id docId : docIds) {
      if (!alreadyLinked.contains(docId)) {
        newLinks.add(
          new Envelope_Content__c(
            Envelope__c = envelopeId,
            Required_Document__c = docId
          )
        );
      }
    }
    if (!newLinks.isEmpty()) {
      insert newLinks;
    }
  }

  // Gives every person owner a signee on its own profile, unless it already has one. Only person
  // profiles are self-signed (ownerSigns) — a Business or Trust profile's signees are its related
  // parties, added elsewhere, not the entity itself.
  private static void ensureSelfSignees(
    Map<Id, Account> eligibleById,
    Map<Id, Id> docIdByOwner
  ) {
    Map<Id, Id> docByPerson = new Map<Id, Id>();
    for (Id ownerId : docIdByOwner.keySet()) {
      Account owner = eligibleById.get(ownerId);
      if (owner == null) {
        continue;
      }
      ProfileShape shape = SHAPE_BY_RECORD_TYPE.get(
        owner.RecordType.DeveloperName
      );
      if (shape != null && shape.ownerSigns) {
        docByPerson.put(ownerId, docIdByOwner.get(ownerId));
      }
    }
    if (docByPerson.isEmpty()) {
      return;
    }

    Set<Id> docIds = new Set<Id>(docByPerson.values());
    Set<String> alreadySigning = new Set<String>();
    for (Signee__c signee : [
      SELECT Account__c, Required_Document__c
      FROM Signee__c
      WHERE Required_Document__c IN :docIds
    ]) {
      alreadySigning.add(
        String.valueOf(signee.Account__c) +
        '|' +
        String.valueOf(signee.Required_Document__c)
      );
    }

    List<Signee__c> toInsert = new List<Signee__c>();
    for (Id personId : docByPerson.keySet()) {
      Id docId = docByPerson.get(personId);
      if (
        !alreadySigning.contains(
          String.valueOf(personId) + '|' + String.valueOf(docId)
        )
      ) {
        toInsert.add(
          new Signee__c(Required_Document__c = docId, Account__c = personId)
        );
      }
    }
    if (!toInsert.isEmpty()) {
      insert toInsert;
    }
  }
}