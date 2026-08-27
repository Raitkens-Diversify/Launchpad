/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-27
 *
 * DTOs for Activity Timeline reads.
 */
public with sharing class ActivityTimelineModels {
  public class Participant {
    @AuraEnabled
    public String id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String objectApiName;

    public Participant() {
    }

    public Participant(String id, String name, String objectApiName) {
      this.id = id;
      this.name = name;
      this.objectApiName = objectApiName;
    }
  }

  public class ActivityItem {
    @AuraEnabled
    public String id;
    @AuraEnabled
    public String dateValue;
    @AuraEnabled
    public Long activityDateTime;
    @AuraEnabled
    public Boolean hasDueDate;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String activityType;
    @AuraEnabled
    public String category;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public List<Participant> participants;
    @AuraEnabled
    public String ownerId;
    @AuraEnabled
    public String ownerName;
    @AuraEnabled
    public List<Participant> relatedParticipants;
    @AuraEnabled
    public String linkedRecord;
    @AuraEnabled
    public String linkedRecordId;
    @AuraEnabled
    public String linkedRecordObjectApiName;
    @AuraEnabled
    public String associatedAccountId;
    @AuraEnabled
    public String associatedAccountName;
    @AuraEnabled
    public String icon;
    @AuraEnabled
    public String recordObjectApiName;
    @AuraEnabled
    public String fromAddress;
    @AuraEnabled
    public String endDateValue;
    @AuraEnabled
    public Boolean approximateDate;

    public ActivityItem() {
      this.participants = new List<Participant>();
      this.relatedParticipants = new List<Participant>();
    }
  }

  public class ActivityTimelineData {
    @AuraEnabled
    public List<ActivityItem> activities;
    @AuraEnabled
    public Map<String, Integer> categoryCounts;
    @AuraEnabled
    public Boolean showExternalToggle;
    @AuraEnabled
    public Boolean isHomeOfficeUser;
    @AuraEnabled
    public Boolean isHouseholdRecordContext;
    @AuraEnabled
    public Boolean isDrpRecordContext;
    @AuraEnabled
    public String contextBranchId;
    @AuraEnabled
    public String contextBranchName;
    @AuraEnabled
    public Boolean hasMoreActivities;
    @AuraEnabled
    public Integer nextPageNumber;

    public ActivityTimelineData() {
      this.activities = new List<ActivityItem>();
      this.categoryCounts = new Map<String, Integer>();
      this.showExternalToggle = false;
      this.isHomeOfficeUser = false;
      this.isHouseholdRecordContext = false;
      this.isDrpRecordContext = false;
      this.hasMoreActivities = false;
      this.nextPageNumber = 0;
    }
  }
}