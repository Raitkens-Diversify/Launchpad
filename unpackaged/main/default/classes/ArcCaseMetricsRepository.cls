/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-12
 *
 * Open case counts grouped by MilestoneStatus for arcCaseMetrics.
 */
public with sharing class ArcCaseMetricsRepository {
  private static final String UNASSIGNED_LABEL = 'Not set';

  private final FinancialAdvisorTeamAccessService teamAccessService;

  public ArcCaseMetricsRepository() {
    this(new FinancialAdvisorTeamAccessService());
  }

  public ArcCaseMetricsRepository(
    FinancialAdvisorTeamAccessService teamAccessService
  ) {
    this.teamAccessService = teamAccessService;
  }

  public ArcCaseMetricsModels.MetricsResult selectMetrics(
    ARCConstants.RelatedTableScope scope
  ) {
    ArcCaseMetricsModels.MetricsResult metrics = new ArcCaseMetricsModels.MetricsResult();
    List<Case> caseRecords = selectCases(scope);

    if (caseRecords.isEmpty()) {
      return metrics;
    }

    Map<String, Integer> countByMilestone = new Map<String, Integer>();
    for (Case caseRecord : caseRecords) {
      String milestoneLabel = resolveMilestoneLabel(caseRecord.MilestoneStatus);
      Integer currentCount = countByMilestone.containsKey(milestoneLabel)
        ? countByMilestone.get(milestoneLabel)
        : 0;
      countByMilestone.put(milestoneLabel, currentCount + 1);
    }

    List<MilestoneAggregate> aggregates = new List<MilestoneAggregate>();
    for (String milestoneLabel : countByMilestone.keySet()) {
      aggregates.add(
        new MilestoneAggregate(
          milestoneLabel,
          countByMilestone.get(milestoneLabel)
        )
      );
    }
    aggregates.sort();

    for (MilestoneAggregate aggregate : aggregates) {
      ArcCaseMetricsModels.MilestoneSegment segment = new ArcCaseMetricsModels.MilestoneSegment();
      segment.key = normalizeSegmentKey(aggregate.label);
      segment.label = aggregate.label;
      segment.count = aggregate.count;
      metrics.segments.add(segment);
      metrics.totalCount += aggregate.count;
    }

    return metrics;
  }

  private List<Case> selectCases(ARCConstants.RelatedTableScope scope) {
    Id currentUserId = UserInfo.getUserId();

    if (scope == ARCConstants.RelatedTableScope.MINE) {
      return selectOwnedOpenCases(currentUserId);
    }

    FinancialAdvisorTeamAccessService.TeamAccessContext teamAccess = teamAccessService.getCurrentUserTeamAccess();
    Set<Id> teamIds = teamAccess.teamIds;

    if (teamIds.isEmpty()) {
      return selectOwnedOpenCases(currentUserId);
    }

    return [
      SELECT Id, MilestoneStatus
      FROM Case
      WHERE
        IsClosed = FALSE
        AND (OwnerId = :currentUserId OR Financial_Advisor_Team__c IN :teamIds)
      WITH SECURITY_ENFORCED
    ];
  }

  private List<Case> selectOwnedOpenCases(Id ownerId) {
    return [
      SELECT Id, MilestoneStatus
      FROM Case
      WHERE OwnerId = :ownerId AND IsClosed = FALSE
      WITH SECURITY_ENFORCED
    ];
  }

  private static String resolveMilestoneLabel(String milestoneStatus) {
    if (String.isBlank(milestoneStatus)) {
      return UNASSIGNED_LABEL;
    }

    return milestoneStatus.trim();
  }

  private static String normalizeSegmentKey(String label) {
    return label == null
      ? 'not-set'
      : label.trim().toLowerCase().replaceAll('[^a-z0-9]+', '-');
  }

  private class MilestoneAggregate implements Comparable {
    public String label { get; private set; }
    public Integer count { get; private set; }

    public MilestoneAggregate(String label, Integer count) {
      this.label = label;
      this.count = count == null ? 0 : count;
    }

    public Integer compareTo(Object other) {
      MilestoneAggregate otherAggregate = (MilestoneAggregate) other;
      if (otherAggregate.count > this.count) {
        return 1;
      }
      if (otherAggregate.count < this.count) {
        return -1;
      }

      return this.label.compareTo(otherAggregate.label);
    }
  }
}