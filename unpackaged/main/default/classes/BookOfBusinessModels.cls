/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-22
 *
 * DTOs for the Book of Business record tab.
 */
public with sharing class BookOfBusinessModels {
  public class BookOfBusinessResult {
    @AuraEnabled
    public String title { get; set; }
    @AuraEnabled
    public String subtitle { get; set; }
    @AuraEnabled
    public SummaryMetrics summary { get; set; }
    @AuraEnabled
    public List<KpiMetric> kpis { get; set; }
    @AuraEnabled
    public List<AccountRow> accounts { get; set; }

    public BookOfBusinessResult() {
      this.kpis = new List<KpiMetric>();
      this.accounts = new List<AccountRow>();
    }
  }

  public class SummaryMetrics {
    @AuraEnabled
    public Integer accountCount { get; set; }
    @AuraEnabled
    public String totalAumLabel { get; set; }
    @AuraEnabled
    public Decimal totalAumValue { get; set; }

    public SummaryMetrics(
      Integer accountCount,
      String totalAumLabel,
      Decimal totalAumValue
    ) {
      this.accountCount = accountCount;
      this.totalAumLabel = totalAumLabel;
      this.totalAumValue = totalAumValue;
    }

    public SummaryMetrics() {
      this(0, '', 0);
    }
  }

  public class KpiMetric {
    @AuraEnabled
    public String id { get; set; }
    @AuraEnabled
    public String label { get; set; }
    @AuraEnabled
    public String value { get; set; }
    @AuraEnabled
    public String subtext { get; set; }
    @AuraEnabled
    public String trendLabel { get; set; }
    @AuraEnabled
    public String trendDirection { get; set; }

    public KpiMetric(
      String id,
      String label,
      String value,
      String subtext,
      String trendLabel,
      String trendDirection
    ) {
      this.id = id;
      this.label = label;
      this.value = value;
      this.subtext = subtext;
      this.trendLabel = trendLabel;
      this.trendDirection = trendDirection;
    }

    public KpiMetric() {
    }
  }

  public class AccountRow {
    @AuraEnabled
    public String id { get; set; }
    @AuraEnabled
    public String accountId { get; set; }
    @AuraEnabled
    public String accountName { get; set; }
    @AuraEnabled
    public String role { get; set; }
    @AuraEnabled
    public String recordType { get; set; }
    @AuraEnabled
    public String association { get; set; }
    @AuraEnabled
    public Decimal totalAum { get; set; }
    @AuraEnabled
    public String totalAumLabel { get; set; }
    @AuraEnabled
    public Decimal revenueT12 { get; set; }
    @AuraEnabled
    public String revenueT12Label { get; set; }
    @AuraEnabled
    public String state { get; set; }
    @AuraEnabled
    public String wealthSegment { get; set; }
    @AuraEnabled
    public Map<String, Object> extraFields { get; set; }

    public AccountRow(
      String id,
      String accountId,
      String accountName,
      String role,
      String recordType,
      String association,
      Decimal totalAum,
      String totalAumLabel,
      Decimal revenueT12,
      String revenueT12Label,
      String state
    ) {
      this.id = id;
      this.accountId = accountId;
      this.accountName = accountName;
      this.role = role;
      this.recordType = recordType;
      this.association = association;
      this.totalAum = totalAum;
      this.totalAumLabel = totalAumLabel;
      this.revenueT12 = revenueT12;
      this.revenueT12Label = revenueT12Label;
      this.state = state;
      this.extraFields = new Map<String, Object>();
    }

    public AccountRow() {
      this.extraFields = new Map<String, Object>();
    }
  }
}