/**
 * Relationships (Trusted Contact / Trustee / Grantor / Executor / Control
 * Person / Beneficial Owner / Authorized Person) for an Account, grouped by
 * role and shown regardless of which household context they were entered
 * under.
 *
 * Reads Account_Account_Relationship__c directly by Account__c = the viewed
 * account -- the same shape EnvelopeHouseholdMemberController.getRelatedParties
 * and FscRelAccountRelationVisibilityService.selectVisibleByAccountAndRecordType
 * already use for this object, neither of which is household-scoped either;
 * this mirrors that, it does not loosen anything.
 *
 * Two independent features write this object with two different role
 * fields: the Envelope wizard's Related Parties step writes Roles__c (a
 * multiselect picklist, e.g. "Trustee;Grantor"), and the separate
 * Relationship Map feature (fscRelMap, internal Lightning record pages only
 * today) writes Reciprocal_Role__c, a lookup to a free-text catalog object
 * whose values do not always match the Roles__c picklist spelling (e.g.
 * "Authorized Individual" vs. "Authorized Person"). Both are read and
 * matched case-insensitively against a small synonym table below, since
 * either can be the only place a given relationship was actually entered --
 * the Envelope wizard in particular has no Estate/Executor option at all
 * today, so Executor rows only ever come from the Relationship Map side.
 */
public with sharing class ArcAccountRelationshipsController {
  private static final String FIDUCIARY_RECORD_TYPE = 'Fiduciary_Legal';

  /** Bucket label -> the Roles__c / Reciprocal_Role__r.Role__c strings that count as that bucket, matched case-insensitively. */
  private static final Map<String, Set<String>> BUCKET_SYNONYMS = new Map<String, Set<String>>{
    'Trusted Contact' => new Set<String>{ 'trusted contact' },
    'Trustee' => new Set<String>{ 'trustee' },
    'Grantor' => new Set<String>{ 'grantor' },
    'Executor' => new Set<String>{ 'executor / personal representative', 'executor', 'personal representative' },
    'Control Person' => new Set<String>{ 'control person' },
    'Beneficial Owner' => new Set<String>{ 'beneficial owner' },
    'Authorized Person' => new Set<String>{ 'authorized person', 'authorized individual' }
  };

  /**
   * Which buckets render for which account category, in display order.
   * Deliberately fixed per the requested categorization (not purely
   * data-driven) so the section reads consistently by account type --
   * e.g. a Trust always shows a Trustee row and a Grantor row, even when
   * one of them has nobody on file yet.
   */
  private static final Map<String, List<String>> BUCKETS_BY_CATEGORY = new Map<String, List<String>>{
    'Individual' => new List<String>{ 'Trusted Contact' },
    'Trust' => new List<String>{ 'Trustee', 'Grantor' },
    'Estate' => new List<String>{ 'Executor' },
    'Business' => new List<String>{ 'Control Person', 'Beneficial Owner', 'Authorized Person' }
  };

  /**
   * Every Account record type this org has that represents an individual,
   * matching arcHouseholdDetail's own alias list exactly -- this org's FSC
   * record types carry no FinServ__ namespace prefix (confirmed live:
   * DeveloperName is bare "IndustriesIndividual"/"IndustriesBusiness", not
   * "FinServ__IndustriesIndividual"/"FinServ__IndustriesBusiness", even
   * though some locally-tracked recordType-meta.xml files describe a
   * different org that does have that namespace).
   */
  private static final Set<String> INDIVIDUAL_RECORD_TYPES = new Set<String>{
    'Individual', 'IndustriesIndividual', 'PersonAccount', 'Diversify_Related_Person', 'Prospect'
  };
  private static final Set<String> BUSINESS_RECORD_TYPES = new Set<String>{
    'Business', 'IndustriesBusiness'
  };

  @AuraEnabled(cacheable=true)
  public static RelationshipsResult getRelationships(Id accountId) {
    RelationshipsResult result = new RelationshipsResult();
    result.category = '';
    result.groups = new List<RelationshipGroup>();

    if (accountId == null) {
      return result;
    }

    List<Account> accounts;
    try {
      accounts = [
        SELECT Id, RecordType.DeveloperName, Trust_Type__c
        FROM Account
        WHERE Id = :accountId
        WITH USER_MODE
        LIMIT 1
      ];
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'ArcAccountRelationshipsController: failed to read Account ' + accountId + ': ' + e
      );
      return result;
    }

    if (accounts.isEmpty()) {
      return result;
    }

    String category = resolveCategory(accounts[0]);
    result.category = category;

    if (String.isBlank(category) || !BUCKETS_BY_CATEGORY.containsKey(category)) {
      return result;
    }

    List<String> bucketOrder = BUCKETS_BY_CATEGORY.get(category);
    Map<String, List<RelationshipRow>> rowsByBucket = new Map<String, List<RelationshipRow>>();
    for (String bucket : bucketOrder) {
      rowsByBucket.put(bucket, new List<RelationshipRow>());
    }

    List<Account_Account_Relationship__c> relations;
    try {
      relations = [
        SELECT Related_Account__c, Related_Account__r.Name, Reciprocal_Role__r.Role__c
        FROM Account_Account_Relationship__c
        WHERE
          Account__c = :accountId
          AND RecordType.DeveloperName = :FIDUCIARY_RECORD_TYPE
          AND Active__c = TRUE
          AND Related_Account__c != NULL
        WITH USER_MODE
        ORDER BY Related_Account__r.Name
        LIMIT 500
      ];
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'ArcAccountRelationshipsController: failed to read Account_Account_Relationship__c for ' +
          accountId +
          ': ' +
          e
      );
      relations = new List<Account_Account_Relationship__c>();
    }

    for (Account_Account_Relationship__c relation : relations) {
      Set<String> matchedBuckets = resolveBuckets(relation, bucketOrder);
      RelationshipRow row = new RelationshipRow();
      row.relatedAccountId = relation.Related_Account__c;
      row.relatedAccountName = relation.Related_Account__r.Name;

      for (String bucket : matchedBuckets) {
        rowsByBucket.get(bucket).add(row);
      }
    }

    for (String bucket : bucketOrder) {
      RelationshipGroup relationshipGroup = new RelationshipGroup();
      relationshipGroup.label = bucket;
      relationshipGroup.rows = rowsByBucket.get(bucket);
      result.groups.add(relationshipGroup);
    }

    return result;
  }

  private static String resolveCategory(Account acct) {
    String recordType = acct.RecordType != null ? acct.RecordType.DeveloperName : null;
    if (String.isBlank(recordType)) {
      return '';
    }

    if (recordType == 'Trust') {
      return acct.Trust_Type__c == 'Estate' ? 'Estate' : 'Trust';
    }
    if (INDIVIDUAL_RECORD_TYPES.contains(recordType)) {
      return 'Individual';
    }
    if (BUSINESS_RECORD_TYPES.contains(recordType)) {
      return 'Business';
    }
    return '';
  }

  /**
   * A single relationship row can land in more than one bucket -- Roles__c
   * is multiselect, and someone can genuinely be both Trustee and Grantor
   * on the same Trust.
   */
  private static Set<String> resolveBuckets(
    Account_Account_Relationship__c relation,
    List<String> bucketOrder
  ) {
    Set<String> found = new Set<String>();
    Set<String> tokens = new Set<String>();

    if (String.isNotBlank(relation.Reciprocal_Role__r.Role__c)) {
      for (String token : relation.Reciprocal_Role__r.Role__c.split(';')) {
        if (String.isNotBlank(token)) {
          tokens.add(token.trim().toLowerCase());
        }
      }
    }
    if (relation.Reciprocal_Role__r != null && String.isNotBlank(relation.Reciprocal_Role__r.Role__c)) {
      tokens.add(relation.Reciprocal_Role__r.Role__c.trim().toLowerCase());
    }

    for (String bucket : bucketOrder) {
      Set<String> synonyms = BUCKET_SYNONYMS.get(bucket);
      for (String token : tokens) {
        if (synonyms.contains(token)) {
          found.add(bucket);
          break;
        }
      }
    }

    return found;
  }

  public class RelationshipsResult {
    /** '' when the account's record type isn't one this tab supports (e.g. Household, Retirement Plan). */
    @AuraEnabled
    public String category;

    @AuraEnabled
    public List<RelationshipGroup> groups;
  }

  public class RelationshipGroup {
    @AuraEnabled
    public String label;

    @AuraEnabled
    public List<RelationshipRow> rows;
  }

  public class RelationshipRow {
    @AuraEnabled
    public Id relatedAccountId;

    @AuraEnabled
    public String relatedAccountName;
  }
}