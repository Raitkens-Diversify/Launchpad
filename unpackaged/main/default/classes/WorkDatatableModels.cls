/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-11
 *
 * DTOs for workTable — Case rows with grouped Tasks for expansion.
 */
public with sharing class WorkDatatableModels {
  public class WorkDatatableData {
    @AuraEnabled
    public List<WorkCaseRow> cases { get; set; }
    @AuraEnabled
    public Integer totalCount { get; set; }

    public WorkDatatableData() {
      this.cases = new List<WorkCaseRow>();
      this.totalCount = 0;
    }
  }

  public class WorkCaseRow {
    @AuraEnabled
    public String id { get; set; }
    @AuraEnabled
    public String objectApiName { get; set; }
    @AuraEnabled
    public String ownerId { get; set; }
    @AuraEnabled
    public String caseName { get; set; }
    @AuraEnabled
    public String caseNumber { get; set; }
    @AuraEnabled
    public String currentTaskSubject { get; set; }
    @AuraEnabled
    public String assigneeName { get; set; }
    @AuraEnabled
    public String currentTaskSubjectAssignee { get; set; }
    @AuraEnabled
    public String ownerName { get; set; }
    @AuraEnabled
    public Datetime createdDate { get; set; }
    @AuraEnabled
    public String financialAdvisorTeamName { get; set; }
    @AuraEnabled
    public String overallStatus { get; set; }
    @AuraEnabled
    public String overallStatusPillClass { get; set; }
    @AuraEnabled
    public String milestoneStatus { get; set; }
    @AuraEnabled
    public String milestoneStatusPillClass { get; set; }
    @AuraEnabled
    public String mainTrackTasks { get; set; }
    @AuraEnabled
    public Integer completedMainTrack { get; set; }
    @AuraEnabled
    public Integer totalMainTrack { get; set; }
    @AuraEnabled
    public Datetime lastModifiedRaw { get; set; }
    @AuraEnabled
    public List<WorkTaskGroup> taskGroups { get; set; }

    public WorkCaseRow() {
      this.objectApiName = 'Case';
      this.taskGroups = new List<WorkTaskGroup>();
    }
  }

  public class WorkTaskGroup {
    @AuraEnabled
    public String key { get; set; }
    @AuraEnabled
    public String label { get; set; }
    @AuraEnabled
    public List<WorkTaskRow> tasks { get; set; }

    public WorkTaskGroup() {
      this.tasks = new List<WorkTaskRow>();
    }
  }

  public class WorkTaskRow {
    @AuraEnabled
    public String id { get; set; }
    @AuraEnabled
    public String name { get; set; }
    @AuraEnabled
    public String ownerName { get; set; }
    @AuraEnabled
    public String status { get; set; }
    @AuraEnabled
    public String statusPillClass { get; set; }
    @AuraEnabled
    public String dueDate { get; set; }
    @AuraEnabled
    public String completedDate { get; set; }
    @AuraEnabled
    public Boolean isStarred { get; set; }
  }
}