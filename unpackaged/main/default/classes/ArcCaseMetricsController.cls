/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-12
 *
 * Aura-enabled facade for arcCaseMetrics.
 */
public with sharing class ArcCaseMetricsController {
  private static final ArcCaseMetricsRepository REPOSITORY = new ArcCaseMetricsRepository();

  @AuraEnabled(cacheable=true)
  public static ArcCaseMetricsModels.MetricsResult getCaseMetrics(String scope) {
    ARCConstants.RelatedTableScope resolvedScope = ARCUtil.relatedTableScopeFromValue(
      scope
    );
    return REPOSITORY.selectMetrics(resolvedScope);
  }
}