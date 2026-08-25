/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-11
 *
 * Envelope__c queries for arcRelatedTable.
 */
public with sharing class ArcRelatedEnvelopeTableRepository {
  private static final Integer ROW_LIMIT = 500;

  private final FinancialAdvisorTeamAccessService teamAccessService;

  public ArcRelatedEnvelopeTableRepository() {
    this(new FinancialAdvisorTeamAccessService());
  }

  public ArcRelatedEnvelopeTableRepository(
    FinancialAdvisorTeamAccessService teamAccessService
  ) {
    this.teamAccessService = teamAccessService;
  }

  public ArcRelatedTableModels.TableData selectRows(
    ArcRelatedTableScope.Value scope
  ) {
    ArcRelatedTableModels.TableData data = new ArcRelatedTableModels.TableData();
    Id currentUserId = UserInfo.getUserId();
    FinancialAdvisorTeamAccessService.TeamAccessContext teamAccess = teamAccessService.getCurrentUserTeamAccess();

    List<Envelope__c> records;
    if (scope == ArcRelatedTableScope.Value.MINE) {
      records = [
        SELECT
          Id,
          Name,
          Status__c,
          Household_Name__c,
          Financial_Advisor_Team__c,
          Financial_Advisor_Team__r.Name,
          LastModifiedDate,
          OwnerId,
          Owner.Name
        FROM Envelope__c
        WHERE OwnerId = :currentUserId
        WITH SECURITY_ENFORCED
        ORDER BY LastModifiedDate DESC
        LIMIT :ROW_LIMIT
      ];
    } else if (teamAccess.teamIds.isEmpty()) {
      records = new List<Envelope__c>();
    } else {
      records = [
        SELECT
          Id,
          Name,
          Status__c,
          Household_Name__c,
          Financial_Advisor_Team__c,
          Financial_Advisor_Team__r.Name,
          LastModifiedDate,
          OwnerId,
          Owner.Name
        FROM Envelope__c
        WHERE Financial_Advisor_Team__c IN :teamAccess.teamIds
        WITH SECURITY_ENFORCED
        ORDER BY LastModifiedDate DESC
        LIMIT :ROW_LIMIT
      ];
    }

    for (Envelope__c record : records) {
      data.rows.add(mapEnvelopeRow(record));
    }

    data.totalCount = data.rows.size();
    return data;
  }

  private static ArcRelatedTableModels.TableRow mapEnvelopeRow(
    Envelope__c record
  ) {
    ArcRelatedTableModels.TableRow row = new ArcRelatedTableModels.TableRow();
    row.id = String.valueOf(record.Id);
    row.name = record.Name;
    row.household = record.Household_Name__c;
    row.advisorTeam = record.Financial_Advisor_Team__r?.Name;
    row.status = record.Status__c;
    row.ownerName = record.Owner?.Name;
    row.lastModifiedRaw = record.LastModifiedDate;
    row.lastModified = formatDateTime(record.LastModifiedDate);
    return row;
  }

  private static String formatDateTime(Datetime value) {
    if (value == null) {
      return '';
    }

    return value.format('MMM d, yyyy HH:mm');
  }
}