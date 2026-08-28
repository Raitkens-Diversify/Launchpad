/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-28
 *
 * Repository for Significant Event create/edit reads and writes.
 */
public with sharing class SignificantEventActionRepository {
  public static final String HOUSEHOLD_RECORD_TYPE = FscRelAccountRepository.HOUSEHOLD_RECORD_TYPE;
  public static final String LEGACY_HOUSEHOLD_RECORD_TYPE = FscRelAccountRepository.LEGACY_HOUSEHOLD_RECORD_TYPE;
  public static final String EVENT_TYPE_OTHER = 'Other';

  public Account selectContextAccount(Id accountId) {
    if (accountId == null) {
      return null;
    }

    List<Account> accounts = [
      SELECT
        Id,
        Name,
        IsPersonAccount,
        PersonContactId,
        Household__c,
        Financial_Advisor_Team__c,
        RecordType.DeveloperName,
        RecordType.Name
      FROM Account
      WHERE Id = :accountId
      LIMIT 1
    ];

    return accounts.isEmpty() ? null : accounts[0];
  }

  public List<Account> searchNonHouseholdAccounts(String searchTerm, Integer limitSize) {
    if (String.isBlank(searchTerm)) {
      return new List<Account>();
    }

    String trimmedTerm = searchTerm.trim();
    if (trimmedTerm.length() < 2) {
      return new List<Account>();
    }

    Integer safeLimit = limitSize == null || limitSize < 1
      ? 8
      : Math.min(limitSize, 25);
    String escapedTerm = String.escapeSingleQuotes(trimmedTerm);
    String likeTerm = '%' + escapedTerm + '%';

    Set<String> householdRecordTypeDeveloperNames = FscRelAccountRepository.selectHouseholdRecordTypeDeveloperNames();

    return [
      SELECT Id, Name, RecordType.DeveloperName, RecordType.Name
      FROM Account
      WHERE
        Name LIKE :likeTerm
        AND RecordType.DeveloperName NOT IN :householdRecordTypeDeveloperNames
      ORDER BY Name
      LIMIT :safeLimit
    ];
  }

  public Significant_Event__c selectSignificantEventById(Id significantEventId) {
    if (significantEventId == null) {
      return null;
    }

    List<Significant_Event__c> events = [
      SELECT
        Id,
        Name,
        Event_Type__c,
        Other_Event_Type__c,
        Start_Date__c,
        End_Date_Optional__c,
        Approximate_Date__c,
        Description__c,
        Household__c,
        Financial_Advisor_Team__c
      FROM Significant_Event__c
      WHERE Id = :significantEventId
      LIMIT 1
    ];

    return events.isEmpty() ? null : events[0];
  }

  public List<Significant_Event_Contact__c> selectParticipantsByEventId(
    Id significantEventId
  ) {
    if (significantEventId == null) {
      return new List<Significant_Event_Contact__c>();
    }

    return [
      SELECT
        Id,
        Name,
        Account__c,
        Account__r.Name,
        Significant_Event__c,
        Significant_Event__r.Name,
        Significant_Event__r.Event_Type__c,
        Significant_Event__r.Other_Event_Type__c,
        Significant_Event__r.Start_Date__c,
        Significant_Event__r.End_Date_Optional__c,
        Significant_Event__r.Approximate_Date__c,
        Significant_Event__r.Description__c,
        Significant_Event__r.Household__c,
        Significant_Event__r.Household__r.Name,
        Significant_Event__r.Financial_Advisor_Team__c,
        Significant_Event__r.Financial_Advisor_Team__r.Name,
        Financial_Advisor_Team__c
      FROM Significant_Event_Contact__c
      WHERE Significant_Event__c = :significantEventId
      ORDER BY Account__r.Name
    ];
  }

  public Significant_Event__c insertSignificantEvent(Significant_Event__c eventRecord) {
    insert eventRecord;
    return eventRecord;
  }

  public Significant_Event__c updateSignificantEvent(Significant_Event__c eventRecord) {
    update eventRecord;
    return eventRecord;
  }

  public void insertParticipants(List<Significant_Event_Contact__c> participants) {
    if (participants == null || participants.isEmpty()) {
      return;
    }

    insert participants;
  }

  public void updateParticipants(List<Significant_Event_Contact__c> participants) {
    if (participants == null || participants.isEmpty()) {
      return;
    }

    update participants;
  }

  public void deleteParticipants(List<Significant_Event_Contact__c> participants) {
    if (participants == null || participants.isEmpty()) {
      return;
    }

    delete participants;
  }

  public void deleteSignificantEvent(Significant_Event__c eventRecord) {
    if (eventRecord == null || eventRecord.Id == null) {
      return;
    }

    delete eventRecord;
  }

  public List<Significant_Event_Contact__c> selectParticipantsByAccountIds(
    Set<Id> accountIds
  ) {
    if (accountIds == null || accountIds.isEmpty()) {
      return new List<Significant_Event_Contact__c>();
    }

    return [
      SELECT
        Id,
        Name,
        Account__c,
        Account__r.Name,
        Significant_Event__c,
        Significant_Event__r.Name,
        Significant_Event__r.Event_Type__c,
        Significant_Event__r.Other_Event_Type__c,
        Significant_Event__r.Start_Date__c,
        Significant_Event__r.End_Date_Optional__c,
        Significant_Event__r.Approximate_Date__c,
        Significant_Event__r.Description__c,
        Significant_Event__r.Household__c,
        Significant_Event__r.Household__r.Name,
        Significant_Event__r.Financial_Advisor_Team__c,
        Significant_Event__r.Financial_Advisor_Team__r.Name
      FROM Significant_Event_Contact__c
      WHERE Account__c IN :accountIds
      ORDER BY
        Significant_Event__r.Start_Date__c DESC NULLS LAST,
        Account__r.Name
    ];
  }

  public List<Significant_Event_Contact__c> selectParticipantsByDirectEventAccountId(
    Id accountId
  ) {
    if (accountId == null) {
      return new List<Significant_Event_Contact__c>();
    }

    return [
      SELECT
        Id,
        Name,
        Account__c,
        Account__r.Name,
        Significant_Event__c,
        Significant_Event__r.Name,
        Significant_Event__r.Event_Type__c,
        Significant_Event__r.Other_Event_Type__c,
        Significant_Event__r.Start_Date__c,
        Significant_Event__r.End_Date_Optional__c,
        Significant_Event__r.Approximate_Date__c,
        Significant_Event__r.Description__c,
        Significant_Event__r.Household__c,
        Significant_Event__r.Household__r.Name,
        Significant_Event__r.Financial_Advisor_Team__c,
        Significant_Event__r.Financial_Advisor_Team__r.Name,
        Significant_Event__r.Person__c
      FROM Significant_Event_Contact__c
      WHERE
        Significant_Event__r.Household__c = :accountId
        OR Significant_Event__r.Person__c = :accountId
      ORDER BY
        Significant_Event__r.Start_Date__c DESC NULLS LAST,
        Account__r.Name
    ];
  }

  public List<Significant_Event_Contact__c> selectParticipantsByDirectEventAccountIds(
    Set<Id> accountIds
  ) {
    if (accountIds == null || accountIds.isEmpty()) {
      return new List<Significant_Event_Contact__c>();
    }

    return [
      SELECT
        Id,
        Name,
        Account__c,
        Account__r.Name,
        Significant_Event__c,
        Significant_Event__r.Name,
        Significant_Event__r.Event_Type__c,
        Significant_Event__r.Other_Event_Type__c,
        Significant_Event__r.Start_Date__c,
        Significant_Event__r.End_Date_Optional__c,
        Significant_Event__r.Approximate_Date__c,
        Significant_Event__r.Description__c,
        Significant_Event__r.Household__c,
        Significant_Event__r.Household__r.Name,
        Significant_Event__r.Financial_Advisor_Team__c,
        Significant_Event__r.Financial_Advisor_Team__r.Name,
        Significant_Event__r.Person__c
      FROM Significant_Event_Contact__c
      WHERE
        Significant_Event__r.Household__c IN :accountIds
        OR Significant_Event__r.Person__c IN :accountIds
      ORDER BY
        Significant_Event__r.Start_Date__c DESC NULLS LAST,
        Account__r.Name
    ];
  }

  public List<Significant_Event_Contact__c> selectParticipantsByFinancialAdvisorTeamIds(
    Set<Id> teamIds
  ) {
    if (teamIds == null || teamIds.isEmpty()) {
      return new List<Significant_Event_Contact__c>();
    }

    return [
      SELECT
        Id,
        Name,
        Account__c,
        Account__r.Name,
        Significant_Event__c,
        Significant_Event__r.Name,
        Significant_Event__r.Event_Type__c,
        Significant_Event__r.Other_Event_Type__c,
        Significant_Event__r.Start_Date__c,
        Significant_Event__r.End_Date_Optional__c,
        Significant_Event__r.Approximate_Date__c,
        Significant_Event__r.Description__c,
        Significant_Event__r.Household__c,
        Significant_Event__r.Household__r.Name,
        Significant_Event__r.Financial_Advisor_Team__c,
        Significant_Event__r.Financial_Advisor_Team__r.Name
      FROM Significant_Event_Contact__c
      WHERE Significant_Event__r.Financial_Advisor_Team__c IN :teamIds
      ORDER BY
        Significant_Event__r.Start_Date__c DESC NULLS LAST,
        Account__r.Name
    ];
  }
}