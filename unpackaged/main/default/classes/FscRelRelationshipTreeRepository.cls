/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-14
 *
 * Orchestration for shared household relationship tree member resolution.
 */
public with sharing class FscRelRelationshipTreeRepository {
  public static final Set<String> FAMILY_AAR_RECORD_TYPES = new Set<String>{
    FscRelRecordTypeUtils.PERSONAL_AND_FAMILY_RECORD_TYPE
  };

  public static final Set<String> NETWORK_AAR_RECORD_TYPES = new Set<String>{
    FscRelRecordTypeUtils.COI_REFERRAL_RECORD_TYPE,
    FscRelRecordTypeUtils.SERVICE_PROVIDER_RECORD_TYPE,
    FscRelRecordTypeUtils.BUSINESS_RECORD_TYPE
  };

  private final FscRelAccountRepository accountRepository;

  public FscRelRelationshipTreeRepository() {
    this(new FscRelAccountRepository());
  }

  @TestVisible
  private FscRelRelationshipTreeRepository(
    FscRelAccountRepository accountRepository
  ) {
    this.accountRepository = accountRepository;
  }

  public Set<Id> buildMemberAccountIds(
    Id householdId,
    Id contextAccountId,
    Boolean isHouseholdLaunch
  ) {
    Set<Id> memberAccountIds = new Set<Id>();

    if (isHouseholdLaunch == true && householdId != null) {
      for (
        Account clientAccount : accountRepository.selectClientAccountsByHouseholdId(
          householdId
        )
      ) {
        memberAccountIds.add(clientAccount.Id);
      }

      memberAccountIds.remove(householdId);
      return memberAccountIds;
    }

    if (householdId != null) {
      for (
        Account clientAccount : accountRepository.selectClientAccountsByHouseholdId(
          householdId
        )
      ) {
        memberAccountIds.add(clientAccount.Id);
      }
    }

    if (contextAccountId != null) {
      Account contextAccount = accountRepository.selectById(contextAccountId);

      if (
        contextAccount != null &&
        FscRelClientAccountUtils.isClientAccount(contextAccount)
      ) {
        memberAccountIds.add(contextAccountId);
      }
    }

    return memberAccountIds;
  }
}