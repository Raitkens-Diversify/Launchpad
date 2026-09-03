@IsTest
private class ArcAccountInvestmentsControllerTest {
  @IsTest
  static void getInvestmentsAndServicesReturnsFinancialAccountsRolledUpToHousehold() {
    Account household = new Account(Name = 'Investments Household', Type = 'Prospect');
    insert household;

    Financial_Account__c isa = new Financial_Account__c(
      Name = 'Rolled Up ISA',
      Household__c = household.Id
    );
    insert isa;

    Test.startTest();
    List<ArcAccountInvestmentsController.InvestmentRow> rows = ArcAccountInvestmentsController.getInvestmentsAndServices(
      household.Id
    );
    Test.stopTest();

    Assert.areEqual(1, rows.size());
    Assert.areEqual(isa.Id, rows[0].id);
    Assert.areEqual('Account', rows[0].typeLabel);
    Assert.areEqual('Financial_Account__c', rows[0].objectApiName);
  }

  @IsTest
  static void getInvestmentsAndServicesReturnsFinancialAccountsOwnedDirectly() {
    Account owner = new Account(Name = 'Direct Owner', Type = 'Prospect');
    insert owner;

    Financial_Account__c isa = new Financial_Account__c(
      Name = 'Directly Owned ISA',
      Primary_Owner__c = owner.Id
    );
    insert isa;

    Test.startTest();
    List<ArcAccountInvestmentsController.InvestmentRow> rows = ArcAccountInvestmentsController.getInvestmentsAndServices(
      owner.Id
    );
    Test.stopTest();

    Assert.areEqual(1, rows.size());
    Assert.areEqual(isa.Id, rows[0].id);
  }

  @IsTest
  static void getInvestmentsAndServicesReturnsServices() {
    Account household = new Account(Name = 'Services Household', Type = 'Prospect');
    insert household;

    Service__c service = new Service__c(
      Name = 'Financial Planning',
      Household__c = household.Id
    );
    insert service;

    Test.startTest();
    List<ArcAccountInvestmentsController.InvestmentRow> rows = ArcAccountInvestmentsController.getInvestmentsAndServices(
      household.Id
    );
    Test.stopTest();

    Assert.areEqual(1, rows.size());
    Assert.areEqual(service.Id, rows[0].id);
    Assert.areEqual('Service', rows[0].typeLabel);
    Assert.areEqual('Service__c', rows[0].objectApiName);
  }

  @IsTest
  static void getInvestmentsAndServicesReturnsApprovedProducts() {
    Account account = new Account(Name = 'Products Account', Type = 'Prospect');
    insert account;

    Product__c product = new Product__c(Name = 'Approved Fund', Account__c = account.Id);
    insert product;

    Test.startTest();
    List<ArcAccountInvestmentsController.InvestmentRow> rows = ArcAccountInvestmentsController.getInvestmentsAndServices(
      account.Id
    );
    Test.stopTest();

    Assert.areEqual(1, rows.size());
    Assert.areEqual(product.Id, rows[0].id);
    Assert.areEqual('Approved Product', rows[0].typeLabel);
    Assert.areEqual('Product__c', rows[0].objectApiName);
  }

  @IsTest
  static void getInvestmentsAndServicesSortsAllTypesByName() {
    Account account = new Account(Name = 'Sorted Account', Type = 'Prospect');
    insert account;

    insert new Financial_Account__c(Name = 'Zebra ISA', Primary_Owner__c = account.Id);
    insert new Service__c(Name = 'Middle Service', Primary_Owner__c = account.Id);
    insert new Product__c(Name = 'Apple Product', Account__c = account.Id);

    Test.startTest();
    List<ArcAccountInvestmentsController.InvestmentRow> rows = ArcAccountInvestmentsController.getInvestmentsAndServices(
      account.Id
    );
    Test.stopTest();

    Assert.areEqual(3, rows.size());
    Assert.areEqual('Apple Product', rows[0].name);
    Assert.areEqual('Middle Service', rows[1].name);
    Assert.areEqual('Zebra ISA', rows[2].name);
  }

  @IsTest
  static void getInvestmentsAndServicesReturnsEmptyForNullAccountId() {
    Test.startTest();
    List<ArcAccountInvestmentsController.InvestmentRow> rows = ArcAccountInvestmentsController.getInvestmentsAndServices(
      null
    );
    Test.stopTest();

    Assert.isNotNull(rows, 'Rows should be an empty list, not null.');
    Assert.areEqual(0, rows.size());
  }
}