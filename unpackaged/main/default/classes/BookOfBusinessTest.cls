/**
 * Tests for BookOfBusinessController, BookOfBusinessRepository and BookOfBusinessModels.
 *
 * The repository serves a fixed mock book (v1) and enriches each row with the requested
 * additional field APIs, so the tests pin the mock shape and the alias resolution rules.
 */
@IsTest
private class BookOfBusinessTest {
  private static final Decimal EXPECTED_TOTAL_AUM = 19990000;

  @IsTest
  static void controller_returnsMockBookWithoutExtraFields() {
    Test.startTest();
    BookOfBusinessModels.BookOfBusinessResult result = BookOfBusinessController.getBookOfBusinessData(
      null,
      null
    );
    Test.stopTest();

    Assert.areEqual('Book of Business', result.title);
    Assert.isTrue(result.subtitle.contains('Harrison'), result.subtitle);

    Assert.areEqual(4, result.summary.accountCount);
    Assert.areEqual('$19.99M', result.summary.totalAumLabel);
    Assert.areEqual(EXPECTED_TOTAL_AUM, result.summary.totalAumValue);

    Assert.areEqual(4, result.kpis.size());
    Assert.areEqual('total-aum', result.kpis[0].id);
    Assert.areEqual('TOTAL AUM', result.kpis[0].label);
    Assert.areEqual('$19.99M', result.kpis[0].value);
    Assert.areEqual('4 accounts', result.kpis[0].subtext);
    Assert.areEqual('+8.4% YTD', result.kpis[0].trendLabel);
    Assert.areEqual('positive', result.kpis[0].trendDirection);
    Assert.areEqual('revenue-t12', result.kpis[1].id);
    Assert.areEqual('client-since', result.kpis[2].id);
    Assert.isNull(result.kpis[2].trendLabel, 'client-since has no trend');
    Assert.isNull(result.kpis[2].trendDirection);
    Assert.areEqual('next-review', result.kpis[3].id);

    Assert.areEqual(4, result.accounts.size());
    BookOfBusinessModels.AccountRow first = result.accounts[0];
    Assert.areEqual('row-1', first.id);
    Assert.isNull(first.accountId, 'mock rows are not linked to Account records');
    Assert.areEqual('Harrison Family Trust', first.accountName);
    Assert.areEqual('Trustee', first.role);
    Assert.areEqual('Trust', first.recordType);
    Assert.areEqual('Member', first.association);
    Assert.areEqual(8200000, first.totalAum);
    Assert.areEqual('$8,200,000', first.totalAumLabel);
    Assert.areEqual(124000, first.revenueT12);
    Assert.areEqual('$124,000', first.revenueT12Label);
    Assert.areEqual('CA', first.state);
    Assert.areEqual('Ultra HNW', first.wealthSegment);
    Assert.areEqual('HNW', result.accounts[1].wealthSegment);
    Assert.areEqual('Affluent', result.accounts[2].wealthSegment);
    Assert.areEqual('Mass Affluent', result.accounts[3].wealthSegment);
    Assert.areEqual('NV', result.accounts[3].state);

    Decimal totalAum = 0;
    for (BookOfBusinessModels.AccountRow row : result.accounts) {
      Assert.isNotNull(row.extraFields, 'extraFields is always initialized');
      Assert.isTrue(row.extraFields.isEmpty(), 'no additional fields requested');
      Assert.isTrue(String.isNotBlank(row.wealthSegment), 'every row has a wealth segment');
      totalAum += row.totalAum;
    }
    Assert.areEqual(EXPECTED_TOTAL_AUM, totalAum, 'row AUM adds up to the summary total');
  }

  @IsTest
  static void controller_ignoresEmptyAdditionalFieldList() {
    BookOfBusinessModels.BookOfBusinessResult result = BookOfBusinessController.getBookOfBusinessData(
      UserInfo.getUserId(),
      new List<String>()
    );

    Assert.areEqual(4, result.accounts.size());
    for (BookOfBusinessModels.AccountRow row : result.accounts) {
      Assert.isTrue(row.extraFields.isEmpty(), 'empty field list adds nothing');
    }
  }

  @IsTest
  static void controller_passesAdditionalFieldsThrough() {
    BookOfBusinessModels.BookOfBusinessResult result = BookOfBusinessController.getBookOfBusinessData(
      null,
      new List<String>{ 'Name' }
    );

    for (BookOfBusinessModels.AccountRow row : result.accounts) {
      Assert.areEqual(1, row.extraFields.size());
      Assert.areEqual(row.accountName, row.extraFields.get('Name'));
    }
  }

  @IsTest
  static void repository_resolvesAdditionalFieldsFromMockRowValues() {
    List<String> fieldApis = new List<String>{
      'Name',
      'BillingState',
      'Type',
      'Description',
      'Industry',
      '',
      null,
      '  '
    };

    BookOfBusinessModels.BookOfBusinessResult result = new BookOfBusinessRepository()
      .selectBookOfBusinessData(null, fieldApis);

    Assert.areEqual(4, result.accounts.size());
    for (BookOfBusinessModels.AccountRow row : result.accounts) {
      Assert.areEqual(5, row.extraFields.size(), 'blank field APIs are skipped: ' + row.extraFields);
      Assert.areEqual(row.accountName, row.extraFields.get('Name'), 'Name aliases accountName');
      Assert.areEqual(row.state, row.extraFields.get('BillingState'), 'BillingState aliases state');
      Assert.areEqual(row.recordType, row.extraFields.get('Type'), 'Type maps to recordType');
      Assert.areEqual(row.role, row.extraFields.get('Description'), 'Description maps to role');
      Assert.areEqual('', row.extraFields.get('Industry'), 'unknown fields resolve to an empty string');
      Assert.isFalse(row.extraFields.containsKey(''), 'empty key skipped');
      Assert.isFalse(row.extraFields.containsKey(null), 'null key skipped');
    }
    Assert.areEqual('Harrison LLC', result.accounts[3].extraFields.get('Name'));
    Assert.areEqual('NV', result.accounts[3].extraFields.get('BillingState'));
    Assert.areEqual('Business', result.accounts[3].extraFields.get('Type'));
    Assert.areEqual('Authorized', result.accounts[3].extraFields.get('Description'));
  }

  @IsTest
  static void repository_returnsFreshResultPerCall() {
    BookOfBusinessRepository repository = new BookOfBusinessRepository();

    BookOfBusinessModels.BookOfBusinessResult enriched = repository.selectBookOfBusinessData(
      null,
      new List<String>{ 'Type' }
    );
    BookOfBusinessModels.BookOfBusinessResult plain = repository.selectBookOfBusinessData(null, null);

    Assert.areEqual(1, enriched.accounts[0].extraFields.size());
    Assert.isTrue(plain.accounts[0].extraFields.isEmpty(), 'a later call is not polluted by an earlier enrichment');
  }

  @IsTest
  static void models_bookOfBusinessResultInitializesCollections() {
    BookOfBusinessModels.BookOfBusinessResult result = new BookOfBusinessModels.BookOfBusinessResult();

    Assert.isNull(result.title);
    Assert.isNull(result.subtitle);
    Assert.isNull(result.summary);
    Assert.isNotNull(result.kpis);
    Assert.isTrue(result.kpis.isEmpty());
    Assert.isNotNull(result.accounts);
    Assert.isTrue(result.accounts.isEmpty());

    result.title = 'Title';
    result.subtitle = 'Subtitle';
    result.summary = new BookOfBusinessModels.SummaryMetrics(1, '$1', 1);
    result.kpis.add(new BookOfBusinessModels.KpiMetric());
    result.accounts.add(new BookOfBusinessModels.AccountRow());

    Assert.areEqual('Title', result.title);
    Assert.areEqual('Subtitle', result.subtitle);
    Assert.areEqual(1, result.summary.accountCount);
    Assert.areEqual(1, result.kpis.size());
    Assert.areEqual(1, result.accounts.size());
  }

  @IsTest
  static void models_summaryMetricsConstructors() {
    BookOfBusinessModels.SummaryMetrics empty = new BookOfBusinessModels.SummaryMetrics();
    Assert.areEqual(0, empty.accountCount);
    Assert.areEqual('', empty.totalAumLabel);
    Assert.areEqual(0, empty.totalAumValue);

    BookOfBusinessModels.SummaryMetrics filled = new BookOfBusinessModels.SummaryMetrics(
      3,
      '$3M',
      3000000
    );
    Assert.areEqual(3, filled.accountCount);
    Assert.areEqual('$3M', filled.totalAumLabel);
    Assert.areEqual(3000000, filled.totalAumValue);

    filled.accountCount = 5;
    filled.totalAumLabel = '$5M';
    filled.totalAumValue = 5000000.5;
    Assert.areEqual(5, filled.accountCount);
    Assert.areEqual('$5M', filled.totalAumLabel);
    Assert.areEqual(5000000.5, filled.totalAumValue);
  }

  @IsTest
  static void models_kpiMetricConstructors() {
    BookOfBusinessModels.KpiMetric empty = new BookOfBusinessModels.KpiMetric();
    Assert.isNull(empty.id);
    Assert.isNull(empty.label);
    Assert.isNull(empty.value);
    Assert.isNull(empty.subtext);
    Assert.isNull(empty.trendLabel);
    Assert.isNull(empty.trendDirection);

    BookOfBusinessModels.KpiMetric filled = new BookOfBusinessModels.KpiMetric(
      'kpi-1',
      'LABEL',
      '42',
      'sub',
      '+1%',
      'positive'
    );
    Assert.areEqual('kpi-1', filled.id);
    Assert.areEqual('LABEL', filled.label);
    Assert.areEqual('42', filled.value);
    Assert.areEqual('sub', filled.subtext);
    Assert.areEqual('+1%', filled.trendLabel);
    Assert.areEqual('positive', filled.trendDirection);

    empty.id = 'kpi-2';
    empty.label = 'L';
    empty.value = 'V';
    empty.subtext = 'S';
    empty.trendLabel = '-2%';
    empty.trendDirection = 'negative';
    Assert.areEqual('kpi-2', empty.id);
    Assert.areEqual('L', empty.label);
    Assert.areEqual('V', empty.value);
    Assert.areEqual('S', empty.subtext);
    Assert.areEqual('-2%', empty.trendLabel);
    Assert.areEqual('negative', empty.trendDirection);
  }

  @IsTest
  static void models_accountRowConstructors() {
    BookOfBusinessModels.AccountRow empty = new BookOfBusinessModels.AccountRow();
    Assert.isNull(empty.id);
    Assert.isNull(empty.accountId);
    Assert.isNull(empty.accountName);
    Assert.isNull(empty.role);
    Assert.isNull(empty.recordType);
    Assert.isNull(empty.association);
    Assert.isNull(empty.totalAum);
    Assert.isNull(empty.totalAumLabel);
    Assert.isNull(empty.revenueT12);
    Assert.isNull(empty.revenueT12Label);
    Assert.isNull(empty.state);
    Assert.isNull(empty.wealthSegment);
    Assert.isNotNull(empty.extraFields, 'no-arg constructor initializes extraFields');
    Assert.isTrue(empty.extraFields.isEmpty());

    String accountId = UserInfo.getUserId();
    BookOfBusinessModels.AccountRow filled = new BookOfBusinessModels.AccountRow(
      'row-9',
      accountId,
      'ACME Trust',
      'Trustee',
      'Trust',
      'Member',
      1000,
      '$1,000',
      10,
      '$10',
      'TX'
    );
    Assert.areEqual('row-9', filled.id);
    Assert.areEqual(accountId, filled.accountId);
    Assert.areEqual('ACME Trust', filled.accountName);
    Assert.areEqual('Trustee', filled.role);
    Assert.areEqual('Trust', filled.recordType);
    Assert.areEqual('Member', filled.association);
    Assert.areEqual(1000, filled.totalAum);
    Assert.areEqual('$1,000', filled.totalAumLabel);
    Assert.areEqual(10, filled.revenueT12);
    Assert.areEqual('$10', filled.revenueT12Label);
    Assert.areEqual('TX', filled.state);
    Assert.isNull(filled.wealthSegment, 'wealth segment is assigned separately');
    Assert.isNotNull(filled.extraFields);
    Assert.isTrue(filled.extraFields.isEmpty());

    filled.wealthSegment = 'HNW';
    filled.extraFields.put('Industry', 'Finance');
    empty.id = 'row-0';
    empty.accountId = accountId;
    empty.accountName = 'N';
    empty.role = 'R';
    empty.recordType = 'T';
    empty.association = 'A';
    empty.totalAum = 1;
    empty.totalAumLabel = '$1';
    empty.revenueT12 = 2;
    empty.revenueT12Label = '$2';
    empty.state = 'WA';
    empty.wealthSegment = 'Affluent';
    empty.extraFields = new Map<String, Object>{ 'Name' => 'N' };

    Assert.areEqual('HNW', filled.wealthSegment);
    Assert.areEqual('Finance', filled.extraFields.get('Industry'));
    Assert.areEqual('row-0', empty.id);
    Assert.areEqual(accountId, empty.accountId);
    Assert.areEqual('N', empty.accountName);
    Assert.areEqual('R', empty.role);
    Assert.areEqual('T', empty.recordType);
    Assert.areEqual('A', empty.association);
    Assert.areEqual(1, empty.totalAum);
    Assert.areEqual('$1', empty.totalAumLabel);
    Assert.areEqual(2, empty.revenueT12);
    Assert.areEqual('$2', empty.revenueT12Label);
    Assert.areEqual('WA', empty.state);
    Assert.areEqual('Affluent', empty.wealthSegment);
    Assert.areEqual('N', empty.extraFields.get('Name'));
  }
}