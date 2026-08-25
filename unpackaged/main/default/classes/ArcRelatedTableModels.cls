/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-11
 *
 * DTOs for arcRelatedTable.
 */
public with sharing class ArcRelatedTableModels {
  public class TableData {
    @AuraEnabled
    public List<TableRow> rows { get; set; }
    @AuraEnabled
    public Integer totalCount { get; set; }

    public TableData() {
      this.rows = new List<TableRow>();
      this.totalCount = 0;
    }
  }

  public class TableRow {
    @AuraEnabled
    public String id { get; set; }
    @AuraEnabled
    public String recordType { get; set; }
    @AuraEnabled
    public String name { get; set; }
    @AuraEnabled
    public String subject { get; set; }
    @AuraEnabled
    public String household { get; set; }
    @AuraEnabled
    public String advisorTeam { get; set; }
    @AuraEnabled
    public String status { get; set; }
    @AuraEnabled
    public String ownerName { get; set; }
    @AuraEnabled
    public String relatedTo { get; set; }
    @AuraEnabled
    public String lastModified { get; set; }
    @AuraEnabled
    public Datetime lastModifiedRaw { get; set; }
    @AuraEnabled
    public String activityDate { get; set; }
    @AuraEnabled
    public Datetime activityDateRaw { get; set; }
    @AuraEnabled
    public String mainTrackTasks { get; set; }
    @AuraEnabled
    public Integer completedMainTrack { get; set; }
    @AuraEnabled
    public Integer totalMainTrack { get; set; }
  }
}