/**
 * ArcTeamSettingsController
 *
 * Read API for the Team tab of the Arc settings surface. Answers three
 * questions about a Financial Advisor Team: who is on it, which permission each
 * member holds, and which rep codes the team owns.
 *
 * Conventions:
 *  - `with sharing` + explicit isAccessible() guards, so a user never sees a
 *    team, member or rep code they could not read directly (CRUD/FLS respected
 *    on top of record sharing).
 *  - Team and role are different things and are kept apart deliberately. The
 *    team is the Financial_Advisor_Team__c the member belongs to; the role is
 *    Financial_Advisor_Team_Member__c.Role__c, the member's job on that team. A
 *    member can sit on several teams and hold a different role on each, so a
 *    role is only ever reported alongside the team it was read from.
 *  - Permissions are read from the member checkboxes, not from the same-named
 *    Text fields on the team. Those team fields exist on the page layout but are
 *    empty in this org, and "who is tied to each permission" is answerable from
 *    the members either way — so the members are the single source of truth and
 *    the team-level view is derived from them.
 *  - Rep codes hang off the team, not off a person. Financial_Advisor_Team__c is
 *    a master-detail parent of Rep_Code__c, and no rep code field points at a
 *    user, so they are returned in the team section rather than per member.
 *  - Bulk-safe: no SOQL inside loops. One query per object, then assembled in
 *    memory.
 */
public with sharing class ArcTeamSettingsController {
  /** A team of this size is already past what the tab can usefully show. */
  private static final Integer MAX_MEMBERS = 500;
  /** Rep codes per team; the largest team in this org holds a handful. */
  private static final Integer MAX_REP_CODES = 200;
  /** One person on many teams is normal; hundreds is not. */
  private static final Integer MAX_TEAMS = 50;

  /**
   * The eight member permission checkboxes, in the order the Permissions
   * section of the internal Financial Advisor Team layout lists them, with
   * the two that layout omits appended. Field API name → display label.
   *
   * Ordered rather than a plain map so the tab renders the same sequence
   * every time; a Map's iteration order is not guaranteed across releases.
   */
  private static final List<String> PERMISSION_FIELDS = new List<String>{
    'CSA__c',
    'Draft_Paperwork__c',
    'Trading__c',
    'Associate_Advisor__c',
    'Review_Paperwork__c',
    'Send_Notifications__c',
    'Operations__c',
    'Project_Manager__c'
  };

  private static final Map<String, String> PERMISSION_LABELS = new Map<String, String>{
    'CSA__c' => 'CSA',
    'Draft_Paperwork__c' => 'Draft Paperwork',
    'Trading__c' => 'Trading',
    'Associate_Advisor__c' => 'Associate Advisor',
    'Review_Paperwork__c' => 'Review Paperwork',
    'Send_Notifications__c' => 'Send Notifications',
    'Operations__c' => 'Operations',
    'Project_Manager__c' => 'Project Manager'
  };

  // ---- Entry points -------------------------------------------------------

  /**
   * Every team the running user is an active member of, fully populated.
   *
   * Returned as a list because a user genuinely can sit on more than one
   * team, and their role differs per team — collapsing to "the" team would
   * have to pick one arbitrarily and would report the wrong role.
   */
  @AuraEnabled(cacheable=true)
  public static List<TeamDetail> getMyTeams() {
    assertAccessible();

    Set<Id> teamIds = new Set<Id>();
    for (Financial_Advisor_Team_Member__c row : [
      SELECT Financial_Advisor_Team__c
      FROM Financial_Advisor_Team_Member__c
      WHERE
        User__c = :UserInfo.getUserId()
        AND Active__c = TRUE
        AND Financial_Advisor_Team__c != NULL
      LIMIT :MAX_TEAMS
    ]) {
      teamIds.add(row.Financial_Advisor_Team__c);
    }

    if (teamIds.isEmpty()) {
      return new List<TeamDetail>();
    }

    return buildTeams(teamIds);
  }

  /**
   * One named team. Used where the surface already knows which team it is
   * about — a case's Financial Advisor Team, for instance — rather than
   * inferring it from the running user.
   */
  @AuraEnabled(cacheable=true)
  public static TeamDetail getTeam(Id teamId) {
    assertAccessible();

    if (teamId == null) {
      return null;
    }

    List<TeamDetail> teams = buildTeams(new Set<Id>{ teamId });
    return teams.isEmpty() ? null : teams[0];
  }

  /**
   * What the running user themselves holds, across every team they are on.
   *
   * Deliberately separate from getMyTeams: a member looking up their own
   * roles should not have to be handed the whole roster to find themselves
   * in it, and this is the answer even when the roster is long.
   */
  @AuraEnabled(cacheable=true)
  public static List<MyAssignment> getMyAssignments() {
    assertAccessible();

    List<MyAssignment> out = new List<MyAssignment>();

    for (Financial_Advisor_Team_Member__c row : [
      SELECT
        Id,
        Role__c,
        Primary__c,
        Active__c,
        Start_Date__c,
        Employment_Status__c,
        Registered_States__c,
        Financial_Advisor_Team__c,
        Financial_Advisor_Team__r.Name,
        CSA__c,
        Draft_Paperwork__c,
        Trading__c,
        Associate_Advisor__c,
        Review_Paperwork__c,
        Send_Notifications__c,
        Operations__c,
        Project_Manager__c
      FROM Financial_Advisor_Team_Member__c
      WHERE User__c = :UserInfo.getUserId() AND Active__c = TRUE
      ORDER BY Financial_Advisor_Team__r.Name
      LIMIT :MAX_TEAMS
    ]) {
      MyAssignment a = new MyAssignment();
      a.memberId = row.Id;
      a.teamId = row.Financial_Advisor_Team__c;
      a.teamName = row.Financial_Advisor_Team__r == null
        ? null
        : row.Financial_Advisor_Team__r.Name;
      a.role = row.Role__c;
      a.isPrimary = row.Primary__c == true;
      a.startDate = row.Start_Date__c;
      a.employmentStatus = row.Employment_Status__c;
      a.registeredStates = row.Registered_States__c;
      a.permissions = grantedPermissions(row);
      out.add(a);
    }

    return out;
  }

  // ---- Assembly -----------------------------------------------------------

  private static List<TeamDetail> buildTeams(Set<Id> teamIds) {
    Map<Id, Financial_Advisor_Team__c> teams = new Map<Id, Financial_Advisor_Team__c>(
      [
        SELECT
          Id,
          Name,
          Orion_ID__c,
          Rep_Number__c,
          Status__c,
          Tiered_IMA_Advisory_Fee__c,
          Registered_States__c,
          of_Rep_Codes__c,
          Primary_Financial_Advisor__c,
          Primary_Financial_Advisor__r.Name,
          Primary_Financial_Advisor__r.FirstName,
          Primary_Financial_Advisor__r.LastName,
          Advisor_Group__c,
          Advisor_Group__r.Name,
          Owner.Name,
          Owner.FirstName,
          Owner.LastName
        FROM Financial_Advisor_Team__c
        WHERE Id IN :teamIds
        ORDER BY Name
        LIMIT :MAX_TEAMS
      ]
    );

    if (teams.isEmpty()) {
      return new List<TeamDetail>();
    }

    // One query for every team's members, then grouped in memory — a query
    // per team would be SOQL in a loop.
    Map<Id, List<TeamMember>> membersByTeam = new Map<Id, List<TeamMember>>();
    Map<Id, Map<String, List<String>>> permissionHoldersByTeam = new Map<Id, Map<String, List<String>>>();

    for (Id teamId : teams.keySet()) {
      membersByTeam.put(teamId, new List<TeamMember>());
      permissionHoldersByTeam.put(teamId, new Map<String, List<String>>());
    }

    for (Financial_Advisor_Team_Member__c row : [
      SELECT
        Id,
        Name,
        User__c,
        User__r.Name,
        User_Name__c,
        Role__c,
        Active__c,
        Primary__c,
        Start_Date__c,
        Employment_Status__c,
        Registered_States__c,
        Financial_Advisor_Team__c,
        CSA__c,
        Draft_Paperwork__c,
        Trading__c,
        Associate_Advisor__c,
        Review_Paperwork__c,
        Send_Notifications__c,
        Operations__c,
        Project_Manager__c
      FROM Financial_Advisor_Team_Member__c
      WHERE Financial_Advisor_Team__c IN :teamIds AND Active__c = TRUE
      ORDER BY Primary__c DESC, User_Name__c
      LIMIT :MAX_MEMBERS
    ]) {
      TeamMember m = new TeamMember();
      m.memberId = row.Id;
      m.userId = row.User__c;
      m.name = resolveMemberName(row);
      m.role = row.Role__c;
      m.isPrimary = row.Primary__c == true;
      m.startDate = row.Start_Date__c;
      m.employmentStatus = row.Employment_Status__c;
      m.registeredStates = row.Registered_States__c;
      m.permissions = grantedPermissions(row);

      membersByTeam.get(row.Financial_Advisor_Team__c).add(m);

      Map<String, List<String>> holders = permissionHoldersByTeam.get(
        row.Financial_Advisor_Team__c
      );
      for (String field : m.permissions) {
        if (!holders.containsKey(field)) {
          holders.put(field, new List<String>());
        }
        holders.get(field).add(m.name);
      }
    }

    Map<Id, List<RepCode>> repCodesByTeam = new Map<Id, List<RepCode>>();
    for (Id teamId : teams.keySet()) {
      repCodesByTeam.put(teamId, new List<RepCode>());
    }

    if (Schema.sObjectType.Rep_Code__c.isAccessible()) {
      for (Rep_Code__c row : [
        SELECT
          Id,
          Name,
          Rep_Code_Type__c,
          Status__c,
          Description__c,
          Financial_Advisor_Team__c
        FROM Rep_Code__c
        WHERE Financial_Advisor_Team__c IN :teamIds
        ORDER BY Name
        LIMIT :MAX_REP_CODES
      ]) {
        RepCode c = new RepCode();
        c.id = row.Id;
        c.name = row.Name;
        c.codeType = row.Rep_Code_Type__c;
        c.status = row.Status__c;
        c.description = row.Description__c;
        repCodesByTeam.get(row.Financial_Advisor_Team__c).add(c);
      }
    }

    List<TeamDetail> out = new List<TeamDetail>();
    for (Financial_Advisor_Team__c team : teams.values()) {
      TeamDetail d = new TeamDetail();
      d.id = team.Id;
      d.name = team.Name;
      d.orionId = team.Orion_ID__c;
      d.repNumber = team.Rep_Number__c;
      d.status = team.Status__c;
      d.hasTieredAdvisoryFee = team.Tiered_IMA_Advisory_Fee__c == true;
      d.registeredStates = team.Registered_States__c;
      d.branchName = team.Advisor_Group__r == null
        ? null
        : team.Advisor_Group__r.Name;
      d.ownerName = personName(
        team.Owner == null ? null : team.Owner.FirstName,
        team.Owner == null ? null : team.Owner.LastName,
        team.Owner == null ? null : team.Owner.Name
      );
      d.primaryAdvisorName = personName(
        team.Primary_Financial_Advisor__r == null
          ? null
          : team.Primary_Financial_Advisor__r.FirstName,
        team.Primary_Financial_Advisor__r == null
          ? null
          : team.Primary_Financial_Advisor__r.LastName,
        team.Primary_Financial_Advisor__r == null
          ? null
          : team.Primary_Financial_Advisor__r.Name
      );
      d.members = membersByTeam.get(team.Id);
      d.repCodes = repCodesByTeam.get(team.Id);
      d.permissions = toPermissionRows(permissionHoldersByTeam.get(team.Id));
      out.add(d);
    }

    return out;
  }

  /**
   * Every permission row, including the ones nobody holds. An empty row is
   * the useful answer here — "no one on this team can trade" is exactly what
   * someone auditing permissions needs to see, and dropping it would leave
   * them unable to tell it apart from the permission not existing.
   */
  private static List<PermissionRow> toPermissionRows(
    Map<String, List<String>> holders
  ) {
    List<PermissionRow> out = new List<PermissionRow>();
    for (String field : PERMISSION_FIELDS) {
      PermissionRow r = new PermissionRow();
      r.field = field;
      r.label = PERMISSION_LABELS.get(field);
      r.holders = holders.containsKey(field)
        ? holders.get(field)
        : new List<String>();
      out.add(r);
    }
    return out;
  }

  private static List<String> grantedPermissions(
    Financial_Advisor_Team_Member__c row
  ) {
    List<String> granted = new List<String>();
    if (row.CSA__c == true) {
      granted.add('CSA__c');
    }
    if (row.Draft_Paperwork__c == true) {
      granted.add('Draft_Paperwork__c');
    }
    if (row.Trading__c == true) {
      granted.add('Trading__c');
    }
    if (row.Associate_Advisor__c == true) {
      granted.add('Associate_Advisor__c');
    }
    if (row.Review_Paperwork__c == true) {
      granted.add('Review_Paperwork__c');
    }
    if (row.Send_Notifications__c == true) {
      granted.add('Send_Notifications__c');
    }
    if (row.Operations__c == true) {
      granted.add('Operations__c');
    }
    if (row.Project_Manager__c == true) {
      granted.add('Project_Manager__c');
    }
    return granted;
  }

  /**
   * User_Name__c is a formula over User__r.FirstName/LastName and is the
   * label the internal related list shows, so it wins. It comes back blank
   * when the member row has no user linked, which the roster still has to
   * render — hence the fallbacks rather than a null name.
   */
  private static String resolveMemberName(
    Financial_Advisor_Team_Member__c row
  ) {
    if (String.isNotBlank(row.User_Name__c)) {
      return row.User_Name__c;
    }
    if (row.User__r != null && String.isNotBlank(row.User__r.Name)) {
      return row.User__r.Name;
    }
    return row.Name;
  }

  /**
   * A person's name built from FirstName/LastName, not from User.Name.
   *
   * Read through Apex on the Experience site, User.Name comes back
   * obfuscated — the ARCQA team's primary advisor reads back as
   * "User17866426362109754018" where the record holds "Mahesh Kumar".
   * FirstName and LastName are not masked the same way, which is also why the
   * roster (which goes through the User_Name__c formula over those two
   * fields) showed real names while these two header fields did not.
   *
   * Falls back to the raw name for an owner that is a queue rather than a
   * user, where there are no first/last parts to build from.
   */
  private static String personName(
    String firstName,
    String lastName,
    String fallback
  ) {
    List<String> parts = new List<String>();
    if (String.isNotBlank(firstName)) {
      parts.add(firstName.trim());
    }
    if (String.isNotBlank(lastName)) {
      parts.add(lastName.trim());
    }
    return parts.isEmpty() ? fallback : String.join(parts, ' ');
  }

  private static void assertAccessible() {
    if (
      !Schema.sObjectType.Financial_Advisor_Team__c.isAccessible() ||
      !Schema.sObjectType.Financial_Advisor_Team_Member__c.isAccessible() ||
      !Schema.sObjectType.Financial_Advisor_Team_Member__c.fields.Role__c.isAccessible()
    ) {
      throw new AuraHandledException(
        'You do not have access to financial advisor teams.'
      );
    }
  }

  // ---- Wrappers exposed to LWC --------------------------------------------

  public class TeamDetail {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    /* Orion_ID__c is Number(18,0) in the org, not text — the local field
           metadata says Text and is stale. Left as a Decimal and formatted by
           the component rather than stringified here. */
    @AuraEnabled
    public Decimal orionId;
    @AuraEnabled
    public String repNumber;
    @AuraEnabled
    public String status;
    /* Tiered_IMA_Advisory_Fee__c is a checkbox, despite reading like an
           amount — it says whether the team is on the tiered schedule, not what
           the fee is. Named for what it holds so the tab cannot render it as a
           number. */
    @AuraEnabled
    public Boolean hasTieredAdvisoryFee;
    @AuraEnabled
    public String registeredStates;
    @AuraEnabled
    public String branchName;
    @AuraEnabled
    public String ownerName;
    @AuraEnabled
    public String primaryAdvisorName;
    @AuraEnabled
    public List<TeamMember> members;
    @AuraEnabled
    public List<RepCode> repCodes;
    @AuraEnabled
    public List<PermissionRow> permissions;
  }

  public class TeamMember {
    @AuraEnabled
    public Id memberId;
    @AuraEnabled
    public Id userId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String role;
    @AuraEnabled
    public Boolean isPrimary;
    @AuraEnabled
    public Date startDate;
    @AuraEnabled
    public String employmentStatus;
    @AuraEnabled
    public String registeredStates;
    /** Field API names of the permissions this member holds. */
    @AuraEnabled
    public List<String> permissions;
  }

  public class PermissionRow {
    @AuraEnabled
    public String field;
    @AuraEnabled
    public String label;
    /** Member names tied to this permission; empty when nobody holds it. */
    @AuraEnabled
    public List<String> holders;
  }

  public class RepCode {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String codeType;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String description;
  }

  public class MyAssignment {
    @AuraEnabled
    public Id memberId;
    @AuraEnabled
    public Id teamId;
    @AuraEnabled
    public String teamName;
    /** The member's role on that team — not the team itself. */
    @AuraEnabled
    public String role;
    @AuraEnabled
    public Boolean isPrimary;
    @AuraEnabled
    public Date startDate;
    @AuraEnabled
    public String employmentStatus;
    @AuraEnabled
    public String registeredStates;
    @AuraEnabled
    public List<String> permissions;
  }
}