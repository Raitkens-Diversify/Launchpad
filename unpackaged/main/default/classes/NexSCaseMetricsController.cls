/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-12
 *
 * Aura-enabled facade for nexSCaseMetrics.
 */
public with sharing class NexSCaseMetricsController {
  private static final NexSCaseMetricsRepository REPOSITORY = new NexSCaseMetricsRepository();

  @AuraEnabled(cacheable=true)
  public static NexSCaseMetricsModels.MetricsResult getCaseMetrics(String scope) {
    NexsRelatedTableScope.Value resolvedScope = NexsRelatedTableScope.fromValue(
      scope
    );
    return REPOSITORY.selectMetrics(resolvedScope);
  }
}