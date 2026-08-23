/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-11
 *
 * DTOs for arcTaskMetrics.
 */
public with sharing class ArcTaskMetricsModels {
  public class MetricsResult {
    @AuraEnabled
    public Integer mainTrackCount { get; set; }

    @AuraEnabled
    public Integer hoPitStopCount { get; set; }

    @AuraEnabled
    public Integer branchPitStopCount { get; set; }

    public MetricsResult() {
      this.mainTrackCount = 0;
      this.hoPitStopCount = 0;
      this.branchPitStopCount = 0;
    }
  }
}