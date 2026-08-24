/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-21
 */
public with sharing class SignificantEventActionModels {
  public class CreateContext {
    @AuraEnabled
    public Boolean isHouseholdLaunch;
    @AuraEnabled
    public Boolean isEditMode;
    @AuraEnabled
    public String contextAccountId;
    @AuraEnabled
    public String contextAccountName;
    @AuraEnabled
    public String contextRecordTypeDeveloperName;
    @AuraEnabled
    public String householdId;
    @AuraEnabled
    public String financialAdvisorTeamId;
    @AuraEnabled
    public List<LinkedAccountOption> defaultSelectedAccounts;
    @AuraEnabled
    public SignificantEventFormData eventData;

    public CreateContext() {
      this.isHouseholdLaunch = false;
      this.isEditMode = false;
      this.defaultSelectedAccounts = new List<LinkedAccountOption>();
    }
  }

  public class SignificantEventFormData {
    @AuraEnabled
    public String significantEventId;
    @AuraEnabled
    public String eventName;
    @AuraEnabled
    public String eventType;
    @AuraEnabled
    public String otherEventType;
    @AuraEnabled
    public String startDate;
    @AuraEnabled
    public String endDate;
    @AuraEnabled
    public Boolean approximateDate;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public List<LinkedAccountOption> selectedAccounts;

    public SignificantEventFormData() {
      this.approximateDate = false;
      this.selectedAccounts = new List<LinkedAccountOption>();
    }
  }

  public class LinkedAccountOption {
    @AuraEnabled
    public String accountId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Boolean isHouseholdRelated;

    public LinkedAccountOption() {
      this.isHouseholdRelated = false;
    }

    public LinkedAccountOption(
      String accountId,
      String name,
      Boolean isHouseholdRelated
    ) {
      this.accountId = accountId;
      this.name = name;
      this.isHouseholdRelated = isHouseholdRelated == true;
    }
  }

  public class SuggestedContactGroup {
    @AuraEnabled
    public String category;
    @AuraEnabled
    public List<LinkedAccountOption> contacts;

    public SuggestedContactGroup() {
      this.contacts = new List<LinkedAccountOption>();
    }

    public SuggestedContactGroup(
      String category,
      List<LinkedAccountOption> contacts
    ) {
      this.category = category;
      this.contacts = contacts == null
        ? new List<LinkedAccountOption>()
        : contacts;
    }
  }

  public class SaveRequest {
    @AuraEnabled
    public String significantEventId;
    @AuraEnabled
    public String eventName;
    @AuraEnabled
    public String eventType;
    @AuraEnabled
    public String otherEventType;
    @AuraEnabled
    public String startDate;
    @AuraEnabled
    public String endDate;
    @AuraEnabled
    public Boolean approximateDate;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public String contextAccountId;
    @AuraEnabled
    public String householdId;
    @AuraEnabled
    public List<String> linkedAccountIds;

    public SaveRequest() {
      this.approximateDate = false;
      this.linkedAccountIds = new List<String>();
    }
  }

  public class SaveResult {
    @AuraEnabled
    public Boolean success;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public String significantEventId;

    public SaveResult(Boolean success, String message, String significantEventId) {
      this.success = success;
      this.message = message;
      this.significantEventId = significantEventId;
    }

    public SaveResult() {
      this(false, '', null);
    }
  }

  public class SignificantEventRow {
    @AuraEnabled
    public String significantEventId;
    @AuraEnabled
    public String eventName;
    @AuraEnabled
    public String eventType;
    @AuraEnabled
    public String otherEventType;
    @AuraEnabled
    public String startDate;
    @AuraEnabled
    public String endDate;
    @AuraEnabled
    public Boolean approximateDate;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public String householdId;
    @AuraEnabled
    public String householdName;

    public SignificantEventRow() {
      this.approximateDate = false;
    }

    public SignificantEventRow(
      String significantEventId,
      String eventName,
      String eventType
    ) {
      this.significantEventId = significantEventId;
      this.eventName = eventName;
      this.eventType = eventType;
      this.approximateDate = false;
    }
  }

  public class LinkedContactRow {
    @AuraEnabled
    public String participantId;
    @AuraEnabled
    public String participantName;
    @AuraEnabled
    public String accountId;
    @AuraEnabled
    public String accountName;
    @AuraEnabled
    public String significantEventId;
    @AuraEnabled
    public String eventName;
    @AuraEnabled
    public String eventType;
    @AuraEnabled
    public String otherEventType;
    @AuraEnabled
    public String startDate;
    @AuraEnabled
    public String endDate;
    @AuraEnabled
    public Boolean approximateDate;
    @AuraEnabled
    public String householdId;
    @AuraEnabled
    public String householdName;
    @AuraEnabled
    public String financialAdvisorTeamId;
    @AuraEnabled
    public String financialAdvisorTeamName;
    @AuraEnabled
    public String description;

    public LinkedContactRow() {
      this.approximateDate = false;
    }

    public LinkedContactRow(String participantId, String accountId) {
      this.participantId = participantId;
      this.accountId = accountId;
      this.approximateDate = false;
    }
  }
}