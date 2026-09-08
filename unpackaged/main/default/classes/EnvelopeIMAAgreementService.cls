public with sharing class EnvelopeIMAAgreementService {
  // The Financial_Account_Role__c roles whose holders are the owners an IMA applies to. Matches
  // EnvelopeHouseholdMemberController.SIGNING_ACCOUNT_ROLES.
  private static final Set<String> OWNER_ROLES = new Set<String>{
    'Primary Owner',
    'Joint Owner'
  };

  // Only an RIA account carries an Investment Management Agreement.
  private static final String RIA = 'RIA';

  // Individual (person) owners share a plain "Investment Management Agreement", up to two signers per
  // form; entity owners' forms carry the entity name in front of this suffix.
  private static final String INDIVIDUAL_DOC_NAME = 'Investment Management Agreement';
  private static final String SUFFIX = ' - Investment Management Agreement';
  private static final Integer SIGNERS_PER_INDIVIDUAL_FORM = 2;

  // The fiduciary role that signs an entity owner's IMA: a business or retirement plan is signed by
  // its Authorized Persons, a trust by its Trustees. Keyed by the owner Account's record-type
  // DeveloperName.
  private static final Map<String, String> FIDUCIARY_ROLE_BY_RECORD_TYPE = new Map<String, String>{
    'Business' => 'Authorized Person',
    'Trust' => 'Trustee',
    'Retirement_Plan' => 'Authorized Person'
  };

  // Brings an envelope's Investment Management Agreements into line with its RIA accounts and their
  // owners. Only an owner (primary or joint) of a BD_or_RIA__c = 'RIA' account whose own
  // IMA_Signed_Date__c is null needs an IMA. Individual owners are pooled across the envelope and
  // grouped up to two per form (each a plain "Investment Management Agreement"); an entity owner
  // (business / trust / retirement plan) is not pooled — each of its Authorized Persons or Trustees
  // gets its own "<Entity> - Investment Management Agreement" with that person as the sole signee.
  //
  // Envelope-scoped, idempotent and reconciling: run it after any change to owners, an account's
  // BD/RIA flag, an entity's related parties, or an account removal. A form already handed to
  // DocuSign (DocuSign_Envelope__c set) is never removed, and its signers are not re-formed elsewhere.
  public static void reconcile(Id envelopeId) {
    if (envelopeId == null) {
      return;
    }

    Map<Id, Account> owners = riaOwnersNeedingIma(envelopeId);
    List<Id> individualOwnerIds = new List<Id>();
    Map<Id, Account> entityOwners = new Map<Id, Account>();
    for (Account owner : owners.values()) {
      if (owner.RecordType.DeveloperName == 'PersonAccount') {
        individualOwnerIds.add(owner.Id);
      } else if (
        FIDUCIARY_ROLE_BY_RECORD_TYPE.containsKey(owner.RecordType.DeveloperName)
      ) {
        entityOwners.put(owner.Id, owner);
      }
    }

    // The envelope's existing IMA forms, split into the individual pool (exact name) and the entity
    // forms (entity name in front of the suffix), each with its signees and sent flag.
    List<Required_Documents__c> existing = imaDocsInEnvelope(envelopeId);
    Map<Id, Set<Id>> signeesByDoc = signeesByDoc(existing);

    reconcileIndividualForms(
      envelopeId,
      individualOwnerIds,
      existing,
      signeesByDoc
    );
    reconcileEntityForms(envelopeId, entityOwners, existing, signeesByDoc);
  }

  // ------------------------------------------------------------------------
  // Individuals — pooled, two per form
  // ------------------------------------------------------------------------

  private static void reconcileIndividualForms(
    Id envelopeId,
    List<Id> individualOwnerIds,
    List<Required_Documents__c> existing,
    Map<Id, Set<Id>> signeesByDoc
  ) {
    // Signers already carried by a sent form stay there and are not re-formed; every other existing
    // individual form is rebuilt from the current pool.
    Set<Id> sentSigners = new Set<Id>();
    List<Required_Documents__c> reusableForms = new List<Required_Documents__c>();
    for (Required_Documents__c doc : existing) {
      if (doc.Name != INDIVIDUAL_DOC_NAME) {
        continue;
      }
      if (doc.DocuSign_Envelope__c != null) {
        Set<Id> signers = signeesByDoc.get(doc.Id);
        if (signers != null) {
          sentSigners.addAll(signers);
        }
      } else {
        reusableForms.add(doc);
      }
    }

    List<Id> remaining = new List<Id>();
    for (Id ownerId : new Set<Id>(individualOwnerIds)) {
      if (!sentSigners.contains(ownerId)) {
        remaining.add(ownerId);
      }
    }
    remaining.sort();

    // The pairs the pool should be grouped into, keyed for comparison so an unchanged pool is a no-op.
    List<List<Id>> desiredPairs = new List<List<Id>>();
    List<Id> current = new List<Id>();
    for (Id ownerId : remaining) {
      current.add(ownerId);
      if (current.size() == SIGNERS_PER_INDIVIDUAL_FORM) {
        desiredPairs.add(current);
        current = new List<Id>();
      }
    }
    if (!current.isEmpty()) {
      desiredPairs.add(current);
    }

    List<String> desiredKeys = new List<String>();
    for (List<Id> pair : desiredPairs) {
      desiredKeys.add(signerKey(new Set<Id>(pair)));
    }
    desiredKeys.sort();

    List<String> existingKeys = new List<String>();
    for (Required_Documents__c doc : reusableForms) {
      Set<Id> signers = signeesByDoc.get(doc.Id);
      existingKeys.add(signerKey(signers == null ? new Set<Id>() : signers));
    }
    existingKeys.sort();

    // The reusable forms already match the desired grouping exactly — nothing to do.
    if (String.join(desiredKeys, ';') == String.join(existingKeys, ';')) {
      return;
    }

    // Otherwise rebuild: drop the non-sent forms and re-create the pool's pairs.
    Set<Id> docIdsToDelete = new Set<Id>();
    for (Required_Documents__c doc : reusableForms) {
      docIdsToDelete.add(doc.Id);
    }
    deleteDocs(docIdsToDelete);

    for (List<Id> pair : desiredPairs) {
      createForm(envelopeId, INDIVIDUAL_DOC_NAME, new Set<Id>(pair));
    }
  }

  // ------------------------------------------------------------------------
  // Entities — one form per related party
  // ------------------------------------------------------------------------

  private static void reconcileEntityForms(
    Id envelopeId,
    Map<Id, Account> entityOwners,
    List<Required_Documents__c> existing,
    Map<Id, Set<Id>> signeesByDoc
  ) {
    // Desired (form name, signer) pairs: each entity owner's Authorized Persons / Trustees, each on
    // its own "<Entity> - Investment Management Agreement".
    Map<String, Id> desiredSignerByKey = new Map<String, Id>();
    if (!entityOwners.isEmpty()) {
      Map<Id, Set<Id>> partiesByEntity = fiduciaryPartiesByEntity(entityOwners);
      for (Id entityId : entityOwners.keySet()) {
        String docName = entityOwners.get(entityId).Name + SUFFIX;
        Set<Id> parties = partiesByEntity.get(entityId);
        if (parties == null || parties.isEmpty()) {
          // The entity owns an RIA account but has no Authorized Persons / Trustees yet: still create
          // the agreement, with no signee, so it shows as "To be assigned..." until they are added.
          desiredSignerByKey.put(entityDocKey(docName, null), null);
        } else {
          for (Id personId : parties) {
            desiredSignerByKey.put(entityDocKey(docName, personId), personId);
          }
        }
      }
    }

    // Existing entity forms keyed the same way (name + its single signer), and which are sent.
    Set<String> existingKeys = new Set<String>();
    Set<Id> docIdsToDelete = new Set<Id>();
    for (Required_Documents__c doc : existing) {
      if (doc.Name == INDIVIDUAL_DOC_NAME || !doc.Name.endsWith(SUFFIX)) {
        continue;
      }
      Set<Id> signers = signeesByDoc.get(doc.Id);
      Id signerId = (signers == null || signers.isEmpty())
        ? null
        : new List<Id>(signers)[0];
      String key = entityDocKey(doc.Name, signerId);
      if (desiredSignerByKey.containsKey(key)) {
        existingKeys.add(key);
      } else if (doc.DocuSign_Envelope__c == null) {
        // No longer wanted (party removed, owner signed, account no longer RIA) and not yet sent.
        docIdsToDelete.add(doc.Id);
      } else {
        // Sent: keep it, and treat it as covering its key so it is not duplicated.
        existingKeys.add(key);
      }
    }

    deleteDocs(docIdsToDelete);

    for (String key : desiredSignerByKey.keySet()) {
      if (existingKeys.contains(key)) {
        continue;
      }
      Id signerId = desiredSignerByKey.get(key);
      Set<Id> signers = signerId == null
        ? new Set<Id>()
        : new Set<Id>{ signerId };
      createForm(envelopeId, key.substringBeforeLast('|'), signers);
    }
  }

  // ------------------------------------------------------------------------
  // Queries
  // ------------------------------------------------------------------------

  // The owners (primary + joint) of the envelope's RIA accounts whose own IMA_Signed_Date__c is null,
  // by owner Account, with the record type and name the reconcile needs.
  private static Map<Id, Account> riaOwnersNeedingIma(Id envelopeId) {
    Set<Id> accountIds = new Set<Id>();
    for (Envelope_Content__c ec : [
      SELECT Wizard_Financial_Account__c
      FROM Envelope_Content__c
      WHERE Envelope__c = :envelopeId AND Wizard_Financial_Account__c != NULL
    ]) {
      accountIds.add(ec.Wizard_Financial_Account__c);
    }
    Map<Id, Account> ownersById = new Map<Id, Account>();
    if (accountIds.isEmpty()) {
      return ownersById;
    }

    Set<Id> riaIds = new Set<Id>();
    for (Financial_Account__c fa : [
      SELECT Id
      FROM Financial_Account__c
      WHERE Id IN :accountIds AND BD_or_RIA__c = :RIA
    ]) {
      riaIds.add(fa.Id);
    }
    if (riaIds.isEmpty()) {
      return ownersById;
    }

    Set<Id> ownerIds = new Set<Id>();
    for (Financial_Account_Role__c role : [
      SELECT Account__c
      FROM Financial_Account_Role__c
      WHERE
        Financial_Account__c IN :riaIds
        AND Role__c IN :OWNER_ROLES
        AND Account__c != NULL
    ]) {
      ownerIds.add(role.Account__c);
    }
    if (ownerIds.isEmpty()) {
      return ownersById;
    }

    for (Account owner : [
      SELECT Id, Name, RecordType.DeveloperName
      FROM Account
      WHERE Id IN :ownerIds AND IMA_Signed_Date__c = NULL
    ]) {
      ownersById.put(owner.Id, owner);
    }
    return ownersById;
  }

  // The active fiduciary signers of each entity owner: its Authorized Persons (business, retirement
  // plan) or Trustees (trust).
  private static Map<Id, Set<Id>> fiduciaryPartiesByEntity(
    Map<Id, Account> entityOwners
  ) {
    Map<Id, Set<Id>> partiesByEntity = new Map<Id, Set<Id>>();
    for (Account_Account_Relationship__c relation : [
      SELECT Account__c, Related_Account__c, Roles__c
      FROM Account_Account_Relationship__c
      WHERE
        Account__c IN :entityOwners.keySet()
        AND Related_Account__c != NULL
        AND Active__c = TRUE
    ]) {
      Account entity = entityOwners.get(relation.Account__c);
      if (entity == null) {
        continue;
      }
      String role = FIDUCIARY_ROLE_BY_RECORD_TYPE.get(
        entity.RecordType.DeveloperName
      );
      if (role == null || !rolesContain(relation.Roles__c, role)) {
        continue;
      }
      if (!partiesByEntity.containsKey(relation.Account__c)) {
        partiesByEntity.put(relation.Account__c, new Set<Id>());
      }
      partiesByEntity.get(relation.Account__c).add(relation.Related_Account__c);
    }
    return partiesByEntity;
  }

  // The envelope's IMA forms — the plain individual pool documents and the "<Entity> - ..." entity
  // ones — found by name among the required documents linked to the envelope.
  private static List<Required_Documents__c> imaDocsInEnvelope(Id envelopeId) {
    Set<Id> docIds = new Set<Id>();
    for (Envelope_Content__c ec : [
      SELECT Required_Document__c
      FROM Envelope_Content__c
      WHERE Envelope__c = :envelopeId AND Required_Document__c != NULL
    ]) {
      docIds.add(ec.Required_Document__c);
    }
    if (docIds.isEmpty()) {
      return new List<Required_Documents__c>();
    }
    String likeSuffix = '%' + SUFFIX;
    return [
      SELECT Id, Name, DocuSign_Envelope__c
      FROM Required_Documents__c
      WHERE
        Id IN :docIds
        AND (Name = :INDIVIDUAL_DOC_NAME OR Name LIKE :likeSuffix)
    ];
  }

  private static Map<Id, Set<Id>> signeesByDoc(
    List<Required_Documents__c> docs
  ) {
    Map<Id, Set<Id>> byDoc = new Map<Id, Set<Id>>();
    if (docs.isEmpty()) {
      return byDoc;
    }
    Set<Id> docIds = new Map<Id, Required_Documents__c>(docs).keySet();
    for (Signee__c signee : [
      SELECT Required_Document__c, Account__c
      FROM Signee__c
      WHERE Required_Document__c IN :docIds AND Account__c != NULL
    ]) {
      if (!byDoc.containsKey(signee.Required_Document__c)) {
        byDoc.put(signee.Required_Document__c, new Set<Id>());
      }
      byDoc.get(signee.Required_Document__c).add(signee.Account__c);
    }
    return byDoc;
  }

  // ------------------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------------------

  private static void createForm(Id envelopeId, String name, Set<Id> signerIds) {
    Required_Documents__c doc = new Required_Documents__c(Name = name);
    insert doc;
    List<Signee__c> signees = new List<Signee__c>();
    for (Id signerId : signerIds) {
      signees.add(
        new Signee__c(Required_Document__c = doc.Id, Account__c = signerId)
      );
    }
    if (!signees.isEmpty()) {
      insert signees;
    }
    insert new Envelope_Content__c(
      Envelope__c = envelopeId,
      Required_Document__c = doc.Id
    );
  }

  private static void deleteDocs(Set<Id> docIds) {
    if (docIds.isEmpty()) {
      return;
    }
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
    delete [SELECT Id FROM Required_Documents__c WHERE Id IN :docIds];
  }

  // A stable key for a set of signer ids: sorted and joined, so the same signers always compare equal.
  private static String signerKey(Set<Id> signerIds) {
    List<Id> ids = new List<Id>(signerIds);
    ids.sort();
    return String.join(ids, ',');
  }

  private static String entityDocKey(String docName, Id signerId) {
    return docName + '|' + String.valueOf(signerId);
  }

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
}