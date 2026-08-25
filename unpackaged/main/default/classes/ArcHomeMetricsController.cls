/**
 * Aura-enabled facade for arcHomeMetrics (the Home dashboard's 5 KPI tiles).
 */
public with sharing class ArcHomeMetricsController {
  private static final ArcHomeMetricsRepository REPOSITORY = new ArcHomeMetricsRepository();

  @AuraEnabled(cacheable=true)
  public static ArcHomeMetricsModels.MetricsResult getHomeMetrics() {
    return REPOSITORY.selectMetrics();
  }
}