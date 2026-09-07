public with sharing class EnvelopeCourtesyAgreementService {
  // The Financial_Account_Role__c roles whose holders are the owners a Courtesy Account agreement is
  // grouped by and signed by. Matches EnvelopeHouseholdMemberController.SIGNING_ACCOUNT_ROLES.
  private static final Set<String> OWNER_ROLES = new Set<String>{
    'Primary Owner',
    'Joint Owner'
  };

  private static final String COURTESY_PLATFORM = 'Courtesy Account';
  private static final String DOC_NAME = 'Courtesy Account Services Agreement';

  // One agreement covers up to this many Courtesy accounts that share the same owners; a group with
  // more needs a second agreement, and so on.
  private static final Integer ACCOUNTS_PER_DOC = 3;

  // Brings an envelope's Courtesy Account Services Agreements into line with its Courtesy accounts.
  // A Courtesy account is a Financial Account whose Managed_Account_Platform__c is 'Courtesy Account';
  // the agreement is signed by that account's owners. Accounts that share the same owner set share an
  // agreement, up to three per agreement — a fourth account with those owners adds a second agreement.
  // A different owner set gets its own agreement(s).
  //
  // Envelope-scoped and idempotent, so it can be run after any change that affects the picture — an
  // account gaining or losing owners, its platform changing to or from Courtesy Account, or an account
  // being removed — and it converges to the right number of agreements each time. An agreement already
  // handed to DocuSign (DocuSign_Envelope__c set) is never removed.
  public static void reconcile(Id envelopeId) {
    if (envelopeId == null) {
      return;
    }

    // The Courtesy accounts on this envelope, each with its sorted owner-id list (empty owners means
    // the account is not ready for an agreement yet and is skipped).
    Map<Id, List<Id>> ownersByAccount = courtesyOwnerSets(envelopeId);

    // Group the accounts by owner set. The key is the sorted owner ids joined — two accounts with the
    // same owners land in the same group whichever role each owner plays.
    Map<String, List<Id>> ownerIdsByKey = new Map<String, List<Id>>();
    Map<String, Integer> accountCountByKey = new Map<String, Integer>();
    for (Id accountId : ownersByAccount.keySet()) {
      List<Id> owners = ownersByAccount.get(accountId);
      if (owners.isEmpty()) {
        continue;
      }
      String key = String.join(owners, ',');
      ownerIdsByKey.put(key, owners);
      accountCountByKey.put(
        key,
        (accountCountByKey.containsKey(key) ? accountCountByKey.get(key) : 0) + 1
      );
    }

    // How many agreements each owner set needs: one per three accounts, rounded up.
    Map<String, Integer> desiredByKey = new Map<String, Integer>();
    for (String key : accountCountByKey.keySet()) {
      Integer count = accountCountByKey.get(key);
      desiredByKey.put(key, (count + ACCOUNTS_PER_DOC - 1) / ACCOUNTS_PER_DOC);
    }

    // The agreements the envelope already has, grouped by the owner set that signs each (its signee
    // set), plus which are already sent and so must not be removed.
    List<Required_Documents__c> existingDocs = courtesyDocsInEnvelope(envelopeId);
    Map<Id, String> keyByDoc = signeeKeyByDoc(existingDocs);
    Map<Id, Boolean> sentByDoc = new Map<Id, Boolean>();
    Map<String, List<Id>> existingDocsByKey = new Map<String, List<Id>>();
    for (Required_Documents__c doc : existingDocs) {
      sentByDoc.put(doc.Id, doc.DocuSign_Envelope__c != null);
      String key = keyByDoc.get(doc.Id);
      if (!existingDocsByKey.containsKey(key)) {
        existingDocsByKey.put(key, new List<Id>());
      }
      existingDocsByKey.get(key).add(doc.Id);
    }

    // Reconcile the count per owner set: create the shortfall, delete the surplus (leaving sent
    // agreements in place). An owner set that no longer has any Courtesy account has a desired count
    // of zero and its agreements are removed.
    List<Required_Documents__c> docsToInsert = new List<Required_Documents__c>();
    List<List<Id>> signeesForInsert = new List<List<Id>>();
    Set<Id> docIdsToDelete = new Set<Id>();

    Set<String> allKeys = new Set<String>();
    allKeys.addAll(desiredByKey.keySet());
    allKeys.addAll(existingDocsByKey.keySet());
    for (String key : allKeys) {
      Integer desired = desiredByKey.containsKey(key) ? desiredByKey.get(key) : 0;
      List<Id> existing = existingDocsByKey.containsKey(key)
        ? existingDocsByKey.get(key)
        : new List<Id>();

      if (existing.size() < desired) {
        List<Id> owners = ownerIdsByKey.get(key);
        for (Integer i = 0; i < desired - existing.size(); i++) {
          docsToInsert.add(new Required_Documents__c(Name = DOC_NAME));
          signeesForInsert.add(owners);
        }
      } else if (existing.size() > desired) {
        Integer toRemove = existing.size() - desired;
        for (Id docId : existing) {
          if (toRemove == 0) {
            break;
          }
          // A sent agreement is left in place; it still counts, so it is not replaced either.
          if (sentByDoc.get(docId) == true) {
            continue;
          }
          docIdsToDelete.add(docId);
          toRemove--;
        }
      }
    }

    createAgreements(docsToInsert, signeesForInsert, envelopeId);
    deleteAgreements(docIdsToDelete);
  }

  // The Courtesy accounts on the envelope, each mapped to its sorted list of owner ids. A non-Courtesy
  // account, or one with no owners, does not appear.
  private static Map<Id, List<Id>> courtesyOwnerSets(Id envelopeId) {
    Set<Id> accountIds = new Set<Id>();
    for (Envelope_Content__c ec : [
      SELECT Wizard_Financial_Account__c
      FROM Envelope_Content__c
      WHERE Envelope__c = :envelopeId AND Wizard_Financial_Account__c != NULL
    ]) {
      accountIds.add(ec.Wizard_Financial_Account__c);
    }
    Map<Id, List<Id>> ownersByAccount = new Map<Id, List<Id>>();
    if (accountIds.isEmpty()) {
      return ownersByAccount;
    }

    Set<Id> courtesyIds = new Set<Id>();
    for (Financial_Account__c fa : [
      SELECT Id
      FROM Financial_Account__c
      WHERE Id IN :accountIds AND Managed_Account_Platform__c = :COURTESY_PLATFORM
    ]) {
      courtesyIds.add(fa.Id);
    }
    if (courtesyIds.isEmpty()) {
      return ownersByAccount;
    }

    Map<Id, Set<Id>> ownerSetByAccount = new Map<Id, Set<Id>>();
    for (Financial_Account_Role__c role : [
      SELECT Financial_Account__c, Account__c
      FROM Financial_Account_Role__c
      WHERE
        Financial_Account__c IN :courtesyIds
        AND Role__c IN :OWNER_ROLES
        AND Account__c != NULL
    ]) {
      if (!ownerSetByAccount.containsKey(role.Financial_Account__c)) {
        ownerSetByAccount.put(role.Financial_Account__c, new Set<Id>());
      }
      ownerSetByAccount.get(role.Financial_Account__c).add(role.Account__c);
    }

    for (Id accountId : courtesyIds) {
      List<Id> owners = ownerSetByAccount.containsKey(accountId)
        ? new List<Id>(ownerSetByAccount.get(accountId))
        : new List<Id>();
      owners.sort();
      ownersByAccount.put(accountId, owners);
    }
    return ownersByAccount;
  }

  // The envelope's Courtesy Account Services Agreements, found by name among the required documents
  // linked to the envelope.
  private static List<Required_Documents__c> courtesyDocsInEnvelope(
    Id envelopeId
  ) {
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
    return [
      SELECT Id, DocuSign_Envelope__c
      FROM Required_Documents__c
      WHERE Id IN :docIds AND Name = :DOC_NAME
    ];
  }

  // Each agreement mapped to the owner-set key its signees form — the same sorted-joined-ids key the
  // Courtesy accounts are grouped by, so an agreement lines up with the group it belongs to.
  private static Map<Id, String> signeeKeyByDoc(
    List<Required_Documents__c> docs
  ) {
    Map<Id, String> keyByDoc = new Map<Id, String>();
    if (docs.isEmpty()) {
      return keyByDoc;
    }
    Set<Id> docIds = new Map<Id, Required_Documents__c>(docs).keySet();
    Map<Id, Set<Id>> signeesByDoc = new Map<Id, Set<Id>>();
    for (Signee__c signee : [
      SELECT Required_Document__c, Account__c
      FROM Signee__c
      WHERE Required_Document__c IN :docIds AND Account__c != NULL
    ]) {
      if (!signeesByDoc.containsKey(signee.Required_Document__c)) {
        signeesByDoc.put(signee.Required_Document__c, new Set<Id>());
      }
      signeesByDoc.get(signee.Required_Document__c).add(signee.Account__c);
    }
    for (Required_Documents__c doc : docs) {
      List<Id> owners = signeesByDoc.containsKey(doc.Id)
        ? new List<Id>(signeesByDoc.get(doc.Id))
        : new List<Id>();
      owners.sort();
      keyByDoc.put(doc.Id, String.join(owners, ','));
    }
    return keyByDoc;
  }

  // Inserts the new agreements, then their signees and envelope links. signeesForInsert is parallel to
  // docs: each entry is the owner ids that sign the agreement at the same position.
  private static void createAgreements(
    List<Required_Documents__c> docs,
    List<List<Id>> signeesForInsert,
    Id envelopeId
  ) {
    if (docs.isEmpty()) {
      return;
    }
    insert docs;

    List<Signee__c> signees = new List<Signee__c>();
    List<Envelope_Content__c> links = new List<Envelope_Content__c>();
    for (Integer i = 0; i < docs.size(); i++) {
      for (Id ownerId : signeesForInsert[i]) {
        signees.add(
          new Signee__c(Required_Document__c = docs[i].Id, Account__c = ownerId)
        );
      }
      links.add(
        new Envelope_Content__c(
          Envelope__c = envelopeId,
          Required_Document__c = docs[i].Id
        )
      );
    }
    if (!signees.isEmpty()) {
      insert signees;
    }
    if (!links.isEmpty()) {
      insert links;
    }
  }

  // Deletes the surplus agreements along with their signees and envelope links.
  private static void deleteAgreements(Set<Id> docIds) {
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
}