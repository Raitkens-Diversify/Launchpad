/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-11
 *
 * Aura-enabled facade for arcRelatedTable.
 */
public with sharing class ArcRelatedTableController {
  private static final ArcRelatedEnvelopeTableRepository ENVELOPE_REPOSITORY = new ArcRelatedEnvelopeTableRepository();
  private static final ArcRelatedWorkTableRepository WORK_REPOSITORY = new ArcRelatedWorkTableRepository();

  @AuraEnabled(cacheable=true)
  public static ArcRelatedTableModels.TableData getTableData(
    String objectType,
    String scope
  ) {
    ArcRelatedTableObjectType.Value resolvedObjectType = ArcRelatedTableObjectType.fromValue(
      objectType
    );
    ArcRelatedTableScope.Value resolvedScope = ArcRelatedTableScope.fromValue(scope);

    if (resolvedObjectType == ArcRelatedTableObjectType.Value.WORK) {
      return WORK_REPOSITORY.selectRows(resolvedScope);
    }

    return ENVELOPE_REPOSITORY.selectRows(resolvedScope);
  }
}