@IsTest
private class ArcTaskFinAcctPanelControllerTest {
  @IsTest
  static void getFinancialAccountDetailReturnsNameAndAccountNumber() {
    Financial_Account__c account = new Financial_Account__c(Name = 'Test Financial Account');
    insert account;

    Task record = new Task(
      Subject = 'Add Account Number to the Financial Account Record in Salesforce',
      Status = 'Not Started',
      DFPG_Financial_Account__c = account.Id
    );
    insert record;

    Test.startTest();
    ArcTaskFinAcctPanelController.FinancialAccountDetail result = ArcTaskFinAcctPanelController.getFinancialAccountDetail(
      record.Id
    );
    Test.stopTest();

    Assert.areEqual(account.Id, result.financialAccountId);
    Assert.areEqual('Test Financial Account', result.name);
    Assert.isNull(result.accountNumber, 'no account number has been set yet');
  }

  @IsTest
  static void getFinancialAccountDetailReturnsEmptyWhenTaskHasNoFinancialAccount() {
    Task record = new Task(Subject = 'Unrelated task', Status = 'Not Started');
    insert record;

    Test.startTest();
    ArcTaskFinAcctPanelController.FinancialAccountDetail result = ArcTaskFinAcctPanelController.getFinancialAccountDetail(
      record.Id
    );
    Test.stopTest();

    Assert.isNull(result.financialAccountId);
    Assert.isNull(result.name);
  }

  @IsTest
  static void getFinancialAccountDetailReturnsEmptyForNullTaskId() {
    Test.startTest();
    ArcTaskFinAcctPanelController.FinancialAccountDetail result = ArcTaskFinAcctPanelController.getFinancialAccountDetail(
      null
    );
    Test.stopTest();

    Assert.isNull(result.financialAccountId);
  }

  @IsTest
  static void saveFinancialAccountDetailUpdatesNameAndAccountNumber() {
    Financial_Account__c account = new Financial_Account__c(Name = 'Before Save');
    insert account;

    Test.startTest();
    ArcTaskFinAcctPanelController.FinancialAccountDetail result = ArcTaskFinAcctPanelController.saveFinancialAccountDetail(
      account.Id,
      'After Save',
      '123456789'
    );
    Test.stopTest();

    Assert.areEqual('After Save', result.name);
    Assert.areEqual('123456789', result.accountNumber);

    Financial_Account__c saved = [
      SELECT Name, Account_Number__c
      FROM Financial_Account__c
      WHERE Id = :account.Id
    ];
    Assert.areEqual('After Save', saved.Name);
    Assert.areEqual('123456789', saved.Account_Number__c);
  }

  @IsTest
  static void saveFinancialAccountDetailThrowsWhenNameIsBlank() {
    Financial_Account__c account = new Financial_Account__c(Name = 'Has A Name');
    insert account;

    Test.startTest();
    try {
      ArcTaskFinAcctPanelController.saveFinancialAccountDetail(account.Id, '', '111');
      Assert.fail('Expected an AuraHandledException for a blank name');
    } catch (AuraHandledException e) {
      Assert.isTrue(e.getMessage().contains('Name is required'));
    }
    Test.stopTest();
  }

  @IsTest
  static void saveFinancialAccountDetailThrowsWhenFinancialAccountIdIsNull() {
    Test.startTest();
    try {
      ArcTaskFinAcctPanelController.saveFinancialAccountDetail(null, 'A Name', '111');
      Assert.fail('Expected an AuraHandledException for a null financial account id');
    } catch (AuraHandledException e) {
      Assert.isTrue(e.getMessage().contains('Financial account is required'));
    }
    Test.stopTest();
  }
}