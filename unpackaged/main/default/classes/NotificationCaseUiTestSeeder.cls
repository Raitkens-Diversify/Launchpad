/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 *
 * Seeds Case UI test records on the Simpson household for notification
 * ownership scenarios AC1 (NexS) and AC2 (Home Office).
 */
public without sharing class NotificationCaseUiTestSeeder {
  public static final Id DEFAULT_HOUSEHOLD_ID = SimpsonMapDemoDataSeeder.HOUSEHOLD_ID;

  public class SeedResult {
    public Id householdId;
    public String householdName;
    public Case ac1NexsCase;
    public Case ac2HomeOfficeCase;
    public Id expectedNexsRecipientId;
    public Id expectedHomeOfficeRecipientId;
    public List<Notification_Log__c> notificationLogs = new List<Notification_Log__c>();
  }

  public static SeedResult seedForHousehold(Id householdId) {
    if (householdId == null) {
      throw new IllegalArgumentException('householdId is required.');
    }

    Account household = [
      SELECT Id, Name, Financial_Advisor_Team__c
      FROM Account
      WHERE Id = :householdId
      LIMIT 1
    ];

    Id primaryContactId = selectPrimaryContactId(householdId);
    User homeOfficeOwner = resolveHomeOfficeOwner();
    User ac1CaseOwner = resolveAc1CaseOwner(homeOfficeOwner);
    User nexsPrimaryAdvisor = selectPrimaryAdvisorForTeam(
      household.Financial_Advisor_Team__c,
      NotificationConstants.PROFILE_NEXS
    );

    String seedMarker = 'UI-' + String.valueOf(System.now().getTime()).right(6);

    Case ac1NexsCase = buildUiTestCase(
      seedMarker +
        ' [UI-AC1 NexS] Case Insert on Simpson Household — Primary Advisor FA Team Path',
      household,
      primaryContactId,
      ac1CaseOwner.Id,
      'AC1 UI test: NexS user should receive notification when Case is on household ' +
        household.Name +
        ', serviced by FA team where user is Primary Advisor. Triggers: Insert, Assigned To change, Status update.'
    );

    Case ac2HomeOfficeCase = buildUiTestCase(
      seedMarker +
        ' [UI-AC2 Home Office] Case Insert on Simpson Household — Case Owner Path',
      household,
      primaryContactId,
      homeOfficeOwner.Id,
      'AC2 UI test: Home Office user should receive notification when they own the Case or are a member of the owning queue. Triggers: Insert, Assigned To change, Status update.'
    );

    insert new List<Case>{ ac1NexsCase, ac2HomeOfficeCase };

    insert new List<CaseComment>{
      new CaseComment(
        ParentId = ac1NexsCase.Id,
        CommentBody = 'UI-AC1 sample comment — verify NexS Case notification email shows latest published comment.',
        IsPublished = true
      ),
      new CaseComment(
        ParentId = ac2HomeOfficeCase.Id,
        CommentBody = 'UI-AC2 sample comment — verify Home Office Case notification email shows latest published comment.',
        IsPublished = true
      )
    };

    SeedResult result = new SeedResult();
    result.householdId = household.Id;
    result.householdName = household.Name;
    result.ac1NexsCase = ac1NexsCase;
    result.ac2HomeOfficeCase = ac2HomeOfficeCase;
    result.expectedNexsRecipientId = nexsPrimaryAdvisor == null
      ? null
      : nexsPrimaryAdvisor.Id;
    result.expectedHomeOfficeRecipientId = homeOfficeOwner.Id;
    result.notificationLogs = selectNotificationLogs(
      new Set<String>{
        String.valueOf(ac1NexsCase.Id),
        String.valueOf(ac2HomeOfficeCase.Id)
      }
    );
    return result;
  }

  public static void logResult(SeedResult result) {
    System.debug('=== Case Notification UI Test Records ===');
    System.debug('Household: ' + result.householdName + ' (' + result.householdId + ')');
    System.debug(
      'AC1 NexS case: ' +
        result.ac1NexsCase.Id +
        ' | Subject: ' +
        result.ac1NexsCase.Subject
    );
    System.debug(
      'AC2 Home Office case: ' +
        result.ac2HomeOfficeCase.Id +
        ' | Subject: ' +
        result.ac2HomeOfficeCase.Subject
    );
    System.debug(
      'Expected AC1 NexS recipient (primary advisor): ' + result.expectedNexsRecipientId
    );
    System.debug(
      'Expected AC2 Home Office recipient (owner): ' +
        result.expectedHomeOfficeRecipientId
    );
    System.debug(
      'Notification logs created (async flow may add more): ' +
        result.notificationLogs.size()
    );

    for (Notification_Log__c logRecord : result.notificationLogs) {
      System.debug(
        '  ' +
          logRecord.Name +
          ' | Case ' +
          logRecord.Source_Record_Id__c +
          ' | ' +
          logRecord.Recipient__r.Name +
          ' (' +
          logRecord.Recipient__r.Profile.Name +
          ') | ' +
          logRecord.Status__c +
          ' | ' +
          logRecord.Channel__c +
          ' | Rule: ' +
          logRecord.Notification_Rule__r.Rule_Name__c
      );
    }

    System.debug('=== UI Verification Checklist ===');
    System.debug(
      '1. Log in as NexS primary advisor and confirm notification for subject containing "[UI-AC1 NexS]".'
    );
    System.debug(
      '2. Log in as Home Office case owner and confirm notification for subject containing "[UI-AC2 Home Office]".'
    );
    System.debug(
      '3. Update Assigned To or Status on each case and confirm notification follows active Case rule settings.'
    );
  }

  private static Case buildUiTestCase(
    String subject,
    Account household,
    Id contactId,
    Id ownerId,
    String description
  ) {
    Case caseRecord = new Case(
      Subject = subject,
      AccountId = household.Id,
      OwnerId = ownerId,
      Status = 'New',
      Origin = 'Phone',
      Description = description,
      Due_Date_of_Current_Task__c = Date.today().addDays(14)
    );

    if (contactId != null) {
      caseRecord.ContactId = contactId;
    }

    if (household.Financial_Advisor_Team__c != null) {
      caseRecord.Financial_Advisor_Team__c = household.Financial_Advisor_Team__c;
    }

    return caseRecord;
  }

  private static Id selectPrimaryContactId(Id householdId) {
    List<AccountContactRelation> contactRelations = [
      SELECT ContactId
      FROM AccountContactRelation
      WHERE AccountId = :householdId
      ORDER BY Contact.Name ASC
      LIMIT 1
    ];
    return contactRelations.isEmpty() ? null : contactRelations[0].ContactId;
  }

  private static User resolveHomeOfficeOwner() {
    User homeOfficeOwner = selectActiveUserByProfile(
      NotificationConstants.PROFILE_HOME_OFFICE
    );
    if (homeOfficeOwner != null) {
      return homeOfficeOwner;
    }

    homeOfficeOwner = [
      SELECT Id, Profile.Name
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];
    System.debug(
      'WARN: No active Home Office user found. AC2 case owner falls back to running user (' +
        homeOfficeOwner.Profile.Name +
        ').'
    );
    return homeOfficeOwner;
  }

  private static User resolveAc1CaseOwner(User homeOfficeOwner) {
    User systemAdminOwner = selectActiveUserByProfile(
      NotificationConstants.PROFILE_SYSTEM_ADMINISTRATOR
    );
    if (systemAdminOwner != null && systemAdminOwner.Id != homeOfficeOwner.Id) {
      return systemAdminOwner;
    }

    User runningUser = [
      SELECT Id, Profile.Name
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];

    if (runningUser.Id != homeOfficeOwner.Id) {
      return runningUser;
    }

    System.debug(
      'WARN: AC1 case owner matches Home Office owner. AC1 may also trigger AC2 owner notifications.'
    );
    return homeOfficeOwner;
  }

  private static User selectActiveUserByProfile(String profileName) {
    List<User> users = [
      SELECT Id, Name, Profile.Name
      FROM User
      WHERE Profile.Name = :profileName AND IsActive = TRUE
      ORDER BY Name
      LIMIT 1
    ];
    return users.isEmpty() ? null : users[0];
  }

  private static User selectPrimaryAdvisorForTeam(Id teamId, String profileName) {
    if (teamId == null) {
      return null;
    }

    List<Financial_Advisor_Team_Member__c> members = [
      SELECT User__c, User__r.Id, User__r.Name, User__r.Profile.Name
      FROM Financial_Advisor_Team_Member__c
      WHERE
        Financial_Advisor_Team__c = :teamId
        AND Primary__c = TRUE
        AND Active__c = TRUE
        AND User__c != NULL
        AND User__r.Profile.Name = :profileName
        AND User__r.IsActive = TRUE
      ORDER BY User__r.Name
      LIMIT 1
    ];

    if (members.isEmpty()) {
      System.debug(
        'WARN: No NexS primary advisor on household FA team. AC1 verification may require FA team membership setup.'
      );
      return null;
    }

    return members[0].User__r;
  }

  private static List<Notification_Log__c> selectNotificationLogs(
    Set<String> sourceRecordIds
  ) {
    return [
      SELECT
        Id,
        Name,
        Recipient__c,
        Recipient__r.Name,
        Recipient__r.Profile.Name,
        Source_Record_Id__c,
        Status__c,
        Channel__c,
        Frequency__c,
        Notification_Rule__r.Rule_Name__c
      FROM Notification_Log__c
      WHERE Source_Record_Id__c IN :sourceRecordIds
      ORDER BY Source_Record_Id__c, Recipient__r.Name
    ];
  }
}