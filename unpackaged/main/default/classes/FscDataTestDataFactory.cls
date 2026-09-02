/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-20
 *
 * Reusable test data factory for FSC relationship map Apex tests.
 *
 * Usage:
 *   @TestSetup
 *   static void setup() {
 *     FscDataTestDataFactory.createTreeScenario();
 *   }
 *
 *   @IsTest
 *   static void example() {
 *     FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
 *   }
 *
 * Isolated scenarios (unique account names per call):
 *   FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.createTreeScenario(
 *     new FscDataTestDataFactory.TreeScenarioOptions().withUniqueNames()
 *   );
 */
@IsTest
public class FscDataTestDataFactory {
  public static final String ROOT_ACCOUNT_NAME = 'FscData Root Account';
  public static final String SECOND_ROOT_ACCOUNT_NAME = 'FscData Second Root';
  public static final String LINKED_PERSON_FIRST_NAME = 'FscData';
  public static final String LINKED_PERSON_LAST_NAME = 'Linked Person';
  public static final String UNLINKED_PERSON_FIRST_NAME = 'FscData';
  public static final String UNLINKED_PERSON_LAST_NAME = 'Unlinked Person';
  public static final String SECOND_PERSON_FIRST_NAME = 'FscData';
  public static final String SECOND_PERSON_LAST_NAME = 'Second Person';
  public static final String RELATED_BUSINESS_ACCOUNT_NAME = 'FscData Related Business';
  public static final String VENDOR_ACCOUNT_NAME = 'FscData Vendor Account';
  public static final String UNCLASSIFIED_ACCOUNT_NAME = 'FscData Unclassified Account';

  private static Integer scenarioSequence = 0;

  public class TreeScenarioOptions {
    public Boolean useUniqueNames = false;
    public Boolean includeClassifications = false;
    public Boolean includeBusinessRelationship = true;
    public Boolean includeSecondHouseholdMember = true;
    public String scenarioKey;

    public TreeScenarioOptions withUniqueNames() {
      this.useUniqueNames = true;
      return this;
    }

    public TreeScenarioOptions withClassifications() {
      this.includeClassifications = true;
      return this;
    }

    public TreeScenarioOptions withoutBusinessRelationship() {
      this.includeBusinessRelationship = false;
      return this;
    }

    public TreeScenarioOptions withoutSecondHouseholdMember() {
      this.includeSecondHouseholdMember = false;
      return this;
    }
  }

  public class TreeScenario {
    public String scenarioKey;
    public Account rootAccount;
    public Account secondRootAccount;
    public Account relatedBusinessAccount;
    public Account linkedPersonAccount;
    public Account unlinkedPersonAccount;
    public Account secondPersonAccount;
    public Account vendorAccount;
    public Account unclassifiedAccount;
    public Account_Account_Relationship__c primaryAccountRelationship;

    public TreeScenario reload() {
      return FscDataTestDataFactory.loadTreeScenario(this.rootAccount.Id);
    }
  }

  public static TreeScenario createTreeScenario() {
    return createTreeScenario(new TreeScenarioOptions());
  }

  public static TreeScenario createTreeScenario(TreeScenarioOptions options) {
    TreeScenarioOptions resolvedOptions = options == null
      ? new TreeScenarioOptions()
      : options;
    String scenarioKey = resolveScenarioKey(resolvedOptions);
    TreeScenario scenario = new TreeScenario();
    scenario.scenarioKey = scenarioKey;

    scenario.rootAccount = createHouseholdAccount(buildScenarioName(ROOT_ACCOUNT_NAME, scenarioKey));
    scenario.secondRootAccount = createHouseholdAccount(
      buildScenarioName(SECOND_ROOT_ACCOUNT_NAME, scenarioKey)
    );
    scenario.relatedBusinessAccount = createRootAccount(
      buildScenarioName(RELATED_BUSINESS_ACCOUNT_NAME, scenarioKey)
    );
    scenario.linkedPersonAccount = createPersonAccount(
      LINKED_PERSON_FIRST_NAME,
      buildScenarioName(LINKED_PERSON_LAST_NAME, scenarioKey)
    );
    scenario.unlinkedPersonAccount = createPersonAccount(
      UNLINKED_PERSON_FIRST_NAME,
      buildScenarioName(UNLINKED_PERSON_LAST_NAME, scenarioKey)
    );
    scenario.secondPersonAccount = createPersonAccount(
      SECOND_PERSON_FIRST_NAME,
      buildScenarioName(SECOND_PERSON_LAST_NAME, scenarioKey)
    );

    assignActiveClientAccountType(
      new List<Account>{
        scenario.linkedPersonAccount,
        scenario.unlinkedPersonAccount,
        scenario.secondPersonAccount
      }
    );
    assignClientHousehold(
      new List<Account>{
        scenario.linkedPersonAccount,
        scenario.secondPersonAccount
      },
      scenario.rootAccount.Id
    );

    if (resolvedOptions.includeBusinessRelationship) {
      scenario.primaryAccountRelationship = createAccountRelationship(
        scenario.rootAccount,
        scenario.relatedBusinessAccount,
        resolveDefaultAarRoleValue()
      );
    }

    if (
      resolvedOptions.includeClassifications &&
      hasClassificationField()
    ) {
      scenario.vendorAccount = createClassifiedBusinessAccount(
        buildScenarioName(VENDOR_ACCOUNT_NAME, scenarioKey),
        FscRelClassificationUtils.VENDOR
      );
      scenario.unclassifiedAccount = createClassifiedBusinessAccount(
        buildScenarioName(UNCLASSIFIED_ACCOUNT_NAME, scenarioKey),
        FscRelClassificationUtils.UNCLASSIFIED
      );
    }

    return scenario;
  }

  public static TreeScenario loadTreeScenario() {
    List<Account> rootAccounts = [
      SELECT Id
      FROM Account
      WHERE Name = :ROOT_ACCOUNT_NAME
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];

    System.assert(
      !rootAccounts.isEmpty(),
      'Call FscDataTestDataFactory.createTreeScenario() in @TestSetup before loadTreeScenario().'
    );

    return loadTreeScenario(rootAccounts[0].Id);
  }

  public static TreeScenario loadTreeScenario(Id rootAccountId) {
    TreeScenario scenario = new TreeScenario();

    scenario.rootAccount = queryAccountById(rootAccountId);
    scenario.scenarioKey = scenario.rootAccount.Name;

    scenario.secondRootAccount = queryAccountByNamePrefix(SECOND_ROOT_ACCOUNT_NAME);
    scenario.relatedBusinessAccount = queryAccountByNamePrefix(
      RELATED_BUSINESS_ACCOUNT_NAME
    );
    scenario.linkedPersonAccount = queryPersonAccountByLastName(LINKED_PERSON_LAST_NAME);
    scenario.unlinkedPersonAccount = queryPersonAccountByLastName(
      UNLINKED_PERSON_LAST_NAME
    );
    scenario.secondPersonAccount = queryPersonAccountByLastName(SECOND_PERSON_LAST_NAME);

    scenario.primaryAccountRelationship = queryPrimaryAccountRelationship(
      scenario.rootAccount.Id,
      scenario.relatedBusinessAccount.Id
    );

    if (hasClassificationField()) {
      scenario.vendorAccount = queryOptionalAccountByNamePrefix(VENDOR_ACCOUNT_NAME);
      scenario.unclassifiedAccount = queryOptionalAccountByNamePrefix(
        UNCLASSIFIED_ACCOUNT_NAME
      );
    }

    ensureClientAccountTypes(scenario);

    return scenario;
  }

  private static void ensureClientAccountTypes(TreeScenario scenario) {
    assignActiveClientAccountType(
      new List<Account>{
        scenario.linkedPersonAccount,
        scenario.unlinkedPersonAccount,
        scenario.secondPersonAccount
      }
    );

    scenario.linkedPersonAccount = queryAccountById(scenario.linkedPersonAccount.Id);
    scenario.secondPersonAccount = queryAccountById(scenario.secondPersonAccount.Id);
    scenario.unlinkedPersonAccount = queryAccountById(
      scenario.unlinkedPersonAccount.Id
    );
  }

  /**
   * Creates a generic business Account without a Household record type.
   * Use createHouseholdAccount for Account records that should be Household RT.
   */
  public static void applyRequiredAccountTypeOrClassification(Account account) {
    if (account == null) {
      return;
    }

    if (
      !String.isBlank(account.Type) ||
      !String.isBlank(account.Classification__c)
    ) {
      return;
    }

    String accountType = FscRelClientAccountUtils.resolveClientAccountTypeForDataSetup();

    if (!String.isBlank(accountType)) {
      account.Type = accountType;
      return;
    }

    if (hasClassificationField()) {
      account.Classification__c = FscRelClassificationUtils.UNCLASSIFIED;
    }
  }

  public static Account createRootAccount(String name) {
    Account rootAccount = new Account(Name = name);
    applyRequiredAccountTypeOrClassification(rootAccount);
    insert rootAccount;
    return rootAccount;
  }

  /**
   * Creates a Household Account using Household (preferred) or IndustriesHousehold (legacy).
   */
  public static Account createHouseholdAccount(String name) {
    return insertHouseholdAccount(
      name,
      FscRelAccountRepository.selectHouseholdRecordTypeId()
    );
  }

  /**
   * Creates a Household Account suitable as an Account.Household__c lookup target.
   * Prefers IndustriesHousehold when present for legacy lookup-filter compatibility.
   */
  public static Account createHouseholdAccountForClientLink(String name) {
    return insertHouseholdAccount(
      name,
      FscRelAccountRepository.selectHouseholdRecordTypeIdForClientHouseholdLink()
    );
  }

  private static Account insertHouseholdAccount(String name, Id householdRecordTypeId) {
    if (householdRecordTypeId == null) {
      return createRootAccount(name);
    }

    Account householdAccount = new Account(
      Name = name,
      RecordTypeId = householdRecordTypeId
    );
    insert householdAccount;
    return householdAccount;
  }

  public static Account createPersonAccount(String firstName, String lastName) {
    Account personAccount = new Account(
      FirstName = firstName,
      LastName = lastName,
      RecordTypeId = resolvePersonAccountRecordTypeId()
    );
    applyRequiredAccountTypeOrClassification(personAccount);
    insert personAccount;

    return queryAccountById(personAccount.Id);
  }

  public static AccountContactRelation createMembership(
    Account rootAccount,
    Account personAccount,
    Boolean isPrimaryMember,
    Boolean isPrimaryGroup,
    String roles
  ) {
    AccountContactRelation membership = new AccountContactRelation(
      AccountId = rootAccount.Id,
      ContactId = personAccount.PersonContactId,
      Roles = roles,
      IsActive = true
    );
    insert membership;
    return membership;
  }

  public static Account_Account_Relationship__c createAccountRelationship(
    Account rootAccount,
    Account relatedAccount,
    String role
  ) {
    return createAccountRelationship(rootAccount, relatedAccount, role, 'Business');
  }

  public static Account_Account_Relationship__c createAccountRelationship(
    Account rootAccount,
    Account relatedAccount,
    String role,
    String recordTypeDeveloperName
  ) {
    Id recordTypeId = FscRelRecordTypeUtils.selectAccountRelationRecordTypeId(
      recordTypeDeveloperName
    );
    Account_Account_Relationship__c relationship = new Account_Account_Relationship__c(
      Account__c = rootAccount.Id,
      Related_Account__c = relatedAccount.Id,
      Roles__c = String.isBlank(role) ? resolveDefaultAarRoleValue() : role
    );

    if (recordTypeId != null) {
      relationship.RecordTypeId = recordTypeId;
    }

    insert relationship;
    return relationship;
  }

  public static Boolean hasClassificationField() {
    return Account.SObjectType.getDescribe()
      .fields.getMap()
      .containsKey('Classification__c');
  }

  public static Account assignClassification(
    Account account,
    String classificationValue
  ) {
    if (account == null || account.Id == null || !hasClassificationField()) {
      return account;
    }

    update new Account(
      Id = account.Id,
      Classification__c = classificationValue
    );

    return queryAccountById(account.Id);
  }

  public static Account createClassifiedBusinessAccount(
    String name,
    String classificationValue
  ) {
    Account account = createRootAccount(name);
    return assignClassification(account, classificationValue);
  }

  public static Reciprocal_Role__c createReciprocalRole(String roleName) {
    return createReciprocalRole(roleName, roleName);
  }

  public static Reciprocal_Role__c createReciprocalRole(
    String roleName,
    String inverseRoleName
  ) {
    FscRelReciprocalRoleRepository repository = new FscRelReciprocalRoleRepository();
    Id recordTypeId = repository.selectContactRecordTypeId();
    Reciprocal_Role__c role = repository.findByRoleName(roleName);

    if (role != null) {
      return role;
    }

    if (
      !String.isBlank(inverseRoleName) &&
      !roleName.trim().equalsIgnoreCase(inverseRoleName.trim())
    ) {
      repository.findOrCreateByRoleName(inverseRoleName, recordTypeId);
    }

    return repository.insertRole(roleName, recordTypeId);
  }

  public static Reciprocal_Role__c createReciprocalRoleForMemberRelationship(
    String aarRecordTypeDeveloperName,
    String roleName,
    String inverseRoleName
  ) {
    Id recordTypeId = FscRelRecordTypeUtils.selectReciprocalRoleRecordTypeId(
      aarRecordTypeDeveloperName
    );
    if (recordTypeId == null) {
      recordTypeId = new FscRelReciprocalRoleRepository().selectContactRecordTypeId();
    }

    FscRelReciprocalRoleRepository repository = new FscRelReciprocalRoleRepository();
    repository.findOrCreateByRoleName(inverseRoleName, recordTypeId);

    Reciprocal_Role__c role = repository.findByRoleName(roleName, recordTypeId);
    if (role != null) {
      return role;
    }

    return repository.insertRole(roleName, recordTypeId);
  }

  public static FscRelHouseholdModels.TreeMemberAccountRelationshipInput buildMemberAccountRelationshipInput(
    Account relatedAccount,
    Reciprocal_Role__c role,
    Reciprocal_Role__c inverseRole,
    Boolean isActive,
    String rowKey
  ) {
    FscRelHouseholdModels.TreeMemberAccountRelationshipInput input = new FscRelHouseholdModels.TreeMemberAccountRelationshipInput();
    input.rowKey = String.isBlank(rowKey) ? 'row-1' : rowKey;
    input.relatedAccountId = String.valueOf(relatedAccount.Id);
    input.reciprocalRoleId = String.valueOf(role.Id);
    input.inverseReciprocalRoleId = String.valueOf(inverseRole.Id);
    input.role = role.Role__c;
    input.inverseRole = inverseRole.Role__c;
    input.isActive = isActive == true;
    return input;
  }

  public static String resolveMemberRelationshipRecordTypeDeveloperName() {
    FscRelReciprocalRoleRepository repository = new FscRelReciprocalRoleRepository();
    Id reciprocalRoleRecordTypeId = repository.selectContactRecordTypeId();

    for (
      FscRelHouseholdModels.RecordTypeOption option : FscRelRecordTypeUtils.selectActiveAccountRelationRecordTypes()
    ) {
      Id mappedRecordTypeId = FscRelRecordTypeUtils.selectReciprocalRoleRecordTypeId(
        option.developerName
      );
      if (mappedRecordTypeId == reciprocalRoleRecordTypeId) {
        return option.developerName;
      }
    }

    List<FscRelHouseholdModels.RecordTypeOption> options = FscRelRecordTypeUtils.selectActiveAccountRelationRecordTypes();
    return options.isEmpty() ? null : options[0].developerName;
  }

  public static String resolveDefaultRoleValue() {
    if (defaultRoleValue != null) {
      return defaultRoleValue;
    }

    defaultRoleValue = 'Client';
    return defaultRoleValue;
  }

  public static String resolveDefaultAarRoleValue() {
    if (defaultAarRoleValue != null) {
      return defaultAarRoleValue;
    }

    defaultAarRoleValue = resolveFirstActivePicklistValue(
      Account_Account_Relationship__c.Roles__c,
      new List<String>{
        'Employer',
        'Business Partner',
        'Co-worker / Colleague',
        'Referrer',
        'Client'
      }
    );
    return defaultAarRoleValue;
  }

  public static List<String> resolveDefaultAarSelectedRoles() {
    String defaultRole = resolveDefaultAarRoleValue();
    return String.isBlank(defaultRole)
      ? new List<String>()
      : new List<String>{ defaultRole };
  }

  public static void assignActiveClientAccountType(List<Account> accounts) {
    if (accounts == null || accounts.isEmpty()) {
      return;
    }

    String clientType = FscRelClientAccountUtils.resolveClientAccountTypeForDataSetup();

    if (String.isBlank(clientType)) {
      return;
    }

    List<Account> accountsToUpdate = new List<Account>();
    for (Account account : accounts) {
      if (account == null || account.Id == null) {
        continue;
      }

      accountsToUpdate.add(new Account(Id = account.Id, Type = clientType));
    }

    if (!accountsToUpdate.isEmpty()) {
      update accountsToUpdate;
    }
  }

  public static void assignClientHousehold(
    List<Account> accounts,
    Id householdId
  ) {
    if (accounts == null || accounts.isEmpty() || householdId == null) {
      return;
    }

    List<Account> accountsToUpdate = new List<Account>();
    for (Account account : accounts) {
      if (account == null || account.Id == null) {
        continue;
      }

      accountsToUpdate.add(
        new Account(Id = account.Id, Household__c = householdId)
      );
    }

    if (!accountsToUpdate.isEmpty()) {
      try {
        update accountsToUpdate;
      } catch (DmlException ex) {
        if (!isHouseholdLookupFilterException(ex)) {
          throw ex;
        }
      }
    }

    createHouseholdMembershipRelations(accounts, householdId);
  }

  public static void createHouseholdMembershipRelations(
    List<Account> memberAccounts,
    Id householdId
  ) {
    if (memberAccounts == null || memberAccounts.isEmpty() || householdId == null) {
      return;
    }

    Id householdRecordTypeId = FscRelRecordTypeUtils.selectAccountRelationRecordTypeId(
      FscRelRecordTypeUtils.HOUSEHOLD_AAR_RECORD_TYPE
    );

    if (householdRecordTypeId == null) {
      return;
    }

    Set<Id> memberAccountIds = new Set<Id>();
    for (Account memberAccount : memberAccounts) {
      if (memberAccount?.Id != null) {
        memberAccountIds.add(memberAccount.Id);
      }
    }

    if (memberAccountIds.isEmpty()) {
      return;
    }

    Set<String> existingMembershipKeys = new Set<String>();
    for (Account_Account_Relationship__c existingRelation : [
      SELECT Account__c, Related_Account__c
      FROM Account_Account_Relationship__c
      WHERE
        Account__c = :householdId
        AND Related_Account__c IN :memberAccountIds
        AND RecordTypeId = :householdRecordTypeId
    ]) {
      existingMembershipKeys.add(
        String.valueOf(existingRelation.Account__c) +
          ':' +
          String.valueOf(existingRelation.Related_Account__c)
      );
    }

    List<Account_Account_Relationship__c> relationsToInsert = new List<Account_Account_Relationship__c>();
    for (Id memberAccountId : memberAccountIds) {
      String membershipKey =
        String.valueOf(householdId) + ':' + String.valueOf(memberAccountId);

      if (existingMembershipKeys.contains(membershipKey)) {
        continue;
      }

      relationsToInsert.add(
        new Account_Account_Relationship__c(
          Account__c = householdId,
          Related_Account__c = memberAccountId,
          RecordTypeId = householdRecordTypeId,
          Active__c = true
        )
      );
    }

    if (!relationsToInsert.isEmpty()) {
      insert relationsToInsert;
    }
  }

  private static Boolean isHouseholdLookupFilterException(DmlException ex) {
    if (ex == null) {
      return false;
    }

    return ex.getMessage().contains('FIELD_FILTER_VALIDATION_EXCEPTION') &&
      ex.getMessage().contains('Household__c');
  }

  private static String resolveScenarioKey(TreeScenarioOptions options) {
    if (!String.isBlank(options.scenarioKey)) {
      return options.scenarioKey.trim();
    }

    if (options.useUniqueNames) {
      scenarioSequence++;
      return 'S' + String.valueOf(scenarioSequence);
    }

    return 'default';
  }

  private static String buildScenarioName(String baseName, String scenarioKey) {
    if (scenarioKey == 'default') {
      return baseName;
    }

    return baseName + ' ' + scenarioKey;
  }

  private static Account queryAccountById(Id accountId) {
    return [
      SELECT
        Id,
        Name,
        IsPersonAccount,
        PersonContactId,
        Classification__c,
        RecordTypeId,
        Household__c,
        Type
      FROM Account
      WHERE Id = :accountId
      LIMIT 1
    ];
  }

  private static Account queryAccountByNamePrefix(String baseName) {
    return [
      SELECT Id, Name, IsPersonAccount, PersonContactId, Classification__c
      FROM Account
      WHERE Name = :baseName OR Name LIKE :(baseName + ' %')
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
  }

  private static Account queryOptionalAccountByNamePrefix(String baseName) {
    List<Account> accounts = [
      SELECT Id, Name, IsPersonAccount, PersonContactId, Classification__c
      FROM Account
      WHERE Name = :baseName OR Name LIKE :(baseName + ' %')
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];

    return accounts.isEmpty() ? null : accounts[0];
  }

  private static Account queryPersonAccountByLastName(String baseLastName) {
    return [
      SELECT Id, Name, IsPersonAccount, PersonContactId, Classification__c
      FROM Account
      WHERE LastName = :baseLastName OR LastName LIKE :(baseLastName + ' %')
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
  }

  private static Account_Account_Relationship__c queryPrimaryAccountRelationship(
    Id rootAccountId,
    Id relatedAccountId
  ) {
    List<Account_Account_Relationship__c> relationships = [
      SELECT Id, Account__c, Related_Account__c, Roles__c
      FROM Account_Account_Relationship__c
      WHERE Account__c = :rootAccountId AND Related_Account__c = :relatedAccountId
      LIMIT 1
    ];

    return relationships.isEmpty() ? null : relationships[0];
  }

  private static String resolveAccountTypeValue(String preferredValue) {
    Schema.DescribeFieldResult typeDescribe = Account.Type.getDescribe();

    for (Schema.PicklistEntry entry : typeDescribe.getPicklistValues()) {
      if (entry.isActive() && entry.getValue() == preferredValue) {
        return entry.getValue();
      }
    }

    return null;
  }

  private static String resolveFirstActivePicklistValue(
    Schema.SObjectField field,
    List<String> preferredValues
  ) {
    Set<String> activeValues = new Set<String>();

    for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
      if (entry.isActive()) {
        activeValues.add(entry.getValue());
      }
    }

    if (preferredValues != null) {
      for (String preferredValue : preferredValues) {
        if (activeValues.contains(preferredValue)) {
          return preferredValue;
        }
      }
    }

    for (String activeValue : activeValues) {
      return activeValue;
    }

    return '';
  }

  private static Id personAccountRecordTypeId;
  private static String defaultRoleValue;
  private static String defaultAarRoleValue;

  private static Id resolvePersonAccountRecordTypeId() {
    if (personAccountRecordTypeId != null) {
      return personAccountRecordTypeId;
    }

    List<RecordType> personRecordTypes = [
      SELECT Id
      FROM RecordType
      WHERE SObjectType = 'Account' AND IsPersonType = TRUE AND IsActive = TRUE
      LIMIT 1
    ];

    System.assert(
      !personRecordTypes.isEmpty(),
      'A person account record type is required to run FSC relationship tests.'
    );

    personAccountRecordTypeId = personRecordTypes[0].Id;
    return personAccountRecordTypeId;
  }
}