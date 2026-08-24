/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-01
 *
 * Service layer for FSC Relationship Tree reads and writes.
 */
public with sharing class FscRelHouseholdService {
  private static final Integer RECIPROCAL_ROLE_LOOKUP_LIMIT = 50;

  private final FscRelAccountRepository accountRepository;
  private final FscRelAccountRelationRepository accountRelationRepository;
  private final FscRelContactRepository contactRepository;
  private final FscRelReciprocalRoleRepository reciprocalRoleRepository;

  public FscRelHouseholdService() {
    this(
      new FscRelAccountRepository(),
      new FscRelAccountRelationRepository(),
      new FscRelContactRepository(),
      new FscRelReciprocalRoleRepository()
    );
  }

  @TestVisible
  private FscRelHouseholdService(
    FscRelAccountRepository accountRepository,
    FscRelAccountRelationRepository accountRelationRepository,
    FscRelContactRepository contactRepository,
    FscRelReciprocalRoleRepository reciprocalRoleRepository
  ) {
    this.accountRepository = accountRepository;
    this.accountRelationRepository = accountRelationRepository;
    this.contactRepository = contactRepository;
    this.reciprocalRoleRepository = reciprocalRoleRepository;
  }

  public FscRelHouseholdModels.RootAccountResolveResult resolveRootAccount(Id accountId) {
    FscRelHouseholdModels.RootAccountResolveResult resolveResult = new FscRelHouseholdModels.RootAccountResolveResult();
    resolveResult.isPersonAccount = false;
    resolveResult.rootAccountId = null;

    if (accountId == null) {
      return resolveResult;
    }

    Account account = accountRepository.selectById(accountId);
    if (account == null) {
      return resolveResult;
    }

    Boolean isPersonAccount = FscRelAccountRepository.isPersonAccountRecord(account);
    resolveResult.isPersonAccount = isPersonAccount;

    if (!isPersonAccount) {
      if (FscRelAccountRepository.isHouseholdRecordType(account)) {
        resolveResult.rootAccountId = account.Id;
        return resolveResult;
      }

      if (account.Household__c != null) {
        resolveResult.rootAccountId = account.Household__c;
        return resolveResult;
      }

      resolveResult.rootAccountId = account.Id;
      return resolveResult;
    }

    if (account.PersonContactId == null) {
      return resolveResult;
    }

    if (account.Household__c != null) {
      resolveResult.rootAccountId = account.Household__c;
    }

    return resolveResult;
  }

  public FscRelHouseholdModels.RelationshipTreeData getRelationshipTree(Id rootAccountId) {
    if (rootAccountId == null) {
      throw new AuraHandledException('No root account id provided.');
    }

    Account rootAccount = accountRepository.selectById(rootAccountId);
    if (rootAccount == null) {
      throw new AuraHandledException('Root account not found.');
    }

    FscRelHouseholdModels.RelationshipTreeData data = new FscRelHouseholdModels.RelationshipTreeData();
    data.rootAccountId = String.valueOf(rootAccount.Id);
    data.name = rootAccount.Name;
    data.recordTypeDeveloperName = rootAccount.RecordType == null
      ? null
      : rootAccount.RecordType.DeveloperName;
    data.recordTypeLabel = rootAccount.RecordType == null
      ? null
      : rootAccount.RecordType.Name;
    data.relatedAccounts = buildRelatedAccounts(
      accountRelationRepository.selectByRootAccount(rootAccountId)
    );
    data.clientAccounts = buildClientAccounts(rootAccountId);
    data.members = buildMembersFromClientAccounts(data.clientAccounts);
    data.leadProspectAccounts = buildLeadProspectAccounts(rootAccountId);
    data.householdLinkedAccounts = buildHouseholdLinkedAccounts(rootAccountId);
    promoteLeadProspectRelatedAccounts(data);
    data.classifiedAccounts = buildClassifiedAccounts(
      rootAccountId,
      data.clientAccounts,
      data.relatedAccounts
    );
    return data;
  }

  public FscRelHouseholdModels.RelationshipTreeData getPersonAccountMapTree(
    Id personAccountId
  ) {
    if (personAccountId == null) {
      throw new AuraHandledException('No person account id provided.');
    }

    Account personAccount = accountRepository.selectById(personAccountId);
    if (personAccount == null) {
      throw new AuraHandledException('Person account not found.');
    }

    if (!FscRelAccountRepository.isPersonAccountRecord(personAccount)) {
      throw new AuraHandledException('The supplied account is not a Person Account.');
    }

    FscRelHouseholdModels.RelationshipTreeData data = new FscRelHouseholdModels.RelationshipTreeData();
    data.rootAccountId = String.valueOf(personAccount.Id);
    data.name = personAccount.Name;
    data.recordTypeDeveloperName = personAccount.RecordType == null
      ? null
      : personAccount.RecordType.DeveloperName;
    data.recordTypeLabel = personAccount.RecordType == null
      ? null
      : personAccount.RecordType.Name;
    data.relatedAccounts = new List<FscRelHouseholdModels.TreeAccount>();

    FscRelHouseholdModels.TreeMember member = new FscRelHouseholdModels.TreeMember();
    member.accountId = String.valueOf(personAccount.Id);
    member.contactId = personAccount.PersonContactId == null
      ? null
      : String.valueOf(personAccount.PersonContactId);
    member.name = personAccount.Name;
    member.roles = new List<String>();
    member.isPrimaryMember = false;
    member.isPrimaryGroup = false;
    member.isActive = true;
    member.recordTypeDeveloperName = data.recordTypeDeveloperName;
    member.recordTypeLabel = data.recordTypeLabel;
    member.accountType = personAccount.Type;
    data.members = new List<FscRelHouseholdModels.TreeMember>{ member };
    data.clientAccounts = FscRelClientAccountUtils.isClientAccount(personAccount)
      ? new List<FscRelHouseholdModels.TreeAccount>{
          mapAccountToTreeAccount(personAccount)
        }
      : new List<FscRelHouseholdModels.TreeAccount>();
    data.leadProspectAccounts = FscRelClientAccountUtils.isLeadProspectAccount(
        personAccount
      )
      ? new List<FscRelHouseholdModels.TreeAccount>{
          mapAccountToTreeAccount(personAccount)
        }
      : new List<FscRelHouseholdModels.TreeAccount>();
    data.classifiedAccounts = buildClassifiedAccounts(
      personAccount.Household__c,
      data.clientAccounts,
      data.relatedAccounts
    );
    data.householdLinkedAccounts = personAccount.Household__c == null
      ? new List<FscRelHouseholdModels.TreeAccount>()
      : buildHouseholdLinkedAccounts(personAccount.Household__c);

    return data;
  }

  public String getAccountName(Id accountId) {
    return accountRepository.selectNameById(accountId);
  }

  public String getAccountRecordTypeId(Boolean personAccountsOnly) {
    Id recordTypeId = FscRelRecordTypeUtils.selectDefaultAccountRecordTypeId(
      personAccountsOnly == true
    );
    return recordTypeId == null ? null : String.valueOf(recordTypeId);
  }

  public FscRelHouseholdModels.RecordTypeInfo getRecordTypeByDeveloperName(
    String objectApiName,
    String recordTypeDeveloperName
  ) {
    FscRelHouseholdModels.RecordTypeInfo recordTypeInfo = new FscRelHouseholdModels.RecordTypeInfo();

    if (String.isBlank(objectApiName) || String.isBlank(recordTypeDeveloperName)) {
      return recordTypeInfo;
    }

    RecordType recordType = FscRelRecordTypeUtils.selectRecordTypeByDeveloperName(
      objectApiName,
      recordTypeDeveloperName.trim()
    );

    if (recordType == null) {
      return recordTypeInfo;
    }

    recordTypeInfo.recordTypeId = String.valueOf(recordType.Id);
    recordTypeInfo.isPersonType = recordType.IsPersonType == true;
    recordTypeInfo.developerName = recordType.DeveloperName;
    return recordTypeInfo;
  }

  public List<FscRelHouseholdModels.LookupOption> searchAccounts(
    String searchTerm,
    Boolean personAccountsOnly
  ) {
    List<Account> accounts = accountRepository.searchAccountsByName(
      searchTerm,
      personAccountsOnly == true,
      8
    );

    List<FscRelHouseholdModels.LookupOption> options = new List<FscRelHouseholdModels.LookupOption>();
    for (Account account : accounts) {
      FscRelHouseholdModels.LookupOption option = new FscRelHouseholdModels.LookupOption();
      option.id = account.Id;
      option.label = account.Name;
      option.subtitle = formatAccountAddressSubtitle(account);
      option.iconName = 'standard:account';
      options.add(option);
    }

    return options;
  }

  public List<FscRelHouseholdModels.LookupOption> searchAccountsInScope(
    String searchTerm,
    Boolean personAccountsOnly,
    List<String> allowedAccountIds
  ) {
    Set<Id> scopedAccountIds = parseAccountIds(allowedAccountIds);
    if (scopedAccountIds.isEmpty()) {
      return new List<FscRelHouseholdModels.LookupOption>();
    }

    List<Account> accounts = accountRepository.searchAccountsByNameInIds(
      searchTerm,
      personAccountsOnly == true,
      scopedAccountIds,
      8
    );

    return mapAccountsToLookupOptions(accounts);
  }

  public List<FscRelHouseholdModels.LookupOption> searchAccountsByClassification(
    String searchTerm,
    String classificationValue
  ) {
    if (String.isBlank(classificationValue)) {
      return new List<FscRelHouseholdModels.LookupOption>();
    }

    List<Account> accounts = accountRepository.searchAccountsByClassification(
      searchTerm,
      classificationValue,
      8
    );

    return mapAccountsToLookupOptions(accounts);
  }

  public FscRelHouseholdModels.TreeAccountResult linkClassificationAccountToHousehold(
    Id rootAccountId,
    Id accountId,
    String classificationValue
  ) {
    if (rootAccountId == null) {
      return new FscRelHouseholdModels.TreeAccountResult(
        false,
        'No root account id provided.',
        null
      );
    }

    if (accountId == null) {
      return new FscRelHouseholdModels.TreeAccountResult(
        false,
        'Select an account to add.',
        null
      );
    }

    if (String.isBlank(classificationValue)) {
      return new FscRelHouseholdModels.TreeAccountResult(
        false,
        'No classification value provided.',
        null
      );
    }

    if (accountId == rootAccountId) {
      return new FscRelHouseholdModels.TreeAccountResult(
        false,
        'The household account cannot be added to itself.',
        null
      );
    }

    Account account = accountRepository.selectById(accountId);
    if (account == null) {
      return new FscRelHouseholdModels.TreeAccountResult(
        false,
        'Account not found.',
        null
      );
    }

    if (
      !FscRelClassificationUtils.includesClassification(account, classificationValue)
    ) {
      return new FscRelHouseholdModels.TreeAccountResult(
        false,
        'The selected account does not include the required classification.',
        null
      );
    }

    if (account.Household__c != null) {
      if (account.Household__c == rootAccountId) {
        return new FscRelHouseholdModels.TreeAccountResult(
          true,
          'Account is already linked to this household.',
          String.valueOf(accountId)
        );
      }

      return new FscRelHouseholdModels.TreeAccountResult(
        false,
        'The selected account is already linked to another household.',
        null
      );
    }

    accountRepository.updateHouseholdLink(accountId, rootAccountId);

    return new FscRelHouseholdModels.TreeAccountResult(
      true,
      'Account linked to household.',
      String.valueOf(accountId)
    );
  }

  public List<FscRelHouseholdModels.LookupOption> getAccountsByIds(
    List<String> accountIds,
    Boolean personAccountsOnly
  ) {
    Set<Id> scopedAccountIds = parseAccountIds(accountIds);
    if (scopedAccountIds.isEmpty()) {
      return new List<FscRelHouseholdModels.LookupOption>();
    }

    List<Account> accounts = personAccountsOnly == true
      ? accountRepository.selectPersonAccountsByIds(scopedAccountIds)
      : accountRepository.selectAccountsByIdsWithClassifications(scopedAccountIds);

    return mapAccountsToLookupOptions(accounts);
  }

  private List<FscRelHouseholdModels.LookupOption> mapAccountsToLookupOptions(
    List<Account> accounts
  ) {
    List<FscRelHouseholdModels.LookupOption> options = new List<FscRelHouseholdModels.LookupOption>();

    for (Account account : accounts) {
      FscRelHouseholdModels.LookupOption option = new FscRelHouseholdModels.LookupOption();
      option.id = account.Id;
      option.label = account.Name;
      option.subtitle = formatAccountAddressSubtitle(account);
      option.iconName = 'standard:account';
      options.add(option);
    }

    return options;
  }

  private Set<Id> parseAccountIds(List<String> accountIds) {
    Set<Id> ids = new Set<Id>();

    if (accountIds == null) {
      return ids;
    }

    for (String rawId : accountIds) {
      if (String.isBlank(rawId)) {
        continue;
      }

      try {
        ids.add(Id.valueOf(rawId));
      } catch (Exception ignored) {
        // Skip malformed ids.
      }
    }

    return ids;
  }

  public String getContactName(Id contactId) {
    return contactRepository.selectNameById(contactId);
  }

  public String getReciprocalRoleName(Id reciprocalRoleId) {
    return reciprocalRoleRepository.selectDisplayNameById(reciprocalRoleId);
  }

  public List<FscRelHouseholdModels.LookupOption> searchReciprocalRoles(
    String searchTerm
  ) {
    return searchReciprocalRoles(searchTerm, null);
  }

  public List<FscRelHouseholdModels.LookupOption> searchReciprocalRoles(
    String searchTerm,
    String recordTypeDeveloperName
  ) {
    Id recordTypeId = String.isBlank(recordTypeDeveloperName)
      ? null
      : reciprocalRoleRepository.selectRecordTypeIdForCategory(
          recordTypeDeveloperName
        );

    if (String.isNotBlank(recordTypeDeveloperName) && recordTypeId == null) {
      return new List<FscRelHouseholdModels.LookupOption>();
    }

    List<Reciprocal_Role__c> roles = String.isBlank(searchTerm)
      ? reciprocalRoleRepository.selectForLookup(
          recordTypeId,
          RECIPROCAL_ROLE_LOOKUP_LIMIT
        )
      : reciprocalRoleRepository.searchByTerm(
          searchTerm,
          recordTypeId,
          RECIPROCAL_ROLE_LOOKUP_LIMIT
        );

    List<FscRelHouseholdModels.LookupOption> options = new List<FscRelHouseholdModels.LookupOption>();

    for (Reciprocal_Role__c role : roles) {
      FscRelHouseholdModels.LookupOption option = new FscRelHouseholdModels.LookupOption();
      option.id = role.Id;
      option.label = FscRelReciprocalRoleRepository.resolveDisplayName(role);
      option.iconName = 'custom:custom18';
      options.add(option);
    }

    return options;
  }

  public FscRelHouseholdModels.ReciprocalRoleDuplicateCheckResult validateReciprocalRoleForCreate(
    String role
  ) {
    FscRelHouseholdModels.ReciprocalRoleDuplicateCheckResult result = new FscRelHouseholdModels.ReciprocalRoleDuplicateCheckResult();
    result.blockSave = false;
    result.requiresConfirmation = false;
    result.message = '';

    String trimmedRole = String.isBlank(role) ? '' : role.trim();

    if (String.isBlank(trimmedRole)) {
      result.blockSave = true;
      result.message = 'Role is required.';
      return result;
    }

    Reciprocal_Role__c exactMatch = reciprocalRoleRepository.findByRoleName(trimmedRole);

    if (exactMatch != null) {
      result.blockSave = true;
      result.existingRole = exactMatch.Role__c;
      result.message = buildExactDuplicateMessage(exactMatch.Role__c);
      return result;
    }

    List<Reciprocal_Role__c> similarRoles = reciprocalRoleRepository.findSimilarRoleNames(
      trimmedRole
    );
    if (!similarRoles.isEmpty()) {
      Reciprocal_Role__c similarRole = similarRoles[0];
      result.requiresConfirmation = true;
      result.existingRole = similarRole.Role__c;
      result.message = buildSimilarRoleMessage(trimmedRole, similarRole);
    }

    return result;
  }

  public FscRelHouseholdModels.ReciprocalRoleCreateResult createReciprocalRole(
    String role,
    Boolean confirmDuplicate,
    String recordTypeDeveloperName
  ) {
    String trimmedRole = String.isBlank(role) ? '' : role.trim();
    Id recordTypeId = String.isBlank(recordTypeDeveloperName)
      ? reciprocalRoleRepository.selectContactRecordTypeId()
      : reciprocalRoleRepository.selectRecordTypeIdForCategory(
          recordTypeDeveloperName
        );

    FscRelHouseholdModels.ReciprocalRoleDuplicateCheckResult validation = validateReciprocalRoleForCreate(
      trimmedRole
    );

    if (validation.blockSave == true) {
      return new FscRelHouseholdModels.ReciprocalRoleCreateResult(
        false,
        validation.message,
        null,
        null
      );
    }

    if (validation.requiresConfirmation == true && confirmDuplicate != true) {
      return new FscRelHouseholdModels.ReciprocalRoleCreateResult(
        false,
        validation.message,
        null,
        null
      );
    }

    try {
      Reciprocal_Role__c createdRole = reciprocalRoleRepository.insertRole(
        trimmedRole,
        recordTypeId
      );

      return new FscRelHouseholdModels.ReciprocalRoleCreateResult(
        true,
        'Reciprocal role created.',
        String.valueOf(createdRole.Id),
        FscRelReciprocalRoleRepository.resolveDisplayName(createdRole)
      );
    } catch (Exception error) {
      return new FscRelHouseholdModels.ReciprocalRoleCreateResult(
        false,
        error.getMessage(),
        null,
        null
      );
    }
  }

  private static String buildExactDuplicateMessage(String role) {
    return 'Reciprocal role "' + role + '" already exists.';
  }

  private static String buildSimilarRoleMessage(
    String role,
    Reciprocal_Role__c existingRole
  ) {
    String existingRoleName = existingRole?.Role__c;

    return 'Reciprocal role "' +
      role +
      '" is similar to existing role "' +
      existingRoleName +
      '". Save anyway?';
  }

  private static String normalizeComparisonValue(String value) {
    return String.isBlank(value) ? '' : value.trim().toLowerCase();
  }

  public List<FscRelHouseholdModels.LookupOption> searchContacts(String searchTerm) {
    List<Contact> contacts = contactRepository.searchContactsByName(searchTerm, 8);
    List<FscRelHouseholdModels.LookupOption> options = new List<FscRelHouseholdModels.LookupOption>();

    for (Contact contact : contacts) {
      FscRelHouseholdModels.LookupOption option = new FscRelHouseholdModels.LookupOption();
      option.id = contact.Id;
      option.label = contact.Name;
      option.subtitle = formatContactSubtitle(contact);
      option.iconName = 'standard:contact';
      options.add(option);
    }

    return options;
  }

  private static String formatContactSubtitle(Contact contact) {
    List<String> parts = new List<String>();

    if (!String.isBlank(contact.Email)) {
      parts.add(contact.Email);
    }

    if (!String.isBlank(contact.Phone)) {
      parts.add(contact.Phone);
    }

    return String.join(parts, ' · ');
  }
  private static String formatAccountAddressSubtitle(Account account) {
    String billingAddress = joinAddressParts(
      account.BillingStreet,
      account.BillingCity,
      account.BillingState,
      account.BillingPostalCode
    );

    if (!String.isBlank(billingAddress)) {
      return billingAddress;
    }

    String mailingAddress = joinAddressParts(
      account.PersonMailingStreet,
      account.PersonMailingCity,
      account.PersonMailingState,
      account.PersonMailingPostalCode
    );

    if (!String.isBlank(mailingAddress)) {
      return mailingAddress;
    }

    return 'No Billing Address';
  }

  private static String joinAddressParts(
    String street,
    String city,
    String state,
    String postalCode
  ) {
    List<String> parts = new List<String>();

    if (!String.isBlank(street)) {
      parts.add(street.trim());
    }

    String cityStatePostal = '';
    if (!String.isBlank(city)) {
      cityStatePostal = city.trim();
    }

    if (!String.isBlank(state)) {
      cityStatePostal = String.isBlank(cityStatePostal)
        ? state.trim()
        : cityStatePostal + ', ' + state.trim();
    }

    if (!String.isBlank(postalCode)) {
      cityStatePostal = String.isBlank(cityStatePostal)
        ? postalCode.trim()
        : cityStatePostal + ' ' + postalCode.trim();
    }

    if (!String.isBlank(cityStatePostal)) {
      parts.add(cityStatePostal);
    }

    return String.join(parts, ', ');
  }

  private List<FscRelHouseholdModels.TreeAccount> buildHouseholdLinkedAccounts(
    Id householdId
  ) {
    List<FscRelHouseholdModels.TreeAccount> householdLinkedAccounts = new List<FscRelHouseholdModels.TreeAccount>();

    for (Account account : accountRepository.selectAccountsByHouseholdId(householdId)) {
      householdLinkedAccounts.add(mapAccountToTreeAccount(account));
    }

    return householdLinkedAccounts;
  }

  private List<FscRelHouseholdModels.TreeAccount> buildClientAccounts(
    Id householdId
  ) {
    List<FscRelHouseholdModels.TreeAccount> clientAccounts = new List<FscRelHouseholdModels.TreeAccount>();

    for (Account account : accountRepository.selectClientAccountsByHouseholdId(householdId)) {
      clientAccounts.add(mapAccountToTreeAccount(account));
    }

    return clientAccounts;
  }

  private List<FscRelHouseholdModels.TreeAccount> buildLeadProspectAccounts(
    Id householdId
  ) {
    List<FscRelHouseholdModels.TreeAccount> leadProspectAccounts = new List<FscRelHouseholdModels.TreeAccount>();

    for (Account account : accountRepository.selectAccountsByHouseholdId(householdId)) {
      if (FscRelClientAccountUtils.isLeadProspectAccount(account)) {
        leadProspectAccounts.add(mapAccountToTreeAccount(account));
      }
    }

    return leadProspectAccounts;
  }

  private void promoteLeadProspectRelatedAccounts(
    FscRelHouseholdModels.RelationshipTreeData data
  ) {
    if (data == null || data.relatedAccounts == null || data.relatedAccounts.isEmpty()) {
      return;
    }

    Map<Id, FscRelHouseholdModels.TreeAccount> leadProspectById = new Map<Id, FscRelHouseholdModels.TreeAccount>();

    for (FscRelHouseholdModels.TreeAccount leadProspectAccount : data.leadProspectAccounts) {
      if (String.isNotBlank(leadProspectAccount.accountId)) {
        leadProspectById.put((Id) leadProspectAccount.accountId, leadProspectAccount);
      }
    }

    List<FscRelHouseholdModels.TreeAccount> remainingRelatedAccounts = new List<FscRelHouseholdModels.TreeAccount>();

    for (FscRelHouseholdModels.TreeAccount relatedAccount : data.relatedAccounts) {
      if (String.isBlank(relatedAccount.accountId)) {
        continue;
      }

      if (
        FscRelClientAccountUtils.isLeadProspectAccount(
          relatedAccount.recordTypeLabel,
          relatedAccount.recordTypeDeveloperName,
          relatedAccount.accountType
        )
      ) {
        Id accountId = (Id) relatedAccount.accountId;

        if (!leadProspectById.containsKey(accountId)) {
          leadProspectById.put(accountId, relatedAccount);
        }

        continue;
      }

      remainingRelatedAccounts.add(relatedAccount);
    }

    data.leadProspectAccounts = leadProspectById.values();
    data.relatedAccounts = remainingRelatedAccounts;
  }

  private FscRelHouseholdModels.TreeAccount mapAccountToTreeAccount(Account account) {
    FscRelHouseholdModels.TreeAccount treeAccount = new FscRelHouseholdModels.TreeAccount();
    treeAccount.accountId = String.valueOf(account.Id);
    treeAccount.name = account.Name;
    treeAccount.roles = new List<String>();
    treeAccount.recordTypeDeveloperName = account.RecordType == null
      ? null
      : account.RecordType.DeveloperName;
    treeAccount.recordTypeLabel = account.RecordType == null
      ? null
      : account.RecordType.Name;
    treeAccount.accountType = account.Type;
    treeAccount.isPersonAccount = account.IsPersonAccount == true;
    treeAccount.contactId = account.PersonContactId == null
      ? null
      : String.valueOf(account.PersonContactId);
    treeAccount.classifications = FscRelClassificationUtils.parseClassifications(
      account.Classification__c
    );
    return treeAccount;
  }

  private List<FscRelHouseholdModels.TreeAccount> buildClassifiedAccounts(
    Id householdId,
    List<FscRelHouseholdModels.TreeAccount> clientAccounts,
    List<FscRelHouseholdModels.TreeAccount> relatedAccounts
  ) {
    Map<Id, FscRelHouseholdModels.TreeAccount> classifiedAccountById = new Map<Id, FscRelHouseholdModels.TreeAccount>();
    Map<Id, String> relationIdByAccountId = new Map<Id, String>();
    Set<Id> clientAccountIds = new Set<Id>();
    Set<Id> candidateAccountIds = new Set<Id>();

    for (FscRelHouseholdModels.TreeAccount clientAccount : clientAccounts) {
      if (String.isNotBlank(clientAccount.accountId)) {
        clientAccountIds.add((Id) clientAccount.accountId);
      }
    }

    for (FscRelHouseholdModels.TreeAccount relatedAccount : relatedAccounts) {
      if (String.isBlank(relatedAccount.accountId)) {
        continue;
      }

      Id accountId = (Id) relatedAccount.accountId;

      if (clientAccountIds.contains(accountId)) {
        continue;
      }

      candidateAccountIds.add(accountId);

      if (String.isNotBlank(relatedAccount.relationId)) {
        relationIdByAccountId.put(accountId, relatedAccount.relationId);
      }
    }

    if (householdId != null) {
      for (Account account : accountRepository.selectAccountsByHouseholdId(householdId)) {
        if (FscRelClientAccountUtils.isClientAccount(account)) {
          continue;
        }

        candidateAccountIds.add(account.Id);
      }
    }

    for (
      Account account : accountRepository.selectAccountsByIdsWithClassifications(
        candidateAccountIds
      )
    ) {
      if (clientAccountIds.contains(account.Id)) {
        continue;
      }

      if (!hasHouseholdScopedClassification(account)) {
        continue;
      }

      FscRelHouseholdModels.TreeAccount treeAccount = mapAccountToTreeAccount(account);

      if (relationIdByAccountId.containsKey(account.Id)) {
        treeAccount.relationId = relationIdByAccountId.get(account.Id);
      }

      classifiedAccountById.put(account.Id, treeAccount);
    }

    return classifiedAccountById.values();
  }

  private Boolean hasHouseholdScopedClassification(Account account) {
    return FscRelClassificationUtils.includesClassification(
        account,
        FscRelClassificationUtils.COI
      ) ||
      FscRelClassificationUtils.includesClassification(
        account,
        FscRelClassificationUtils.VENDOR
      ) ||
      FscRelClassificationUtils.includesClassification(
        account,
        FscRelClassificationUtils.UNCLASSIFIED
      );
  }

  private List<FscRelHouseholdModels.TreeAccount> buildRelatedAccounts(
    List<Account_Account_Relationship__c> relations
  ) {
    List<FscRelHouseholdModels.TreeAccount> accounts = new List<FscRelHouseholdModels.TreeAccount>();

    for (Account_Account_Relationship__c relation : relations) {
      if (relation.Related_Account__c == null) {
        continue;
      }

      FscRelHouseholdModels.TreeAccount account = new FscRelHouseholdModels.TreeAccount();
      account.relationId = String.valueOf(relation.Id);
      account.accountId = String.valueOf(relation.Related_Account__c);
      account.name = relation.Related_Account__r != null
        ? relation.Related_Account__r.Name
        : null;
      account.roles = FscRelRoleUtils.parseRoles(relation.Roles__c);
      account.associationType = relation.Association_Type__c;
      account.recordTypeDeveloperName = relation.Related_Account__r != null &&
        relation.Related_Account__r.RecordType != null
        ? relation.Related_Account__r.RecordType.DeveloperName
        : null;
      account.recordTypeLabel = relation.Related_Account__r != null &&
        relation.Related_Account__r.RecordType != null
        ? relation.Related_Account__r.RecordType.Name
        : null;
      account.accountType = relation.Related_Account__r != null
        ? relation.Related_Account__r.Type
        : null;
      account.isPersonAccount = relation.Related_Account__r != null &&
        relation.Related_Account__r.IsPersonAccount == true;
      accounts.add(account);
    }

    return accounts;
  }

  private List<FscRelHouseholdModels.TreeMember> buildMembersFromClientAccounts(
    List<FscRelHouseholdModels.TreeAccount> clientAccounts
  ) {
    List<FscRelHouseholdModels.TreeMember> members = new List<FscRelHouseholdModels.TreeMember>();

    if (clientAccounts == null || clientAccounts.isEmpty()) {
      return members;
    }

    for (FscRelHouseholdModels.TreeAccount clientAccount : clientAccounts) {
      if (clientAccount.isPersonAccount != true) {
        continue;
      }

      FscRelHouseholdModels.TreeMember member = new FscRelHouseholdModels.TreeMember();
      member.relationId = clientAccount.relationId;
      member.accountId = clientAccount.accountId;
      member.contactId = clientAccount.contactId;
      member.name = clientAccount.name;
      member.roles = clientAccount.roles == null
        ? new List<String>()
        : clientAccount.roles;
      member.isPrimaryMember = false;
      member.isPrimaryGroup = false;
      member.isActive = true;
      member.recordTypeDeveloperName = clientAccount.recordTypeDeveloperName;
      member.recordTypeLabel = clientAccount.recordTypeLabel;
      member.accountType = clientAccount.accountType;
      members.add(member);
    }

    return members;
  }

  private List<Id> parseRelationIds(List<String> relationIds) {
    List<Id> ids = new List<Id>();

    for (String rawId : relationIds) {
      if (String.isBlank(rawId)) {
        continue;
      }

      try {
        ids.add(Id.valueOf(rawId));
      } catch (Exception ignored) {
        // Skip malformed ids.
      }
    }

    return ids;
  }

  public List<FscRelHouseholdModels.RecordTypeOption> getMemberRelationshipRecordTypes() {
    return FscRelRecordTypeUtils.selectActiveAccountRelationRecordTypes();
  }

  public List<FscRelHouseholdModels.TreeMemberAccountRelationship> getMemberAccountRelationships(
    Id memberAccountId,
    String recordTypeDeveloperName
  ) {
    if (memberAccountId == null || String.isBlank(recordTypeDeveloperName)) {
      return new List<FscRelHouseholdModels.TreeMemberAccountRelationship>();
    }

    Id recordTypeId = FscRelRecordTypeUtils.selectAccountRelationRecordTypeId(
      recordTypeDeveloperName
    );
    if (recordTypeId == null) {
      return new List<FscRelHouseholdModels.TreeMemberAccountRelationship>();
    }

    List<FscRelHouseholdModels.TreeMemberAccountRelationship> results = new List<FscRelHouseholdModels.TreeMemberAccountRelationship>();
    Map<String, FscRelHouseholdModels.TreeMemberAccountRelationship> relationIdToRow = new Map<String, FscRelHouseholdModels.TreeMemberAccountRelationship>();
    Set<String> outgoingPairKeys = new Set<String>();

    for (
      Account_Account_Relationship__c relation : FscRelAccountRelationVisibilityService.selectVisibleByAccountAndRecordType(
        memberAccountId,
        recordTypeId
      )
    ) {
      if (relation.Active__c != true) {
        continue;
      }

      outgoingPairKeys.add(
        buildMemberRelationPairKey(
          memberAccountId,
          relation.Related_Account__c,
          relation.RecordTypeId
        )
      );
      relationIdToRow.put(
        String.valueOf(relation.Id),
        mapMemberAccountRelationship(relation)
      );
    }

    for (
      Account_Account_Relationship__c relation : FscRelAccountRelationVisibilityService.selectVisibleByRelatedAccountAndRecordType(
        memberAccountId,
        recordTypeId
      )
    ) {
      if (relation.Active__c != true) {
        continue;
      }

      String pairKey = buildMemberRelationPairKey(
        memberAccountId,
        relation.Account__c,
        relation.RecordTypeId
      );

      if (outgoingPairKeys.contains(pairKey)) {
        continue;
      }

      relationIdToRow.put(
        String.valueOf(relation.Id),
        mapIncomingMemberAccountRelationship(relation, memberAccountId)
      );
    }

    results.addAll(relationIdToRow.values());
    return results;
  }

  public List<FscRelHouseholdModels.TreeMemberAccountRelationship> getMemberAccountRelationshipsForAccounts(
    Set<Id> accountIds
  ) {
    if (accountIds == null || accountIds.isEmpty()) {
      return new List<FscRelHouseholdModels.TreeMemberAccountRelationship>();
    }

    Map<Id, Map<String, FscRelHouseholdModels.TreeMemberAccountRelationship>> accountIdToRelationIdToRow = new Map<Id, Map<String, FscRelHouseholdModels.TreeMemberAccountRelationship>>();
    Map<Id, Set<String>> accountIdToOutgoingPairKeys = new Map<Id, Set<String>>();

    for (
      Account_Account_Relationship__c relation : FscRelAccountRelationVisibilityService.selectVisibleByAccountIds(
        accountIds
      )
    ) {
      if (relation.Active__c != true) {
        continue;
      }

      addOutgoingMemberAccountRelationship(
        accountIdToRelationIdToRow,
        accountIdToOutgoingPairKeys,
        relation
      );
    }

    for (
      Account_Account_Relationship__c relation : FscRelAccountRelationVisibilityService.selectVisibleByRelatedAccountIds(
        accountIds
      )
    ) {
      if (relation.Active__c != true) {
        continue;
      }

      addIncomingMemberAccountRelationship(
        accountIdToRelationIdToRow,
        accountIdToOutgoingPairKeys,
        relation
      );
    }

    List<FscRelHouseholdModels.TreeMemberAccountRelationship> results = new List<FscRelHouseholdModels.TreeMemberAccountRelationship>();
    for (Map<String, FscRelHouseholdModels.TreeMemberAccountRelationship> relationIdToRow : accountIdToRelationIdToRow.values()) {
      results.addAll(relationIdToRow.values());
    }

    return results;
  }

  public Map<String, Integer> getMemberAccountRelationshipCounts(List<Id> accountIds) {
    if (accountIds == null || accountIds.isEmpty()) {
      return new Map<String, Integer>();
    }

    return FscRelAccountRelationVisibilityService.selectVisibleExpansionCountsByAccountIds(
      new Set<Id>(accountIds)
    );
  }

  public Map<String, Integer> getAccountMemberCounts(List<Id> accountIds) {
    if (accountIds == null || accountIds.isEmpty()) {
      return new Map<String, Integer>();
    }

    Map<Id, Integer> rootAccountIdToMemberCount = accountRepository.selectClientAccountCountsByHouseholdIds(
      new Set<Id>(accountIds)
    );
    Map<String, Integer> accountIdToMemberCount = new Map<String, Integer>();

    for (Id accountId : accountIds) {
      if (accountId == null) {
        continue;
      }

      accountIdToMemberCount.put(
        String.valueOf(accountId),
        rootAccountIdToMemberCount.containsKey(accountId)
          ? rootAccountIdToMemberCount.get(accountId)
          : 0
      );
    }

    return accountIdToMemberCount;
  }

  public Integer getHouseholdFamilyCardCount(List<Id> memberAccountIds) {
    if (memberAccountIds == null || memberAccountIds.isEmpty()) {
      return 0;
    }

    return accountRelationRepository.selectDistinctFamilyContactCountByMemberAccountIds(
      new Set<Id>(memberAccountIds)
    );
  }

  public Integer getHouseholdNetworkCardCount(List<Id> memberAccountIds) {
    if (memberAccountIds == null || memberAccountIds.isEmpty()) {
      return 0;
    }

    return accountRelationRepository.selectDistinctNetworkContactCountByMemberAccountIds(
      new Set<Id>(memberAccountIds)
    );
  }

  public FscRelHouseholdModels.MemberAccountRelationshipsSaveResult saveMemberAccountRelationships(
    Id memberAccountId,
    String recordTypeDeveloperName,
    List<FscRelHouseholdModels.TreeMemberAccountRelationshipInput> relationships
  ) {
    if (memberAccountId == null) {
      return new FscRelHouseholdModels.MemberAccountRelationshipsSaveResult(
        false,
        'Member account is required.',
        0
      );
    }

    if (String.isBlank(recordTypeDeveloperName)) {
      return new FscRelHouseholdModels.MemberAccountRelationshipsSaveResult(
        false,
        'Record type is required.',
        0
      );
    }

    Id recordTypeId = FscRelRecordTypeUtils.selectAccountRelationRecordTypeId(
      recordTypeDeveloperName
    );
    Id reciprocalRoleRecordTypeId = FscRelRecordTypeUtils.selectReciprocalRoleRecordTypeId(
      recordTypeDeveloperName
    );

    if (recordTypeId == null) {
      return new FscRelHouseholdModels.MemberAccountRelationshipsSaveResult(
        false,
        'Record type is not available.',
        0
      );
    }

    if (relationships == null || relationships.isEmpty()) {
      return new FscRelHouseholdModels.MemberAccountRelationshipsSaveResult(
        true,
        'Nothing to save.',
        0
      );
    }

    Map<String, FscRelHouseholdModels.TreeMemberAccountRelationshipRowResult> rowKeyToResult = new Map<String, FscRelHouseholdModels.TreeMemberAccountRelationshipRowResult>();
    Map<String, List<String>> relatedAccountIdToRowKeys = new Map<String, List<String>>();
    FscRelHouseholdModels.MemberAccountRelationshipsSaveResult bulkResult = new FscRelHouseholdModels.MemberAccountRelationshipsSaveResult(
      true,
      'Saved.',
      0
    );

    for (Integer index = 0; index < relationships.size(); index++) {
      FscRelHouseholdModels.TreeMemberAccountRelationshipInput relationship = relationships[
        index
      ];
      String rowKey = String.isBlank(relationship.rowKey)
        ? String.valueOf(index)
        : relationship.rowKey;
      FscRelHouseholdModels.TreeMemberAccountRelationshipRowResult rowResult = new FscRelHouseholdModels.TreeMemberAccountRelationshipRowResult(
        rowKey
      );
      rowResult.relatedAccountId = relationship.relatedAccountId;
      rowKeyToResult.put(rowKey, rowResult);
      bulkResult.rowResults.add(rowResult);

      List<String> rowErrors = collectMemberAccountRelationshipValidationErrors(
        memberAccountId,
        relationship,
        recordTypeId,
        reciprocalRoleRecordTypeId
      );
      if (!rowErrors.isEmpty()) {
        rowResult.success = false;
        rowResult.messages = rowErrors;
        bulkResult.success = false;
      }

      if (String.isNotBlank(relationship.relatedAccountId)) {
        if (!relatedAccountIdToRowKeys.containsKey(relationship.relatedAccountId)) {
          relatedAccountIdToRowKeys.put(
            relationship.relatedAccountId,
            new List<String>()
          );
        }
        relatedAccountIdToRowKeys.get(relationship.relatedAccountId).add(rowKey);
      }
    }

    applyDuplicateRelatedAccountErrors(
      relatedAccountIdToRowKeys,
      rowKeyToResult,
      bulkResult
    );

    if (!bulkResult.success) {
      bulkResult.message = 'Fix the highlighted rows before saving.';
      bulkResult.successCount = 0;
      return bulkResult;
    }

    Savepoint savepoint = Database.setSavepoint();
    try {
      Integer successCount = 0;
      for (Integer index = 0; index < relationships.size(); index++) {
        FscRelHouseholdModels.TreeMemberAccountRelationshipInput relationship = relationships[
          index
        ];
        String rowKey = String.isBlank(relationship.rowKey)
          ? String.valueOf(index)
          : relationship.rowKey;
        FscRelHouseholdModels.TreeMemberAccountRelationshipRowResult rowResult = rowKeyToResult.get(
          rowKey
        );
        FscRelHouseholdModels.TreeMemberAccountRelationshipRowResult persistResult = persistMemberAccountRelationship(
          memberAccountId,
          recordTypeId,
          reciprocalRoleRecordTypeId,
          relationship
        );

        if (!persistResult.success) {
          rowResult.success = false;
          rowResult.messages = persistResult.messages;
          bulkResult.success = false;
          bulkResult.message = 'Fix the highlighted rows before saving.';
          bulkResult.successCount = 0;
          Database.rollback(savepoint);
          return bulkResult;
        }

        rowResult.relationId = persistResult.relationId;
        rowResult.relatedAccountId = persistResult.relatedAccountId;
        successCount++;
      }

      bulkResult.successCount = successCount;
      bulkResult.message =
        successCount == 1
          ? 'Saved 1 relationship.'
          : 'Saved ' + successCount + ' relationships.';
      return bulkResult;
    } catch (Exception error) {
      Database.rollback(savepoint);
      return new FscRelHouseholdModels.MemberAccountRelationshipsSaveResult(
        false,
        error.getMessage(),
        0
      );
    }
  }

  public FscRelHouseholdModels.DeleteResult deleteMemberAccountRelationships(
    List<String> relationIds
  ) {
    if (relationIds == null || relationIds.isEmpty()) {
      return new FscRelHouseholdModels.DeleteResult(true, 'Nothing to delete.', 0);
    }

    List<Id> ids = parseRelationIds(relationIds);
    if (ids.isEmpty()) {
      return new FscRelHouseholdModels.DeleteResult(
        false,
        'No valid relationship ids provided.',
        0
      );
    }

    Savepoint savepoint = Database.setSavepoint();
    try {
      List<Account_Account_Relationship__c> targets = accountRelationRepository.selectByIds(
        ids
      );
      if (targets.isEmpty()) {
        return new FscRelHouseholdModels.DeleteResult(
          true,
          'No matching relationships found.',
          0
        );
      }

      List<Account_Account_Relationship__c> mirrorRelations = new List<Account_Account_Relationship__c>();
      for (Account_Account_Relationship__c relation : targets) {
        Account_Account_Relationship__c mirror = findMirrorMemberAccountRelationship(
          relation
        );
        if (mirror != null) {
          mirrorRelations.add(mirror);
        }
      }

      Integer deletedCount = accountRelationRepository.deleteRelations(targets);
      if (!mirrorRelations.isEmpty()) {
        deletedCount += accountRelationRepository.deleteRelations(mirrorRelations);
      }

      return new FscRelHouseholdModels.DeleteResult(
        true,
        'Deleted ' + deletedCount + ' relationship record(s).',
        deletedCount
      );
    } catch (Exception error) {
      Database.rollback(savepoint);
      return new FscRelHouseholdModels.DeleteResult(false, error.getMessage(), 0);
    }
  }

  private FscRelHouseholdModels.TreeMemberAccountRelationship mapMemberAccountRelationship(
    Account_Account_Relationship__c relation
  ) {
    FscRelHouseholdModels.TreeMemberAccountRelationship row = new FscRelHouseholdModels.TreeMemberAccountRelationship();
    row.relationId = String.valueOf(relation.Id);
    row.memberAccountId = relation.Account__c == null
      ? null
      : String.valueOf(relation.Account__c);
    row.relatedAccountId = relation.Related_Account__c == null
      ? null
      : String.valueOf(relation.Related_Account__c);
    row.relatedAccountName = relation.Related_Account__r?.Name;
    row.reciprocalRoleId = relation.Reciprocal_Role__c == null
      ? ''
      : String.valueOf(relation.Reciprocal_Role__c);
    row.role = relation.Reciprocal_Role__r != null
      ? FscRelReciprocalRoleRepository.resolveDisplayName(relation.Reciprocal_Role__r)
      : '';
    row.inverseReciprocalRoleId = relation.Inverse_Reciprocal_Role__c == null
      ? ''
      : String.valueOf(relation.Inverse_Reciprocal_Role__c);
    row.inverseRole = relation.Inverse_Reciprocal_Role__r != null
      ? FscRelReciprocalRoleRepository.resolveDisplayName(
          relation.Inverse_Reciprocal_Role__r
        )
      : '';
    row.recordTypeDeveloperName = FscRelRecordTypeUtils.normalizeAccountRelationRecordTypeDeveloperName(
      relation.RecordType?.DeveloperName
    );
    row.isActive = relation.Active__c == true;
    return row;
  }

  private void addOutgoingMemberAccountRelationship(
    Map<Id, Map<String, FscRelHouseholdModels.TreeMemberAccountRelationship>> accountIdToRelationIdToRow,
    Map<Id, Set<String>> accountIdToOutgoingPairKeys,
    Account_Account_Relationship__c relation
  ) {
    if (relation.Account__c == null || relation.Related_Account__c == null) {
      return;
    }

    String pairKey = buildMemberRelationPairKey(
      relation.Account__c,
      relation.Related_Account__c,
      relation.RecordTypeId
    );
    Map<String, FscRelHouseholdModels.TreeMemberAccountRelationship> relationIdToRow = getMemberRelationIdToRowMap(
      accountIdToRelationIdToRow,
      relation.Account__c
    );
    Set<String> outgoingPairKeys = getOutgoingPairKeySet(
      accountIdToOutgoingPairKeys,
      relation.Account__c
    );

    outgoingPairKeys.add(pairKey);
    relationIdToRow.put(
      String.valueOf(relation.Id),
      mapMemberAccountRelationship(relation)
    );
  }

  private void addIncomingMemberAccountRelationship(
    Map<Id, Map<String, FscRelHouseholdModels.TreeMemberAccountRelationship>> accountIdToRelationIdToRow,
    Map<Id, Set<String>> accountIdToOutgoingPairKeys,
    Account_Account_Relationship__c relation
  ) {
    if (relation.Account__c == null || relation.Related_Account__c == null) {
      return;
    }

    Id viewerAccountId = relation.Related_Account__c;
    String pairKey = buildMemberRelationPairKey(
      viewerAccountId,
      relation.Account__c,
      relation.RecordTypeId
    );
    Set<String> outgoingPairKeys = getOutgoingPairKeySet(
      accountIdToOutgoingPairKeys,
      viewerAccountId
    );

    if (outgoingPairKeys.contains(pairKey)) {
      return;
    }

    Map<String, FscRelHouseholdModels.TreeMemberAccountRelationship> relationIdToRow = getMemberRelationIdToRowMap(
      accountIdToRelationIdToRow,
      viewerAccountId
    );
    relationIdToRow.put(
      String.valueOf(relation.Id),
      mapIncomingMemberAccountRelationship(relation, viewerAccountId)
    );
  }

  private Map<String, FscRelHouseholdModels.TreeMemberAccountRelationship> getMemberRelationIdToRowMap(
    Map<Id, Map<String, FscRelHouseholdModels.TreeMemberAccountRelationship>> accountIdToRelationIdToRow,
    Id accountId
  ) {
    if (!accountIdToRelationIdToRow.containsKey(accountId)) {
      accountIdToRelationIdToRow.put(
        accountId,
        new Map<String, FscRelHouseholdModels.TreeMemberAccountRelationship>()
      );
    }

    return accountIdToRelationIdToRow.get(accountId);
  }

  private Set<String> getOutgoingPairKeySet(
    Map<Id, Set<String>> accountIdToOutgoingPairKeys,
    Id accountId
  ) {
    if (!accountIdToOutgoingPairKeys.containsKey(accountId)) {
      accountIdToOutgoingPairKeys.put(accountId, new Set<String>());
    }

    return accountIdToOutgoingPairKeys.get(accountId);
  }

  private static String buildMemberRelationPairKey(
    Id viewerAccountId,
    Id otherAccountId,
    Id recordTypeId
  ) {
    return String.valueOf(viewerAccountId) +
      ':' +
      String.valueOf(otherAccountId) +
      ':' +
      String.valueOf(recordTypeId);
  }

  private FscRelHouseholdModels.TreeMemberAccountRelationship mapIncomingMemberAccountRelationship(
    Account_Account_Relationship__c relation,
    Id viewerAccountId
  ) {
    FscRelHouseholdModels.TreeMemberAccountRelationship row = new FscRelHouseholdModels.TreeMemberAccountRelationship();
    row.relationId = String.valueOf(relation.Id);
    row.memberAccountId = String.valueOf(viewerAccountId);
    row.relatedAccountId = relation.Account__c == null
      ? null
      : String.valueOf(relation.Account__c);
    row.relatedAccountName = relation.Account__r?.Name;
    row.reciprocalRoleId = relation.Inverse_Reciprocal_Role__c == null
      ? ''
      : String.valueOf(relation.Inverse_Reciprocal_Role__c);
    row.role = relation.Inverse_Reciprocal_Role__r != null
      ? FscRelReciprocalRoleRepository.resolveDisplayName(
          relation.Inverse_Reciprocal_Role__r
        )
      : '';
    row.inverseReciprocalRoleId = relation.Reciprocal_Role__c == null
      ? ''
      : String.valueOf(relation.Reciprocal_Role__c);
    row.inverseRole = relation.Reciprocal_Role__r != null
      ? FscRelReciprocalRoleRepository.resolveDisplayName(relation.Reciprocal_Role__r)
      : '';
    row.recordTypeDeveloperName = FscRelRecordTypeUtils.normalizeAccountRelationRecordTypeDeveloperName(
      relation.RecordType?.DeveloperName
    );
    row.isActive = relation.Active__c == true;
    return row;
  }

  private List<String> collectMemberAccountRelationshipValidationErrors(
    Id memberAccountId,
    FscRelHouseholdModels.TreeMemberAccountRelationshipInput relationship,
    Id recordTypeId,
    Id reciprocalRoleRecordTypeId
  ) {
    List<String> errors = new List<String>();

    if (relationship == null) {
      errors.add('Relationship row is required.');
      return errors;
    }

    if (String.isBlank(relationship.relatedAccountId)) {
      errors.add('Related person account is required.');
      return errors;
    }

    Id relatedAccountId;
    try {
      relatedAccountId = Id.valueOf(relationship.relatedAccountId);
    } catch (Exception ignored) {
      errors.add('Related person account is invalid.');
      return errors;
    }

    if (relatedAccountId == memberAccountId) {
      errors.add('A member cannot be related to themselves.');
    }

    Account relatedAccount = accountRepository.selectById(relatedAccountId);
    if (relatedAccount == null) {
      errors.add('Related person account was not found.');
    } else if (!FscRelAccountRepository.isPersonAccountRecord(relatedAccount)) {
      errors.add('Related account must be a person account.');
    }

    if (String.isBlank(relationship.reciprocalRoleId)) {
      errors.add('Role is required.');
    }

    if (String.isBlank(relationship.inverseReciprocalRoleId)) {
      errors.add('Inverse role is required.');
    }

    if (
      reciprocalRoleRecordTypeId != null &&
      !String.isBlank(relationship.reciprocalRoleId)
    ) {
      Reciprocal_Role__c role = reciprocalRoleRepository.selectById(
        Id.valueOf(relationship.reciprocalRoleId)
      );
      if (role != null && role.RecordTypeId != reciprocalRoleRecordTypeId) {
        errors.add('Role must match the selected record type.');
      }
    }

    if (
      reciprocalRoleRecordTypeId != null &&
      !String.isBlank(relationship.inverseReciprocalRoleId)
    ) {
      Reciprocal_Role__c inverseRole = reciprocalRoleRepository.selectById(
        Id.valueOf(relationship.inverseReciprocalRoleId)
      );
      if (
        inverseRole != null &&
        inverseRole.RecordTypeId != reciprocalRoleRecordTypeId
      ) {
        errors.add('Inverse role must match the selected record type.');
      }
    }

    return errors;
  }

  private FscRelHouseholdModels.TreeMemberAccountRelationshipRowResult persistMemberAccountRelationship(
    Id memberAccountId,
    Id recordTypeId,
    Id reciprocalRoleRecordTypeId,
    FscRelHouseholdModels.TreeMemberAccountRelationshipInput relationship
  ) {
    String rowKey = String.isBlank(relationship.rowKey) ? '0' : relationship.rowKey;
    FscRelHouseholdModels.TreeMemberAccountRelationshipRowResult rowResult = new FscRelHouseholdModels.TreeMemberAccountRelationshipRowResult(
      rowKey
    );

    List<String> validationErrors = collectMemberAccountRelationshipValidationErrors(
      memberAccountId,
      relationship,
      recordTypeId,
      reciprocalRoleRecordTypeId
    );
    if (!validationErrors.isEmpty()) {
      rowResult.success = false;
      rowResult.messages = validationErrors;
      return rowResult;
    }

    Id relatedAccountId = Id.valueOf(relationship.relatedAccountId);
    Id reciprocalRoleId = Id.valueOf(relationship.reciprocalRoleId);
    Id inverseReciprocalRoleId = Id.valueOf(relationship.inverseReciprocalRoleId);
    Boolean isActive = relationship.isActive == null ? true : relationship.isActive;

    Account_Account_Relationship__c existingRelation = null;
    if (!String.isBlank(relationship.relationId)) {
      List<Account_Account_Relationship__c> existingRows = accountRelationRepository.selectByIds(
        new List<Id>{ Id.valueOf(relationship.relationId) }
      );
      existingRelation = existingRows.isEmpty() ? null : existingRows[0];
    }

    if (existingRelation == null) {
      existingRelation = accountRelationRepository.selectByAccountRelatedAccountAndRecordType(
        memberAccountId,
        relatedAccountId,
        recordTypeId
      );
    }

    Account_Account_Relationship__c savedRelation = upsertMemberAccountRelation(
      existingRelation,
      memberAccountId,
      relatedAccountId,
      recordTypeId,
      reciprocalRoleId,
      inverseReciprocalRoleId,
      isActive
    );

    syncMirrorMemberAccountRelationship(
      savedRelation,
      recordTypeId,
      isActive
    );

    rowResult.relationId = String.valueOf(savedRelation.Id);
    rowResult.relatedAccountId = String.valueOf(relatedAccountId);
    return rowResult;
  }

  private Account_Account_Relationship__c upsertMemberAccountRelation(
    Account_Account_Relationship__c existingRelation,
    Id accountId,
    Id relatedAccountId,
    Id recordTypeId,
    Id reciprocalRoleId,
    Id inverseReciprocalRoleId,
    Boolean isActive
  ) {
    if (existingRelation != null) {
      existingRelation.Related_Account__c = relatedAccountId;
      existingRelation.Reciprocal_Role__c = reciprocalRoleId;
      existingRelation.Inverse_Reciprocal_Role__c = inverseReciprocalRoleId;
      existingRelation.Active__c = isActive == true;
      existingRelation.RecordTypeId = recordTypeId;
      return accountRelationRepository.updateRelation(existingRelation);
    }

    Account_Account_Relationship__c relation = new Account_Account_Relationship__c(
      Account__c = accountId,
      Related_Account__c = relatedAccountId,
      RecordTypeId = recordTypeId,
      Reciprocal_Role__c = reciprocalRoleId,
      Inverse_Reciprocal_Role__c = inverseReciprocalRoleId,
      Active__c = isActive == true
    );
    return accountRelationRepository.insertRelation(relation);
  }

  private void syncMirrorMemberAccountRelationship(
    Account_Account_Relationship__c primaryRelation,
    Id recordTypeId,
    Boolean isActive
  ) {
    if (
      primaryRelation == null ||
      primaryRelation.Account__c == null ||
      primaryRelation.Related_Account__c == null ||
      primaryRelation.Reciprocal_Role__c == null ||
      primaryRelation.Inverse_Reciprocal_Role__c == null
    ) {
      return;
    }

    Account_Account_Relationship__c mirrorExisting = accountRelationRepository.selectByAccountRelatedAccountAndRecordType(
      primaryRelation.Related_Account__c,
      primaryRelation.Account__c,
      recordTypeId
    );

    upsertMemberAccountRelation(
      mirrorExisting,
      primaryRelation.Related_Account__c,
      primaryRelation.Account__c,
      recordTypeId,
      primaryRelation.Inverse_Reciprocal_Role__c,
      primaryRelation.Reciprocal_Role__c,
      isActive
    );
  }

  private Account_Account_Relationship__c findMirrorMemberAccountRelationship(
    Account_Account_Relationship__c relation
  ) {
    if (
      relation == null ||
      relation.Account__c == null ||
      relation.Related_Account__c == null ||
      relation.RecordTypeId == null
    ) {
      return null;
    }

    return accountRelationRepository.selectByAccountRelatedAccountAndRecordType(
      relation.Related_Account__c,
      relation.Account__c,
      relation.RecordTypeId
    );
  }

  private void applyDuplicateRelatedAccountErrors(
    Map<String, List<String>> relatedAccountIdToRowKeys,
    Map<String, FscRelHouseholdModels.TreeMemberAccountRelationshipRowResult> rowKeyToResult,
    FscRelHouseholdModels.MemberAccountRelationshipsSaveResult bulkResult
  ) {
    for (String relatedAccountId : relatedAccountIdToRowKeys.keySet()) {
      List<String> rowKeys = relatedAccountIdToRowKeys.get(relatedAccountId);
      if (rowKeys == null || rowKeys.size() <= 1) {
        continue;
      }

      for (String rowKey : rowKeys) {
        FscRelHouseholdModels.TreeMemberAccountRelationshipRowResult rowResult = rowKeyToResult.get(
          rowKey
        );
        if (rowResult == null) {
          continue;
        }

        rowResult.success = false;
        rowResult.messages = new List<String>{
          'Each related person account can only appear once.'
        };
        bulkResult.success = false;
      }
    }
  }
}