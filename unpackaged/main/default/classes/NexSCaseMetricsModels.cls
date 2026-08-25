/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-12
 *
 * DTOs for nexSCaseMetrics.
 */
public with sharing class NexSCaseMetricsModels {
  public class MetricsResult {
    @AuraEnabled
    public Integer totalCount { get; set; }

    @AuraEnabled
    public List<MilestoneSegment> segments { get; set; }

    public MetricsResult() {
      this.totalCount = 0;
      this.segments = new List<MilestoneSegment>();
    }
  }

  public class MilestoneSegment {
    @AuraEnabled
    public String key { get; set; }

    @AuraEnabled
    public String label { get; set; }

    @AuraEnabled
    public Integer count { get; set; }

    public MilestoneSegment() {
      this.count = 0;
    }
  }
}