/**
 * Result shape for arcHomeMetrics (the 5-tile Home dashboard KPI row).
 */
public class ArcHomeMetricsModels {
  public class MetricsResult {
    @AuraEnabled
    public Integer casesAssignedToMe = 0;
    @AuraEnabled
    public Integer tasksAssignedToMe = 0;
    @AuraEnabled
    public Integer casesAssignedToMyTeams = 0;
    @AuraEnabled
    public Integer tasksAssignedToMyTeams = 0;
    /** Open Tasks assigned to the user that are a Branch or Home Office pit stop. */
    @AuraEnabled
    public Integer pitStopTasksAssignedToMe = 0;
  }
}