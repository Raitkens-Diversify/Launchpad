/**
 * Row scope for every ARC list: a record is listed when the running user
 * owns it, or it belongs to one of the Financial Advisor Teams the user is an
 * ACTIVE member of. One shared rule, so no list can drift from the others.
 *
 *   (OwnerId = :me OR Financial_Advisor_Team__c IN :myTeams)
 *
 * Per-object shape of "belongs to my team":
 * - Account also checks the Person Account mirror, Financial_Advisor_Team__pc.
 *   The plain field is populated on the overwhelming majority of Person
 *   Accounts too (confirmed live), but a handful carry the value only on the
 *   __pc side, so both are read rather than trusting one.
 * - Task uses the same two halves as everything else, per the business
 *   (2026-09-08): a teammate's task counts only when it is stamped with one of
 *   my teams. Task.Financial_Advisor_Team__c is blank on ~16% of open tasks
 *   (3,013 of 18,662, measured that day), and those no longer appear under
 *   "My Team's Open Tasks" unless the viewer owns them. activeTeamUserIds
 *   still backs that tab's own owned-by-a-teammate clause; placeholder owners
 *   (Unassigned, Maestro, DMS, *systems*) are taken out of it because they can
 *   sit on a roster while their tasks are nobody's own work.
 * - Service__c and Check_Deposit__c carry no team of their own and read it
 *   from the parent that does: a Service through its Household / Primary
 *   Owner account, a Check Deposit through its Check Log (a master-detail
 *   child, so it has no OwnerId of its own either).
 * - Financial_Account_Related_Product__c (a client's holding of an Approved
 *   Product; master-detail under Product__c, so no OwnerId) is the owner /
 *   team of its ARC Financial Account, or of the Case it was raised from. Its
 *   own Financial_Advisor_Team__c is a text formula of the FinServ account's
 *   team NAME, and the FinServ relationship is not traversable at all for
 *   Community users ("No such relation" -- see ArcCaseDetailController), so
 *   neither is used.
 * - Product__c is the Approved Products catalog and is deliberately not
 *   scoped. Any other object without both OwnerId and Financial_Advisor_Team__c
 *   is left to sharing rules (clauseFor returns null).
 *
 * Related lists (ArcRelatedListController) apply this only when the parent
 * record's object is not itself scoped -- see isScoped -- so a Product's
 * Related Products are filtered, while a Case's or Financial Account's
 * children, already behind a scoped parent, are not.
 *
 * Active membership (Active__c = true) is the rule here, as it always was for
 * the Contacts tabs. FinancialAdvisorTeamAccessService -- the Work table's
 * scope toggle, envelopes and the Home metrics -- deliberately keeps its own
 * broader membership rule; this class does not replace it.
 *
 * Every query that consumes this runs WITH USER_MODE / AccessLevel.USER_MODE.
 * This org's API version rejects combining that with the older WITH
 * SECURITY_ENFORCED, and USER_MODE is the stricter of the two: field- and
 * object-level security plus sharing.
 */
public with sharing class ArcListScope {
  /** Bind names clauseFor writes into the caller's bind map. */
  public static final String USER_BIND = 'scopeUserId';
  public static final String TEAM_BIND = 'scopeTeamIds';
  public static final String TEAM_USER_BIND = 'scopeTeamUserIds';

  private static final Set<String> UNSCOPED_OBJECTS = new Set<String>{ 'Product__c' };

  /** Placeholder owners whose tasks are never a person's own work. */
  private static final Set<String> SYSTEM_TASK_OWNER_NAMES = new Set<String>{
    'Unassigned',
    'Maestro',
    'DMS'
  };

  /** Never matches a real record; an empty IN () is invalid SOQL/SOSL. */
  private static final String NO_MATCH_ID = '000000000000000AAA';

  private static final String OWNER_OR_TEAM =
    '(OwnerId = :scopeUserId OR Financial_Advisor_Team__c IN :scopeTeamIds)';

  private static final Map<String, String> CLAUSE_BY_OBJECT = new Map<String, String>{
    'Account' => '(OwnerId = :scopeUserId' +
      ' OR Financial_Advisor_Team__c IN :scopeTeamIds' +
      ' OR Financial_Advisor_Team__pc IN :scopeTeamIds)',
    'Service__c' => '(OwnerId = :scopeUserId' +
      ' OR Household__r.Financial_Advisor_Team__c IN :scopeTeamIds' +
      ' OR Primary_Owner__r.Financial_Advisor_Team__c IN :scopeTeamIds' +
      ' OR Primary_Owner__r.Financial_Advisor_Team__pc IN :scopeTeamIds)',
    'Check_Deposit__c' => '(Check__r.OwnerId = :scopeUserId' +
      ' OR Check__r.Financial_Advisor_Team__c IN :scopeTeamIds)',
    'Financial_Account_Related_Product__c' => '(Wizard_Financial_Account__r.OwnerId = :scopeUserId' +
      ' OR Wizard_Financial_Account__r.Financial_Advisor_Team__c IN :scopeTeamIds' +
      ' OR Case__r.OwnerId = :scopeUserId' +
      ' OR Case__r.Financial_Advisor_Team__c IN :scopeTeamIds)'
  };

  /** The Financial Advisor Teams the running user is an active member of. */
  public static Set<Id> activeTeamIds() {
    Set<Id> teamIds = new Set<Id>();
    for (Financial_Advisor_Team_Member__c membership : [
      SELECT Financial_Advisor_Team__c
      FROM Financial_Advisor_Team_Member__c
      WHERE User__c = :UserInfo.getUserId() AND Active__c = true
      WITH USER_MODE
    ]) {
      if (membership.Financial_Advisor_Team__c != null) {
        teamIds.add(membership.Financial_Advisor_Team__c);
      }
    }
    return teamIds;
  }

  /**
   * Every active member of those teams, minus the placeholder owners --
   * resolved in two hops (my memberships -> their teams -> every active
   * membership on them), since the junction object has no self-join that
   * answers it in one. An empty result is valid: IN :emptySet matches
   * nothing, which is right for someone on no team.
   */
  public static Set<Id> activeTeamUserIds() {
    Set<Id> teamIds = activeTeamIds();
    Set<Id> userIds = new Set<Id>();
    if (teamIds.isEmpty()) {
      return userIds;
    }

    for (Financial_Advisor_Team_Member__c teammate : [
      SELECT User__c
      FROM Financial_Advisor_Team_Member__c
      WHERE Financial_Advisor_Team__c IN :teamIds AND Active__c = true
      WITH USER_MODE
    ]) {
      if (teammate.User__c != null) {
        userIds.add(teammate.User__c);
      }
    }

    // Removed by id rather than by an Owner.Name clause: a name clause
    // silently drops any row whose Owner.Name does not resolve.
    for (User systemUser : [
      SELECT Id
      FROM User
      WHERE Name IN :SYSTEM_TASK_OWNER_NAMES OR Name LIKE '%systems%'
      WITH USER_MODE
    ]) {
      userIds.remove(systemUser.Id);
    }
    return userIds;
  }

  /**
   * The scope clause for one object, ready to AND into a dynamic SOQL WHERE,
   * with its bind values written into binds (see the *_BIND constants). Null
   * for an object this rule does not apply to -- the caller adds nothing.
   */
  public static String clauseFor(String objectApiName, Map<String, Object> binds) {
    String clause = clauseTemplate(objectApiName);
    if (clause == null) {
      return null;
    }
    binds.put(USER_BIND, UserInfo.getUserId());
    binds.put(TEAM_BIND, activeTeamIds());
    if (clause.contains(':' + TEAM_USER_BIND)) {
      binds.put(TEAM_USER_BIND, activeTeamUserIds());
    }
    return clause;
  }

  /**
   * The same clause with every value inlined as a quoted Id literal, for
   * dynamic SOSL -- Search.query(String) has no bind-variable support. An Id
   * is never attacker-controlled text, so inlining it carries none of the
   * injection risk that inlining raw user input would. Null when clauseFor
   * would be.
   */
  public static String literalClauseFor(String objectApiName) {
    String clause = clauseTemplate(objectApiName);
    if (clause == null) {
      return null;
    }
    if (clause.contains(':' + TEAM_USER_BIND)) {
      clause = clause.replace(':' + TEAM_USER_BIND, idInClause(activeTeamUserIds()));
    }
    return clause
      .replace(':' + TEAM_BIND, idInClause(activeTeamIds()))
      .replace(':' + USER_BIND, '\'' + UserInfo.getUserId() + '\'');
  }

  /** Whether this rule applies to an object at all (clauseFor would be non-null). */
  public static Boolean isScoped(String objectApiName) {
    return clauseTemplate(objectApiName) != null;
  }

  private static String clauseTemplate(String objectApiName) {
    if (String.isBlank(objectApiName) || UNSCOPED_OBJECTS.contains(objectApiName)) {
      return null;
    }
    if (CLAUSE_BY_OBJECT.containsKey(objectApiName)) {
      return CLAUSE_BY_OBJECT.get(objectApiName);
    }

    Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
    if (objectType == null) {
      return null;
    }
    Map<String, Schema.SObjectField> fields = objectType.getDescribe().fields.getMap();
    Schema.SObjectField teamField = fields.get('Financial_Advisor_Team__c');
    // The team half must be a real lookup: on some objects the field of that
    // name is a text formula (a team NAME), which an IN over ids would never
    // match -- a silently dead clause, not a scope.
    if (
      !fields.containsKey('OwnerId') ||
      teamField == null ||
      teamField.getDescribe().getType() != Schema.DisplayType.REFERENCE
    ) {
      return null;
    }
    return OWNER_OR_TEAM;
  }

  private static String idInClause(Set<Id> ids) {
    List<String> quoted = new List<String>();
    for (Id recordId : ids) {
      quoted.add('\'' + recordId + '\'');
    }
    if (quoted.isEmpty()) {
      quoted.add('\'' + NO_MATCH_ID + '\'');
    }
    return '(' + String.join(quoted, ', ') + ')';
  }
}