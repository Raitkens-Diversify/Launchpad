/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-11
 *
 * Aura-enabled facade for arcTaskMetrics.
 */
public with sharing class ArcTaskMetricsController {
  private static final ArcTaskMetricsRepository REPOSITORY = new ArcTaskMetricsRepository();

  @AuraEnabled(cacheable=true)
  public static ArcTaskMetricsModels.MetricsResult getTaskMetrics(String scope) {
    ARCConstants.RelatedTableScope resolvedScope = ARCUtil.relatedTableScopeFromValue(
      scope
    );
    return REPOSITORY.selectMetrics(resolvedScope);
  }
}