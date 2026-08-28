/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-12
 *
 * Open case counts grouped by Milestone__c for arcCaseMetrics.
 *
 * Milestone__c, NOT the standard MilestoneStatus. MilestoneStatus is derived
 * from Entitlement Management's CaseMilestone records and this org creates
 * none at all, so it is blank on every open Case and grouping by it dropped
 * all of them into 'Not set' — a donut captioned "By milestone" that never
 * showed a milestone. The milestone this org actually tracks is written to
 * Case.Milestone__c by Case_TriggerHandler.populateMilestoneOnCase, which sets
 * it to the last completed milestone task in MILESTONE_RANK order below.
 * arcCaseMetrics was already built for those values — resolveSegmentColor
 * there keys off 'ho-submission', 'branch-goal' and 'ho-goal' — so the query
 * was the only thing pointing at the wrong field.
 */
public with sharing class ArcCaseMetricsRepository {
  private static final String UNASSIGNED_LABEL = 'Not set';

  /**
   * Milestone progression, so the donut steps through the stages in the order
   * cases actually move through them instead of reshuffling whenever a count
   * changes. Mirrors the order Case_TriggerHandler.populateMilestoneOnCase
   * walks its milestone fields. An unrecognised value sorts after these but
   * ahead of 'Not set', which is always last: it is the absence of a
   * milestone, not a stage of one.
   */
  private static final Map<String, Integer> MILESTONE_RANK = new Map<String, Integer>{
    'HO Submission' => 0,
    'HO Approval' => 1,
    'Branch Goal' => 2,
    'HO Goal' => 3
  };
  private static final Integer RANK_UNKNOWN = 8;
  private static final Integer RANK_UNASSIGNED = 9;

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
    ArcRelatedTableScope.Value scope
  ) {
    ArcCaseMetricsModels.MetricsResult metrics = new ArcCaseMetricsModels.MetricsResult();
    List<Case> caseRecords = selectCases(scope);

    if (caseRecords.isEmpty()) {
      return metrics;
    }

    Map<String, Integer> countByMilestone = new Map<String, Integer>();
    for (Case caseRecord : caseRecords) {
      String milestoneLabel = resolveMilestoneLabel(caseRecord.Milestone__c);
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

  private List<Case> selectCases(ArcRelatedTableScope.Value scope) {
    Id currentUserId = UserInfo.getUserId();

    if (scope == ArcRelatedTableScope.Value.MINE) {
      return [
        SELECT Id, Milestone__c
        FROM Case
        WHERE OwnerId = :currentUserId AND IsClosed = FALSE
        WITH SECURITY_ENFORCED
      ];
    }

    FinancialAdvisorTeamAccessService.TeamAccessContext teamAccess = teamAccessService.getCurrentUserTeamAccess();
    if (teamAccess.teamIds.isEmpty()) {
      return new List<Case>();
    }

    Set<Id> teamIds = teamAccess.teamIds;
    return [
      SELECT Id, Milestone__c
      FROM Case
      WHERE Financial_Advisor_Team__c IN :teamIds AND IsClosed = FALSE
      WITH SECURITY_ENFORCED
    ];
  }

  private static String resolveMilestoneLabel(String milestone) {
    if (String.isBlank(milestone)) {
      return UNASSIGNED_LABEL;
    }

    return milestone.trim();
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

    /**
     * Milestone order first, then count descending, then label as a stable
     * tie-break.
     */
    public Integer compareTo(Object other) {
      MilestoneAggregate otherAggregate = (MilestoneAggregate) other;

      Integer thisRank = rankFor(this.label);
      Integer otherRank = rankFor(otherAggregate.label);
      if (thisRank != otherRank) {
        return thisRank < otherRank ? -1 : 1;
      }

      if (otherAggregate.count > this.count) {
        return 1;
      }
      if (otherAggregate.count < this.count) {
        return -1;
      }

      return this.label.compareTo(otherAggregate.label);
    }

    private Integer rankFor(String label) {
      if (UNASSIGNED_LABEL.equals(label)) {
        return RANK_UNASSIGNED;
      }

      return MILESTONE_RANK.containsKey(label)
        ? MILESTONE_RANK.get(label)
        : RANK_UNKNOWN;
    }
  }
}