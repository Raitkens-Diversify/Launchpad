/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-21
 *
 * Service for shared household relationship tree reads.
 */
public with sharing class FscRelRelationshipTreeService {
  private static final String CATEGORY_CLIENTS = 'Clients';
  private static final String CATEGORY_FAMILY = 'Family and Friends';
  private static final String CATEGORY_NETWORK = 'Network';

  private final FscRelRelationshipTreeRepository repository;
  private final FscRelHouseholdService householdService;
  private final FscRelAccountRepository accountRepository;

  public FscRelRelationshipTreeService() {
    this(
      new FscRelRelationshipTreeRepository(),
      new FscRelHouseholdService(),
      new FscRelAccountRepository()
    );
  }

  @TestVisible
  private FscRelRelationshipTreeService(
    FscRelRelationshipTreeRepository repository,
    FscRelHouseholdService householdService,
    FscRelAccountRepository accountRepository
  ) {
    this.repository = repository;
    this.householdService = householdService;
    this.accountRepository = accountRepository;
  }

  public Id resolveHouseholdId(Id contextAccountId) {
    if (contextAccountId == null) {
      return null;
    }

    return resolveHouseholdId(accountRepository.selectById(contextAccountId));
  }

  public Id resolveHouseholdId(Account contextAccount) {
    if (contextAccount == null) {
      return null;
    }

    if (FscRelAccountRepository.isHouseholdRecordType(contextAccount)) {
      return contextAccount.Id;
    }

    if (contextAccount.Household__c != null) {
      return contextAccount.Household__c;
    }

    FscRelHouseholdModels.RootAccountResolveResult resolveResult = householdService.resolveRootAccount(
      contextAccount.Id
    );
    return resolveResult == null ? null : resolveResult.rootAccountId;
  }

  public Set<Id> buildMemberAccountIds(
    Id householdId,
    Id contextAccountId,
    Boolean isHouseholdLaunch
  ) {
    return repository.buildMemberAccountIds(
      householdId,
      contextAccountId,
      isHouseholdLaunch
    );
  }

  public List<FscRelRelationshipTreeModels.GroupedAccountContacts> getGroupedContactSuggestions(
    Id householdId,
    Id contextAccountId,
    Set<Id> selectedAccountIds,
    Boolean isHouseholdLaunch
  ) {
    Set<Id> safeSelectedIds = selectedAccountIds == null
      ? new Set<Id>()
      : selectedAccountIds;
    Set<Id> memberAccountIds = repository.buildMemberAccountIds(
      householdId,
      contextAccountId,
      isHouseholdLaunch
    );
    List<FscRelRelationshipTreeModels.GroupedAccountContacts> groups = new List<FscRelRelationshipTreeModels.GroupedAccountContacts>();

    groups.add(
      buildGroupedContacts(
        CATEGORY_CLIENTS,
        buildClientSuggestions(
          householdId,
          safeSelectedIds,
          isHouseholdLaunch,
          contextAccountId
        )
      )
    );
    groups.add(
      buildGroupedContacts(
        CATEGORY_FAMILY,
        buildAarSuggestionsFromMembers(
          memberAccountIds,
          safeSelectedIds,
          FscRelRelationshipTreeRepository.FAMILY_AAR_RECORD_TYPES
        )
      )
    );
    groups.add(
      buildGroupedContacts(
        CATEGORY_NETWORK,
        buildAarSuggestionsFromMembers(
          memberAccountIds,
          safeSelectedIds,
          FscRelRelationshipTreeRepository.NETWORK_AAR_RECORD_TYPES
        )
      )
    );

    return groups;
  }

  public Map<String, List<FscRelHouseholdModels.TreeMemberAccountRelationship>> getMemberRelationshipsByMemberAccountIds(
    Set<Id> memberAccountIds
  ) {
    List<FscRelHouseholdModels.TreeMemberAccountRelationship> relationships = householdService.getMemberAccountRelationshipsForAccounts(
      memberAccountIds
    );
    return groupRelationshipsByMemberAccountId(relationships);
  }

  private List<FscRelRelationshipTreeModels.ScopedAccountSummary> buildClientSuggestions(
    Id householdId,
    Set<Id> selectedIds,
    Boolean isHouseholdLaunch,
    Id contextAccountId
  ) {
    List<FscRelRelationshipTreeModels.ScopedAccountSummary> suggestions = new List<FscRelRelationshipTreeModels.ScopedAccountSummary>();
    Set<Id> seenAccountIds = new Set<Id>();

    if (householdId != null) {
      for (
        Account account : accountRepository.selectClientAccountsByHouseholdId(
          householdId
        )
      ) {
        if (
          account == null ||
          selectedIds.contains(account.Id) ||
          seenAccountIds.contains(account.Id) ||
          (isHouseholdLaunch != true &&
          contextAccountId != null &&
          account.Id == contextAccountId)
        ) {
          continue;
        }

        seenAccountIds.add(account.Id);
        suggestions.add(
          buildScopedAccountSummary(account.Id, account.Name, true)
        );
      }
    }

    if (
      contextAccountId != null &&
      !seenAccountIds.contains(contextAccountId) &&
      !selectedIds.contains(contextAccountId) &&
      isHouseholdLaunch != true
    ) {
      Account contextAccount = accountRepository.selectById(contextAccountId);

      if (
        contextAccount != null &&
        FscRelClientAccountUtils.isClientAccount(contextAccount)
      ) {
        suggestions.add(
          buildScopedAccountSummary(
            contextAccount.Id,
            contextAccount.Name,
            false
          )
        );
      }
    }

    return suggestions;
  }

  private List<FscRelRelationshipTreeModels.ScopedAccountSummary> buildAarSuggestionsFromMembers(
    Set<Id> memberAccountIds,
    Set<Id> selectedIds,
    Set<String> allowedRecordTypes
  ) {
    List<FscRelRelationshipTreeModels.ScopedAccountSummary> suggestions = new List<FscRelRelationshipTreeModels.ScopedAccountSummary>();
    Set<Id> seenAccountIds = new Set<Id>();
    List<FscRelHouseholdModels.TreeMemberAccountRelationship> relationships = householdService.getMemberAccountRelationshipsForAccounts(
      memberAccountIds
    );

    for (
      FscRelHouseholdModels.TreeMemberAccountRelationship relationship : relationships
    ) {
      addAarSuggestion(
        suggestions,
        seenAccountIds,
        selectedIds,
        memberAccountIds,
        relationship.relatedAccountId == null
          ? null
          : Id.valueOf(relationship.relatedAccountId),
        relationship.relatedAccountName,
        relationship.recordTypeDeveloperName,
        allowedRecordTypes
      );
    }

    return suggestions;
  }

  private void addAarSuggestion(
    List<FscRelRelationshipTreeModels.ScopedAccountSummary> suggestions,
    Set<Id> seenAccountIds,
    Set<Id> selectedIds,
    Set<Id> memberAccountIds,
    Id relatedAccountId,
    String relatedAccountName,
    String relationRecordTypeDeveloperName,
    Set<String> allowedRecordTypes
  ) {
    String normalizedRecordType = FscRelRecordTypeUtils.normalizeAccountRelationRecordTypeDeveloperName(
      relationRecordTypeDeveloperName
    );

    if (
      relatedAccountId == null ||
      memberAccountIds.contains(relatedAccountId) ||
      !allowedRecordTypes.contains(normalizedRecordType) ||
      selectedIds.contains(relatedAccountId) ||
      seenAccountIds.contains(relatedAccountId)
    ) {
      return;
    }

    seenAccountIds.add(relatedAccountId);
    suggestions.add(
      buildScopedAccountSummary(relatedAccountId, relatedAccountName, true)
    );
  }

  private Map<String, List<FscRelHouseholdModels.TreeMemberAccountRelationship>> groupRelationshipsByMemberAccountId(
    List<FscRelHouseholdModels.TreeMemberAccountRelationship> relationships
  ) {
    Map<String, List<FscRelHouseholdModels.TreeMemberAccountRelationship>> memberAccountIdToRelationships = new Map<String, List<FscRelHouseholdModels.TreeMemberAccountRelationship>>();

    if (relationships == null) {
      return memberAccountIdToRelationships;
    }

    for (
      FscRelHouseholdModels.TreeMemberAccountRelationship relationship : relationships
    ) {
      if (String.isBlank(relationship.memberAccountId)) {
        continue;
      }

      if (!memberAccountIdToRelationships.containsKey(relationship.memberAccountId)) {
        memberAccountIdToRelationships.put(
          relationship.memberAccountId,
          new List<FscRelHouseholdModels.TreeMemberAccountRelationship>()
        );
      }

      memberAccountIdToRelationships.get(relationship.memberAccountId)
        .add(relationship);
    }

    return memberAccountIdToRelationships;
  }

  private FscRelRelationshipTreeModels.GroupedAccountContacts buildGroupedContacts(
    String category,
    List<FscRelRelationshipTreeModels.ScopedAccountSummary> contacts
  ) {
    FscRelRelationshipTreeModels.GroupedAccountContacts groupedContacts = new FscRelRelationshipTreeModels.GroupedAccountContacts();
    groupedContacts.category = category;
    groupedContacts.contacts = contacts == null
      ? new List<FscRelRelationshipTreeModels.ScopedAccountSummary>()
      : contacts;
    return groupedContacts;
  }

  private FscRelRelationshipTreeModels.ScopedAccountSummary buildScopedAccountSummary(
    Id accountId,
    String name,
    Boolean isHouseholdRelated
  ) {
    FscRelRelationshipTreeModels.ScopedAccountSummary summary = new FscRelRelationshipTreeModels.ScopedAccountSummary();
    summary.accountId = formatId(accountId);
    summary.name = name;
    summary.isHouseholdRelated = isHouseholdRelated == true;
    return summary;
  }

  private String formatId(Id value) {
    return value == null ? null : String.valueOf(value);
  }
}