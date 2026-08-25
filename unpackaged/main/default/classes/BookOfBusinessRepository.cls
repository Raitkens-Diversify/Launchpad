/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-14
 *
 * SOQL and mock enrichment for Book of Business account rows.
 */
public with sharing class BookOfBusinessRepository {
  private static final Map<String, String> MOCK_FIELD_ALIASES = new Map<String, String>{
    'Name' => 'accountName',
    'BillingState' => 'state'
  };

  public BookOfBusinessModels.BookOfBusinessResult selectBookOfBusinessData(
    Id recordId,
    List<String> additionalFieldApis
  ) {
    BookOfBusinessModels.BookOfBusinessResult result = buildMockResult();

    if (additionalFieldApis == null || additionalFieldApis.isEmpty()) {
      return result;
    }

    for (BookOfBusinessModels.AccountRow row : result.accounts) {
      row.extraFields = buildExtraFields(row, additionalFieldApis);
    }

    return result;
  }

  private static Map<String, Object> buildExtraFields(
    BookOfBusinessModels.AccountRow row,
    List<String> additionalFieldApis
  ) {
    Map<String, Object> extraFields = new Map<String, Object>();

    for (String fieldApi : additionalFieldApis) {
      if (String.isBlank(fieldApi)) {
        continue;
      }

      extraFields.put(fieldApi, resolveMockFieldValue(row, fieldApi));
    }

    return extraFields;
  }

  private static Object resolveMockFieldValue(
    BookOfBusinessModels.AccountRow row,
    String fieldApi
  ) {
    if (MOCK_FIELD_ALIASES.containsKey(fieldApi)) {
      String aliasField = MOCK_FIELD_ALIASES.get(fieldApi);

      if (aliasField == 'accountName') {
        return row.accountName;
      }

      if (aliasField == 'state') {
        return row.state;
      }
    }

    if (fieldApi == 'Type') {
      return row.recordType;
    }

    if (fieldApi == 'Description') {
      return row.role;
    }

    return '';
  }

  private static BookOfBusinessModels.BookOfBusinessResult buildMockResult() {
    BookOfBusinessModels.BookOfBusinessResult result = new BookOfBusinessModels.BookOfBusinessResult();
    result.title = 'Book of Business';
    result.subtitle = 'Related client accounts for Harrison Family Household';
    result.summary = new BookOfBusinessModels.SummaryMetrics(
      4,
      '$19.99M',
      19990000
    );

    result.kpis.add(
      new BookOfBusinessModels.KpiMetric(
        'total-aum',
        'TOTAL AUM',
        '$19.99M',
        '4 accounts',
        '+8.4% YTD',
        'positive'
      )
    );
    result.kpis.add(
      new BookOfBusinessModels.KpiMetric(
        'revenue-t12',
        'REVENUE T12',
        '$292K',
        'vs $271K prior year',
        '+7.7% YoY',
        'positive'
      )
    );
    result.kpis.add(
      new BookOfBusinessModels.KpiMetric(
        'client-since',
        'CLIENT SINCE',
        '2009',
        '15-year relationship',
        null,
        null
      )
    );
    result.kpis.add(
      new BookOfBusinessModels.KpiMetric(
        'next-review',
        'NEXT REVIEW',
        'Aug 14',
        '2025 · 43 days away',
        null,
        null
      )
    );

    result.accounts.add(
      new BookOfBusinessModels.AccountRow(
        'row-1',
        null,
        'Harrison Family Trust',
        'Trustee',
        'Trust',
        'Member',
        8200000,
        '$8,200,000',
        124000,
        '$124,000',
        'CA'
      )
    );
    result.accounts.add(
      new BookOfBusinessModels.AccountRow(
        'row-2',
        null,
        'John Harrison',
        'Primary',
        'Individual',
        'Primary',
        6100000,
        '$6,100,000',
        89000,
        '$89,000',
        'CA'
      )
    );
    result.accounts.add(
      new BookOfBusinessModels.AccountRow(
        'row-3',
        null,
        'Sarah Harrison',
        'Spouse',
        'Individual',
        'Member',
        3400000,
        '$3,400,000',
        48000,
        '$48,000',
        'CA'
      )
    );
    result.accounts.add(
      new BookOfBusinessModels.AccountRow(
        'row-4',
        null,
        'Harrison LLC',
        'Authorized',
        'Business',
        'Member',
        2290000,
        '$2,290,000',
        31000,
        '$31,000',
        'NV'
      )
    );

    result.accounts.get(0).wealthSegment = 'Ultra HNW';
    result.accounts.get(1).wealthSegment = 'HNW';
    result.accounts.get(2).wealthSegment = 'Affluent';
    result.accounts.get(3).wealthSegment = 'Mass Affluent';

    return result;
  }
}