/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-28
 *
 * Queries and normalizes household activity records for the timeline UI.
 */
public with sharing class ActivityTimelineService {
  private static final List<String> CATEGORY_ORDER = new List<String>{
    'Work',
    'Interactions'
  };

  private static final FscRelAccountRepository ACCOUNT_REPOSITORY = new FscRelAccountRepository();
  private static final SignificantEventActionService SIGNIFICANT_EVENT_SERVICE = new SignificantEventActionService();

  private static final String DIVERSIFY_RELATED_PERSON_RECORD_TYPE = 'Diversify_Related_Person';

  private static final Map<String, String> EVENT_TYPE_LABELS = new Map<String, String>{
    'Call' => 'Phone call',
    'Meeting' => 'Meeting',
    'Event' => 'Meeting',
    'Email' => 'Email',
    'Zoom' => 'Meeting',
    'Other' => 'Text/SMS'
  };

  private static final Map<String, String> TASK_SUBTYPE_LABELS = new Map<String, String>{
    'Call' => 'Phone call',
    'Email' => 'Email'
  };

  private static final Map<String, String> CHANNEL_TYPE_LABELS = new Map<String, String>{
    'Voice Call' => 'Phone call',
    'Web Chat' => 'Chat',
    'Video Call' => 'Meeting',
    'In Person' => 'Meeting'
  };

  private static final Integer QUERY_CHUNK_SIZE = 200;
  private static final Integer SOQL_LIMIT_BUFFER = 20;
  private static final Integer QUERY_ROW_SAFETY_BUFFER = 4000;
  private static final Integer DEFAULT_ACTIVITY_QUERY_LIMIT = 400;
  private static final Integer EMAIL_ACTIVITY_QUERY_LIMIT = 80;
  private static final Integer EXTERNAL_ACCOUNT_PAGE_SIZE = 75;
  private static final Integer ACCOUNT_SCOPE_QUERY_LIMIT = 10000;

  @TestVisible
  private static Integer externalAccountPageSizeOverride;
  @TestVisible
  private static Integer activityQueryLimitOverride;

  private static QueryBudget queryBudget;

  private static Boolean canContinueSoqlWork(Integer reservedQueries) {
    Integer safeReservedQueries = reservedQueries == null ? 1 : reservedQueries;
    return Limits.getQueries() + safeReservedQueries < Limits.getLimitQueries();
  }

  public ActivityTimelineModels.ActivityTimelineData getTimelineData(
    Id recordId
  ) {
    return getTimelineData(recordId, false, 0);
  }

  public ActivityTimelineModels.ActivityTimelineData getTimelineData(
    Id recordId,
    Boolean includeExternalActivities
  ) {
    return getTimelineData(recordId, includeExternalActivities, 0);
  }

  public ActivityTimelineModels.ActivityTimelineData getTimelineData(
    Id recordId,
    Boolean includeExternalActivities,
    Integer pageNumber
  ) {
    if (recordId == null) {
      throw new IllegalArgumentException('Record Id is required.');
    }

    Integer safePageNumber = pageNumber == null || pageNumber < 0 ? 0 : pageNumber;
    queryBudget = new QueryBudget();

    try {
      return buildPagedTimelineData(
        recordId,
        includeExternalActivities == true,
        safePageNumber
      );
    } finally {
      queryBudget = null;
    }
  }

  private ActivityTimelineModels.ActivityTimelineData buildPagedTimelineData(
    Id recordId,
    Boolean includeExternalActivities,
    Integer pageNumber
  ) {
    ActivityQueryScope coreScope = resolveActivityQueryScope(recordId, false);
    List<ActivityTimelineModels.ActivityItem> activities = new List<ActivityTimelineModels.ActivityItem>();

    if (pageNumber == 0) {
      activities.addAll(collectActivitiesForScope(coreScope, recordId, true));
    }

    Boolean hasMoreActivities = false;
    Integer nextPageNumber = pageNumber;

    if (includeExternalActivities) {
      ActivityQueryScope fullScope = resolveActivityQueryScope(recordId, true);
      ExternalPageSlice pageSlice = sliceExternalScope(
        coreScope,
        fullScope,
        pageNumber
      );

      if (!pageSlice.scope.isEmpty()) {
        activities.addAll(
          collectActivitiesForScope(pageSlice.scope, recordId, false)
        );
      }

      hasMoreActivities = pageSlice.hasMore;
      nextPageNumber = pageNumber + 1;
    }

    if (
      pageNumber == 0 &&
      activities.isEmpty() &&
      coreScope.isEmpty() &&
      !includeExternalActivities
    ) {
      return buildEmptyTimelineData(recordId);
    }

    activities = deduplicateActivitiesById(activities);
    activities.sort(new ActivityItemComparator());

    ActivityTimelineModels.ActivityTimelineData data = new ActivityTimelineModels.ActivityTimelineData();
    data.activities = activities;
    data.categoryCounts = buildCategoryCounts(activities);
    data.hasMoreActivities = hasMoreActivities;
    data.nextPageNumber = hasMoreActivities ? nextPageNumber : pageNumber;
    applyTimelineAccessFlags(data, recordId, includeExternalActivities);
    return data;
  }

  private List<ActivityTimelineModels.ActivityItem> collectActivitiesForScope(
    ActivityQueryScope queryScope,
    Id recordId,
    Boolean includeSignificantEvents
  ) {
    List<ActivityTimelineModels.ActivityItem> activities = new List<ActivityTimelineModels.ActivityItem>();
    if (queryScope == null || queryScope.isEmpty()) {
      return activities;
    }

    Set<Id> caseIds = budget().canRead(1)
      ? resolveCaseIds(queryScope.relatedAccountIds)
      : new Set<Id>();
    queryScope.whatIds.addAll(caseIds);
    Map<Id, String> caseNumberById = resolveCaseNumbers(caseIds);
    Set<Id> contactIds = budget().canRead(1)
      ? resolveContactIds(
          queryScope.householdIds,
          queryScope.householdId,
          queryScope.relatedAccountIds
        )
      : new Set<Id>();

    if (budget().canRead(1)) {
      activities.addAll(
        buildCaseActivities(queryScope.relatedAccountIds, caseNumberById)
      );
    }
    if (budget().canRead(1)) {
      activities.addAll(
        buildTaskActivities(queryScope.whatIds, contactIds, caseNumberById)
      );
    }
    if (budget().canRead(1)) {
      activities.addAll(
        buildEventActivities(queryScope.whatIds, contactIds, caseNumberById)
      );
    }
    if (budget().canRead(1)) {
      activities.addAll(buildEngagementActivities(contactIds));
    }
    if (budget().canRead(1)) {
      activities.addAll(buildEmailActivities(queryScope.whatIds));
    }
    if (budget().canRead(1)) {
      activities.addAll(
        buildSignificantEventActivitiesForScope(
          recordId,
          queryScope,
          includeSignificantEvents
        )
      );
    }

    return activities;
  }

  private ExternalPageSlice sliceExternalScope(
    ActivityQueryScope coreScope,
    ActivityQueryScope fullScope,
    Integer pageNumber
  ) {
    ExternalPageSlice slice = new ExternalPageSlice();
    if (fullScope == null) {
      return slice;
    }

    Set<Id> coreRelated = coreScope != null && coreScope.relatedAccountIds != null
      ? new Set<Id>(coreScope.relatedAccountIds)
      : new Set<Id>();
    Set<Id> coreWhat = coreScope != null && coreScope.whatIds != null
      ? new Set<Id>(coreScope.whatIds)
      : new Set<Id>();

    Set<Id> extraRelated = new Set<Id>();
    if (fullScope.relatedAccountIds != null) {
      extraRelated.addAll(fullScope.relatedAccountIds);
    }
    extraRelated.removeAll(coreRelated);

    List<Id> pageableIds = new List<Id>(extraRelated);
    pageableIds.sort();

    Integer pageSize = getExternalAccountPageSize();
    Integer startIndex = pageNumber * pageSize;

    if (startIndex < pageableIds.size()) {
      Integer endIndex = Math.min(startIndex + pageSize, pageableIds.size());
      slice.hasMore = endIndex < pageableIds.size();

      for (Integer index = startIndex; index < endIndex; index++) {
        Id accountId = pageableIds[index];
        slice.scope.relatedAccountIds.add(accountId);
        slice.scope.whatIds.add(accountId);
      }

      if (fullScope.householdIds != null) {
        for (Id householdId : fullScope.householdIds) {
          if (slice.scope.relatedAccountIds.contains(householdId)) {
            slice.scope.householdIds.add(householdId);
            slice.scope.householdId = householdId;
          }
        }
      }
    }

    if (pageNumber == 0) {
      addStructuralWhatIds(slice.scope, fullScope, coreWhat, extraRelated);
      if (fullScope.financialAdvisorTeamIds != null) {
        slice.scope.financialAdvisorTeamIds.addAll(
          fullScope.financialAdvisorTeamIds
        );
      }
    }

    return slice;
  }

  private static void addStructuralWhatIds(
    ActivityQueryScope pageScope,
    ActivityQueryScope fullScope,
    Set<Id> coreWhat,
    Set<Id> extraRelated
  ) {
    if (pageScope == null || fullScope == null || fullScope.whatIds == null) {
      return;
    }

    for (Id whatId : fullScope.whatIds) {
      if (coreWhat.contains(whatId) || extraRelated.contains(whatId)) {
        continue;
      }

      pageScope.whatIds.add(whatId);
    }
  }

  private static Integer getExternalAccountPageSize() {
    if (
      externalAccountPageSizeOverride != null &&
      externalAccountPageSizeOverride > 0
    ) {
      return externalAccountPageSizeOverride;
    }

    return EXTERNAL_ACCOUNT_PAGE_SIZE;
  }

  private static Integer getActivityQueryLimit() {
    if (activityQueryLimitOverride != null && activityQueryLimitOverride > 0) {
      return activityQueryLimitOverride;
    }

    return DEFAULT_ACTIVITY_QUERY_LIMIT;
  }

  private static QueryBudget budget() {
    if (queryBudget == null) {
      queryBudget = new QueryBudget();
    }

    return queryBudget;
  }

  private ActivityTimelineModels.ActivityTimelineData buildEmptyTimelineData(
    Id recordId
  ) {
    ActivityTimelineModels.ActivityTimelineData data = new ActivityTimelineModels.ActivityTimelineData();
    data.activities = new List<ActivityTimelineModels.ActivityItem>();
    data.categoryCounts = buildCategoryCounts(data.activities);
    data.hasMoreActivities = false;
    data.nextPageNumber = 0;
    applyTimelineAccessFlags(data, recordId, false);
    return data;
  }

  private void applyTimelineAccessFlags(
    ActivityTimelineModels.ActivityTimelineData data,
    Id recordId,
    Boolean includeExternalActivities
  ) {
    Boolean isHomeOfficeUser = UserInfoUtils.isCurrentUserHomeOffice();
    Boolean canUseExternalToggle =
      isHomeOfficeUser || UserInfoUtils.isCurrentUserSystemAdministrator();
    data.isHomeOfficeUser = isHomeOfficeUser;
    data.showExternalToggle =
      canUseExternalToggle && supportsExternalToggle(recordId);
    data.isHouseholdRecordContext = isHouseholdRecordContext(recordId);
    data.isDrpRecordContext = isDrpRecordContext(recordId);
    applyDrpExternalContextBranch(data, recordId, includeExternalActivities);
  }

  private static Boolean isDrpRecordContext(Id recordId) {
    if (recordId == null || recordId.getSObjectType() != Account.SObjectType) {
      return false;
    }

    return isDiversifyRelatedPersonAccount(ACCOUNT_REPOSITORY.selectById(recordId));
  }

  private void applyDrpExternalContextBranch(
    ActivityTimelineModels.ActivityTimelineData data,
    Id recordId,
    Boolean includeExternalActivities
  ) {
    if (includeExternalActivities != true || !isDrpRecordContext(recordId)) {
      return;
    }

    Set<Id> branchIds = selectBranchIdsForDrpAccount(recordId);
    if (branchIds.isEmpty()) {
      return;
    }

    List<Advisor_Group__c> branches = [
      SELECT Id, Name
      FROM Advisor_Group__c
      WHERE Id IN :branchIds
      ORDER BY Name
      LIMIT 1
    ];

    if (branches.isEmpty()) {
      return;
    }

    data.contextBranchId = String.valueOf(branches[0].Id);
    data.contextBranchName = branches[0].Name;
  }

  private void applyTimelineAccessFlags(
    ActivityTimelineModels.ActivityTimelineData data,
    Id recordId
  ) {
    applyTimelineAccessFlags(data, recordId, false);
  }

  private static Boolean isHouseholdRecordContext(Id recordId) {
    if (recordId == null || recordId.getSObjectType() != Account.SObjectType) {
      return false;
    }

    return FscRelAccountRepository.isHouseholdRecordType(
      ACCOUNT_REPOSITORY.selectById(recordId)
    );
  }

  private Boolean supportsExternalToggle(Id recordId) {
    Schema.SObjectType sobjectType = recordId.getSObjectType();

    if (sobjectType == Advisor_Group__c.SObjectType) {
      return true;
    }

    if (sobjectType == Account.SObjectType) {
      return isDiversifyRelatedPersonAccount(
        ACCOUNT_REPOSITORY.selectById(recordId)
      );
    }

    return false;
  }

  private static Boolean isDiversifyRelatedPersonAccount(Account account) {
    return account != null &&
      account.RecordType != null &&
      account.RecordType.DeveloperName == DIVERSIFY_RELATED_PERSON_RECORD_TYPE;
  }

  private static Boolean isExternalScopeAccount(Account account) {
    if (account == null) {
      return false;
    }

    if (FscRelAccountRepository.isHouseholdRecordType(account)) {
      return true;
    }

    return isTimelineEligibleAccount(account);
  }

  private Id resolveAccountContextId(Id recordId) {
    if (recordId == null) {
      return null;
    }

    Schema.SObjectType sobjectType = recordId.getSObjectType();
    if (sobjectType == Account.SObjectType) {
      return recordId;
    }

    String objectApiName = sobjectType.getDescribe().getName();

    if (objectApiName == 'Case') {
      List<Case> caseRecords = [
        SELECT AccountId
        FROM Case
        WHERE Id = :recordId
        LIMIT 1
      ];
      return caseRecords.isEmpty() ? null : caseRecords[0].AccountId;
    }

    if (objectApiName == 'Contact') {
      List<Contact> contactRecords = [
        SELECT AccountId
        FROM Contact
        WHERE Id = :recordId
        LIMIT 1
      ];
      return contactRecords.isEmpty() ? null : contactRecords[0].AccountId;
    }

    if (objectApiName == 'Opportunity') {
      List<Opportunity> opportunityRecords = [
        SELECT AccountId
        FROM Opportunity
        WHERE Id = :recordId
        LIMIT 1
      ];
      return opportunityRecords.isEmpty()
        ? null
        : opportunityRecords[0].AccountId;
    }

    if (objectApiName == 'Task') {
      List<Task> taskRecords = [
        SELECT WhatId, WhoId
        FROM Task
        WHERE Id = :recordId
        LIMIT 1
      ];
      if (taskRecords.isEmpty()) {
        return null;
      }

      Task taskRecord = taskRecords[0];
      Id accountId = resolvePolymorphicAccountId(taskRecord.WhatId);
      if (accountId != null) {
        return accountId;
      }

      return resolveContactAccountId(taskRecord.WhoId);
    }

    if (objectApiName == 'Event') {
      List<Event> eventRecords = [
        SELECT WhatId, WhoId
        FROM Event
        WHERE Id = :recordId
        LIMIT 1
      ];
      if (eventRecords.isEmpty()) {
        return null;
      }

      Event eventRecord = eventRecords[0];
      Id accountId = resolvePolymorphicAccountId(eventRecord.WhatId);
      if (accountId != null) {
        return accountId;
      }

      return resolveContactAccountId(eventRecord.WhoId);
    }

    return null;
  }

  private Id resolvePolymorphicAccountId(Id relatedRecordId) {
    if (relatedRecordId == null) {
      return null;
    }

    Schema.SObjectType relatedType = relatedRecordId.getSObjectType();
    if (relatedType == Account.SObjectType) {
      return relatedRecordId;
    }

    if (relatedType == Case.SObjectType) {
      List<Case> caseRecords = [
        SELECT AccountId
        FROM Case
        WHERE Id = :relatedRecordId
        LIMIT 1
      ];
      return caseRecords.isEmpty() ? null : caseRecords[0].AccountId;
    }

    if (relatedType == Advisor_Group__c.SObjectType) {
      return null;
    }

    return null;
  }

  private Id resolveContactAccountId(Id whoId) {
    if (whoId == null || whoId.getSObjectType() != Contact.SObjectType) {
      return null;
    }

    List<Contact> contactRecords = [
      SELECT AccountId
      FROM Contact
      WHERE Id = :whoId
      LIMIT 1
    ];
    return contactRecords.isEmpty() ? null : contactRecords[0].AccountId;
  }

  private class TimelineScope {
    Id householdId;
    Set<Id> relatedAccountIds;
  }

  private class ActivityQueryScope {
    Id householdId;
    Set<Id> householdIds = new Set<Id>();
    Set<Id> relatedAccountIds = new Set<Id>();
    Set<Id> whatIds = new Set<Id>();
    Set<Id> financialAdvisorTeamIds = new Set<Id>();

    private Boolean isEmpty() {
      return relatedAccountIds.isEmpty() &&
        whatIds.isEmpty() &&
        financialAdvisorTeamIds.isEmpty();
    }
  }

  private class ExternalPageSlice {
    ActivityQueryScope scope = new ActivityQueryScope();
    Boolean hasMore = false;
  }

  private class QueryBudget {
    Boolean truncated = false;

    Integer remainingRows() {
      return Limits.getLimitQueryRows() -
        Limits.getQueryRows() -
        QUERY_ROW_SAFETY_BUFFER;
    }

    Integer nextLimit(Integer preferred) {
      Integer remaining = remainingRows();
      if (remaining <= 0) {
        truncated = true;
        return 0;
      }

      Integer cap = preferred == null || preferred <= 0
        ? DEFAULT_ACTIVITY_QUERY_LIMIT
        : preferred;
      Integer rowLimit = Math.min(cap, remaining);
      if (rowLimit <= 0) {
        truncated = true;
        return 0;
      }

      return rowLimit;
    }

    Boolean canRead(Integer minimumRows) {
      Integer requiredRows = minimumRows == null ? 1 : minimumRows;
      if (!canContinueSoqlWork(1)) {
        truncated = true;
        return false;
      }

      if (remainingRows() < requiredRows) {
        truncated = true;
        return false;
      }

      return true;
    }

    void markTruncatedIfFull(Integer requestedLimit, Integer returnedSize) {
      if (
        requestedLimit != null &&
        requestedLimit > 0 &&
        returnedSize != null &&
        returnedSize >= requestedLimit
      ) {
        truncated = true;
      }
    }
  }

  private ActivityQueryScope resolveActivityQueryScope(
    Id recordId,
    Boolean includeExternalActivities
  ) {
    ActivityQueryScope scope = new ActivityQueryScope();
    Schema.SObjectType sobjectType = recordId.getSObjectType();

    if (sobjectType == Advisor_Group__c.SObjectType) {
      resolveBranchScope(recordId, scope, includeExternalActivities);
      return scope;
    }

    if (sobjectType == Account.SObjectType) {
      Account account = ACCOUNT_REPOSITORY.selectById(recordId);
      if (isDiversifyRelatedPersonAccount(account)) {
        resolveDrpScope(recordId, scope, includeExternalActivities);
        return scope;
      }
    }

    Id accountContextId = resolveAccountContextId(recordId);
    if (accountContextId != null) {
      TimelineScope timelineScope = resolveTimelineScope(accountContextId);
      scope.householdId = timelineScope.householdId;
      if (timelineScope.householdId != null) {
        scope.householdIds.add(timelineScope.householdId);
      }
      scope.relatedAccountIds.addAll(timelineScope.relatedAccountIds);
      scope.whatIds.addAll(timelineScope.relatedAccountIds);
    }

    if (supportsDirectActivityRelation(sobjectType)) {
      scope.whatIds.add(recordId);
    }

    return scope;
  }

  private void resolveBranchScope(
    Id branchId,
    ActivityQueryScope scope,
    Boolean includeExternalActivities
  ) {
    scope.whatIds.add(branchId);
    Set<Id> drpAccountIds = addBranchMemberDrpAccountsToScope(scope, branchId);

    if (includeExternalActivities) {
      addBranchExternalActivitiesScope(scope, branchId, drpAccountIds);
    }
  }

  private void resolveDrpScope(
    Id drpAccountId,
    ActivityQueryScope scope,
    Boolean includeExternalActivities
  ) {
    scope.whatIds.add(drpAccountId);
    scope.relatedAccountIds.add(drpAccountId);

    if (includeExternalActivities) {
      addExternalHouseholdScope(scope, new Set<Id>{ drpAccountId });
      addLinkedBranchExternalScopeForDrp(scope, drpAccountId);
    }
  }

  private void addLinkedBranchExternalScopeForDrp(
    ActivityQueryScope scope,
    Id drpAccountId
  ) {
    Set<Id> branchIds = selectBranchIdsForDrpAccount(drpAccountId);
    if (branchIds.isEmpty()) {
      return;
    }

    if (!canContinueSoqlWork(SOQL_LIMIT_BUFFER)) {
      return;
    }

    scope.whatIds.addAll(branchIds);

    Map<Id, Set<Id>> drpAccountIdsByBranchId = selectDrpAccountIdsByBranchIds(
      branchIds
    );
    Set<Id> allBranchDrpAccountIds = new Set<Id>();

    for (Set<Id> branchDrpAccountIds : drpAccountIdsByBranchId.values()) {
      for (Id branchDrpAccountId : branchDrpAccountIds) {
        scope.whatIds.add(branchDrpAccountId);
        scope.relatedAccountIds.add(branchDrpAccountId);
        allBranchDrpAccountIds.add(branchDrpAccountId);
      }
    }

    if (!allBranchDrpAccountIds.isEmpty()) {
      addExternalHouseholdScope(scope, allBranchDrpAccountIds);
    }

    addBranchFinancialAdvisorTeamAccountScopeBulk(scope, branchIds);
  }

  private static Set<Id> selectBranchIdsForDrpAccount(Id drpAccountId) {
    Set<Id> branchIds = new Set<Id>();

    if (drpAccountId == null) {
      return branchIds;
    }

    for (Advisor_Group_Member__c member : [
      SELECT Advisor_Group__c
      FROM Advisor_Group_Member__c
      WHERE
        Diversify_Related_Person__c = :drpAccountId
        AND Advisor_Group__c != NULL
    ]) {
      branchIds.add(member.Advisor_Group__c);
    }

    return branchIds;
  }

  private static Map<Id, Set<Id>> selectDrpAccountIdsByBranchIds(Set<Id> branchIds) {
    Map<Id, Set<Id>> drpAccountIdsByBranchId = new Map<Id, Set<Id>>();

    if (branchIds == null || branchIds.isEmpty()) {
      return drpAccountIdsByBranchId;
    }

    for (Advisor_Group_Member__c member : [
      SELECT Advisor_Group__c, Diversify_Related_Person__c
      FROM Advisor_Group_Member__c
      WHERE
        Advisor_Group__c IN :branchIds
        AND Diversify_Related_Person__c != NULL
    ]) {
      if (!drpAccountIdsByBranchId.containsKey(member.Advisor_Group__c)) {
        drpAccountIdsByBranchId.put(
          member.Advisor_Group__c,
          new Set<Id>()
        );
      }

      drpAccountIdsByBranchId.get(member.Advisor_Group__c)
        .add(member.Diversify_Related_Person__c);
    }

    return drpAccountIdsByBranchId;
  }

  private Set<Id> addBranchMemberDrpAccountsToScope(
    ActivityQueryScope scope,
    Id branchId
  ) {
    Set<Id> drpAccountIds = new Set<Id>();

    for (Advisor_Group_Member__c member : [
      SELECT Diversify_Related_Person__c
      FROM Advisor_Group_Member__c
      WHERE Advisor_Group__c = :branchId AND Diversify_Related_Person__c != NULL
    ]) {
      drpAccountIds.add(member.Diversify_Related_Person__c);
      scope.whatIds.add(member.Diversify_Related_Person__c);
      scope.relatedAccountIds.add(member.Diversify_Related_Person__c);
    }

    return drpAccountIds;
  }

  private void addBranchExternalActivitiesScope(
    ActivityQueryScope scope,
    Id branchId,
    Set<Id> drpAccountIds
  ) {
    addExternalHouseholdScope(scope, drpAccountIds);
    addBranchFinancialAdvisorTeamAccountScope(scope, branchId);
  }

  private void addExternalHouseholdScope(
    ActivityQueryScope scope,
    Set<Id> anchorAccountIds
  ) {
    if (anchorAccountIds == null || anchorAccountIds.isEmpty()) {
      return;
    }

    if (!canContinueSoqlWork(SOQL_LIMIT_BUFFER)) {
      return;
    }

    Set<Id> accountIdsToAdd = new Set<Id>();
    Map<Id, TimelineScope> scopesByAnchorId = resolveTimelineScopesBulk(
      anchorAccountIds,
      true
    );

    for (TimelineScope timelineScope : scopesByAnchorId.values()) {
      if (timelineScope.householdId != null) {
        scope.householdId = timelineScope.householdId;
        scope.householdIds.add(timelineScope.householdId);
        accountIdsToAdd.add(timelineScope.householdId);
      }

      accountIdsToAdd.addAll(timelineScope.relatedAccountIds);
    }

    addExternalAccountsToScope(scope, accountIdsToAdd);
  }

  private void addBranchFinancialAdvisorTeamAccountScope(
    ActivityQueryScope scope,
    Id branchId
  ) {
    addBranchFinancialAdvisorTeamAccountScopeBulk(
      scope,
      new Set<Id>{ branchId }
    );
  }

  private void addBranchFinancialAdvisorTeamAccountScopeBulk(
    ActivityQueryScope scope,
    Set<Id> branchIds
  ) {
    if (branchIds == null || branchIds.isEmpty()) {
      return;
    }

    if (!canContinueSoqlWork(SOQL_LIMIT_BUFFER)) {
      return;
    }

    ActivityTimelineScopeQuery scopeQuery = new ActivityTimelineScopeQuery();
    Set<Id> teamIds = scopeQuery.selectFinancialAdvisorTeamIdsByBranchIds(
      branchIds
    );
    if (teamIds.isEmpty()) {
      return;
    }

    scope.financialAdvisorTeamIds.addAll(teamIds);

    if (!canContinueSoqlWork(2)) {
      return;
    }

    for (Account account : scopeQuery.selectAccountsForBranchFinancialAdvisorTeams(
      teamIds
    )) {
      if (isHouseholdAccount(account)) {
        scope.householdIds.add(account.Id);
        scope.householdId = account.Id;
      }

      addExternalAccountToScope(scope, account);
    }
  }

  private static Boolean isHouseholdAccount(Account account) {
    return account != null &&
      account.RecordType != null &&
      FscRelAccountRepository.isHouseholdRecordTypeDeveloperName(
        account.RecordType.DeveloperName
      );
  }

  private void addExternalAccountsToScope(
    ActivityQueryScope scope,
    Set<Id> accountIds
  ) {
    if (accountIds == null || accountIds.isEmpty()) {
      return;
    }

    Set<Id> pendingAccountIds = new Set<Id>();
    for (Id accountId : accountIds) {
      if (accountId != null && !scope.relatedAccountIds.contains(accountId)) {
        pendingAccountIds.add(accountId);
      }
    }

    if (pendingAccountIds.isEmpty()) {
      return;
    }

    for (Set<Id> accountIdChunk : chunkIdSet(pendingAccountIds)) {
      if (!canContinueSoqlWork(1)) {
        break;
      }

      for (Account account : [
        SELECT Id, RecordType.DeveloperName, RecordType.Name, Type
        FROM Account
        WHERE Id IN :accountIdChunk
      ]) {
        addExternalAccountToScope(scope, account);
      }
    }
  }

  private void addExternalAccountToScope(ActivityQueryScope scope, Id accountId) {
    if (accountId == null || scope.relatedAccountIds.contains(accountId)) {
      return;
    }

    addExternalAccountsToScope(scope, new Set<Id>{ accountId });
  }

  private void addExternalAccountToScope(
    ActivityQueryScope scope,
    Account account
  ) {
    if (account == null || account.Id == null) {
      return;
    }

    if (scope.relatedAccountIds.contains(account.Id)) {
      return;
    }

    if (!isExternalScopeAccount(account)) {
      return;
    }

    scope.whatIds.add(account.Id);
    scope.relatedAccountIds.add(account.Id);
  }

  private static Boolean supportsDirectActivityRelation(
    Schema.SObjectType sobjectType
  ) {
    return sobjectType == Account.SObjectType ||
      sobjectType == Case.SObjectType ||
      sobjectType == Opportunity.SObjectType;
  }

  private TimelineScope resolveTimelineScope(Id accountId) {
    Map<Id, TimelineScope> scopesByAccountId = resolveTimelineScopesBulk(
      new Set<Id>{ accountId },
      false
    );
    TimelineScope scope = scopesByAccountId.get(accountId);
    return scope != null ? scope : newEmptyTimelineScope();
  }

  private Map<Id, TimelineScope> resolveTimelineScopesBulk(Set<Id> accountIds) {
    return resolveTimelineScopesBulk(accountIds, false);
  }

  private Map<Id, TimelineScope> resolveTimelineScopesBulk(
    Set<Id> accountIds,
    Boolean includeRelatedHouseholdMembers
  ) {
    Map<Id, TimelineScope> scopesByAccountId = new Map<Id, TimelineScope>();

    if (accountIds == null || accountIds.isEmpty()) {
      return scopesByAccountId;
    }

    Map<Id, Account> accountById = new Map<Id, Account>();
    for (Set<Id> accountIdChunk : chunkIdSet(accountIds)) {
      if (!canContinueSoqlWork(1)) {
        break;
      }

      for (Account account : selectAccountsForTimelineScope(accountIdChunk)) {
        accountById.put(account.Id, account);
      }
    }

    Set<Id> householdIdsNeedingMembers = new Set<Id>();

    for (Id accountId : accountIds) {
      TimelineScope scope = newEmptyTimelineScope();
      Account account = accountById.get(accountId);

      if (account == null) {
        scopesByAccountId.put(accountId, scope);
        continue;
      }

      Id householdId = resolveHouseholdId(account);

      if (FscRelAccountRepository.isHouseholdRecordType(account)) {
        scope.householdId = householdId;
        scope.relatedAccountIds.add(householdId);
        householdIdsNeedingMembers.add(householdId);
      } else if (
        includeRelatedHouseholdMembers == true &&
        householdId != accountId
      ) {
        scope.householdId = householdId;
        scope.relatedAccountIds.add(householdId);
        householdIdsNeedingMembers.add(householdId);
        scope.relatedAccountIds.add(accountId);
      } else {
        scope.relatedAccountIds.add(accountId);
      }

      scopesByAccountId.put(accountId, scope);
    }

    Map<Id, List<Account>> linkedAccountsByHouseholdId = selectLinkedAccountsByHouseholdIds(
      householdIdsNeedingMembers
    );

    for (Id accountId : accountIds) {
      TimelineScope scope = scopesByAccountId.get(accountId);
      Account account = accountById.get(accountId);

      if (
        scope == null ||
        scope.householdId == null ||
        !shouldExpandLinkedHouseholdMembers(
          account,
          includeRelatedHouseholdMembers
        )
      ) {
        continue;
      }

      List<Account> linkedAccounts = linkedAccountsByHouseholdId.get(
        scope.householdId
      );

      if (linkedAccounts == null) {
        continue;
      }

      for (Account linkedAccount : linkedAccounts) {
        if (isTimelineEligibleAccount(linkedAccount)) {
          scope.relatedAccountIds.add(linkedAccount.Id);
        }
      }
    }

    return scopesByAccountId;
  }

  private static Boolean shouldExpandLinkedHouseholdMembers(
    Account account,
    Boolean includeRelatedHouseholdMembers
  ) {
    if (account == null) {
      return false;
    }

    return FscRelAccountRepository.isHouseholdRecordType(account) ||
      includeRelatedHouseholdMembers == true;
  }

  private static TimelineScope newEmptyTimelineScope() {
    TimelineScope scope = new TimelineScope();
    scope.relatedAccountIds = new Set<Id>();
    return scope;
  }

  private Map<Id, List<Account>> selectLinkedAccountsByHouseholdIds(
    Set<Id> householdIds
  ) {
    Map<Id, List<Account>> linkedAccountsByHouseholdId = new Map<Id, List<Account>>();

    if (householdIds == null || householdIds.isEmpty()) {
      return linkedAccountsByHouseholdId;
    }

    for (Set<Id> householdIdChunk : chunkIdSet(householdIds)) {
      if (!canContinueSoqlWork(1)) {
        break;
      }

      for (Account account : [
        SELECT
          Id,
          Household__c,
          RecordType.DeveloperName,
          RecordType.Name,
          Type
        FROM Account
        WHERE Household__c IN :householdIdChunk
      ]) {
        if (!linkedAccountsByHouseholdId.containsKey(account.Household__c)) {
          linkedAccountsByHouseholdId.put(
            account.Household__c,
            new List<Account>()
          );
        }

        linkedAccountsByHouseholdId.get(account.Household__c).add(account);
      }
    }

    return linkedAccountsByHouseholdId;
  }

  private static List<Account> selectAccountsForTimelineScope(Set<Id> accountIds) {
    if (accountIds == null || accountIds.isEmpty()) {
      return new List<Account>();
    }

    return [
      SELECT
        Id,
        Household__c,
        Type,
        RecordType.DeveloperName,
        RecordType.Name
      FROM Account
      WHERE Id IN :accountIds
    ];
  }

  private static Id resolveHouseholdId(Account account) {
    if (FscRelAccountRepository.isHouseholdRecordType(account)) {
      return account.Id;
    }

    if (account.Household__c != null) {
      return account.Household__c;
    }

    return account.Id;
  }

  private static void addLinkedHouseholdAccounts(
    Set<Id> relatedAccountIds,
    Id householdId
  ) {
    for (Account account : ACCOUNT_REPOSITORY.selectAccountsByHouseholdId(householdId)) {
      if (isTimelineEligibleAccount(account)) {
        relatedAccountIds.add(account.Id);
      }
    }
  }

  private static Boolean isTimelineEligibleAccount(Account account) {
    if (account == null || account.RecordType == null) {
      return false;
    }

    return FscRelClientAccountUtils.isClientRecordType(
      account.RecordType.Name,
      account.RecordType.DeveloperName
    );
  }

  private static Set<Id> resolveContactIds(
    Set<Id> householdIds,
    Id householdId,
    Set<Id> relatedAccountIds
  ) {
    Set<Id> contactIds = new Set<Id>();
    Set<Id> effectiveHouseholdIds = householdIds == null
      ? new Set<Id>()
      : new Set<Id>(householdIds);

    if (householdId != null) {
      effectiveHouseholdIds.add(householdId);
    }

    if (!effectiveHouseholdIds.isEmpty()) {
      for (Set<Id> householdIdChunk : chunkIdSet(effectiveHouseholdIds)) {
        if (!budget().canRead(1)) {
          break;
        }

        Integer rowLimit = budget().nextLimit(ACCOUNT_SCOPE_QUERY_LIMIT);
        if (rowLimit <= 0) {
          break;
        }

        List<AccountContactRelation> relations = [
          SELECT ContactId
          FROM AccountContactRelation
          WHERE AccountId IN :householdIdChunk AND IsActive = TRUE
          LIMIT :rowLimit
        ];
        budget().markTruncatedIfFull(rowLimit, relations.size());

        for (AccountContactRelation relation : relations) {
          contactIds.add(relation.ContactId);
        }
      }
    }

    if (relatedAccountIds == null || relatedAccountIds.isEmpty()) {
      return contactIds;
    }

    for (Set<Id> accountIdChunk : chunkIdSet(relatedAccountIds)) {
      if (!budget().canRead(2)) {
        break;
      }

      for (Account account : [
        SELECT PersonContactId
        FROM Account
        WHERE Id IN :accountIdChunk AND PersonContactId != NULL
      ]) {
        contactIds.add(account.PersonContactId);
      }

      if (!budget().canRead(1)) {
        break;
      }

      Integer rowLimit = budget().nextLimit(ACCOUNT_SCOPE_QUERY_LIMIT);
      if (rowLimit <= 0) {
        break;
      }

      List<AccountContactRelation> relations = [
        SELECT ContactId
        FROM AccountContactRelation
        WHERE AccountId IN :accountIdChunk AND IsActive = TRUE
        LIMIT :rowLimit
      ];
      budget().markTruncatedIfFull(rowLimit, relations.size());

      for (AccountContactRelation relation : relations) {
        contactIds.add(relation.ContactId);
      }
    }

    return contactIds;
  }

  private static Set<Id> resolveCaseIds(Set<Id> accountIds) {
    Set<Id> caseIds = new Set<Id>();

    if (accountIds == null || accountIds.isEmpty()) {
      return caseIds;
    }

    for (Set<Id> accountIdChunk : chunkIdSet(accountIds)) {
      if (!budget().canRead(1)) {
        break;
      }

      Integer rowLimit = budget().nextLimit(getActivityQueryLimit());
      if (rowLimit <= 0) {
        break;
      }

      List<Case> caseRecords = [
        SELECT Id
        FROM Case
        WHERE AccountId IN :accountIdChunk
        ORDER BY CreatedDate DESC
        LIMIT :rowLimit
      ];
      budget().markTruncatedIfFull(rowLimit, caseRecords.size());

      for (Case caseRecord : caseRecords) {
        caseIds.add(caseRecord.Id);
      }
    }

    return caseIds;
  }

  private static Map<Id, String> resolveCaseNumbers(Set<Id> caseIds) {
    Map<Id, String> caseNumberById = new Map<Id, String>();
    if (caseIds.isEmpty()) {
      return caseNumberById;
    }

    for (Case caseRecord : [
      SELECT Id, CaseNumber
      FROM Case
      WHERE Id IN :caseIds
    ]) {
      caseNumberById.put(caseRecord.Id, caseRecord.CaseNumber);
    }
    return caseNumberById;
  }

  private static List<ActivityTimelineModels.ActivityItem> buildCaseActivities(
    Set<Id> accountIds,
    Map<Id, String> caseNumberById
  ) {
    List<ActivityTimelineModels.ActivityItem> items = new List<ActivityTimelineModels.ActivityItem>();

    if (accountIds == null || accountIds.isEmpty()) {
      return items;
    }

    List<Case> caseRecords = new List<Case>();
    for (Set<Id> accountIdChunk : chunkIdSet(accountIds)) {
      if (!budget().canRead(1)) {
        break;
      }

      Integer rowLimit = budget().nextLimit(getActivityQueryLimit());
      if (rowLimit <= 0) {
        break;
      }

      List<Case> chunkRecords = [
        SELECT
          Id,
          Subject,
          Status,
          Description,
          CreatedDate,
          Priority,
          OwnerId,
          Owner.Name,
          CaseNumber,
          AccountId
        FROM Case
        WHERE AccountId IN :accountIdChunk
        ORDER BY CreatedDate DESC
        LIMIT :rowLimit
      ];
      budget().markTruncatedIfFull(rowLimit, chunkRecords.size());
      caseRecords.addAll(chunkRecords);
    }

    Set<Id> associatedAccountIds = new Set<Id>();
    for (Case caseRecord : caseRecords) {
      if (caseRecord.AccountId != null) {
        associatedAccountIds.add(caseRecord.AccountId);
      }
    }

    Map<Id, String> accountNameById = resolveAccountNamesById(associatedAccountIds);

    for (Case caseRecord : caseRecords) {
      ActivityTimelineModels.ActivityItem item = buildItem(
        caseRecord.Id,
        caseRecord.CreatedDate,
        caseRecord.Subject,
        'Case',
        'Work',
        caseRecord.Status,
        caseRecord.Description,
        caseRecord.OwnerId,
        caseRecord.Owner?.Name,
        new List<ActivityTimelineModels.Participant>(),
        null,
        resolveActivityIcon('Case')
      );
      applyAssociatedAccountReference(
        item,
        caseRecord.AccountId,
        accountNameById
      );
      items.add(item);
    }

    return items;
  }

  private static List<ActivityTimelineModels.ActivityItem> buildTaskActivities(
    Set<Id> whatIds,
    Set<Id> whoIds,
    Map<Id, String> caseNumberById
  ) {
    List<ActivityTimelineModels.ActivityItem> items = new List<ActivityTimelineModels.ActivityItem>();
    List<Task> taskRecords = queryTasksByRelation(whatIds, whoIds);
    Set<Id> linkedWhatIds = new Set<Id>();

    for (Task taskRecord : taskRecords) {
      if (taskRecord.WhatId != null) {
        linkedWhatIds.add(taskRecord.WhatId);
      }
    }

    Map<Id, LinkedRecordContext> linkedRecordByWhatId = buildLinkedRecordContextForWhatIds(
      linkedWhatIds,
      caseNumberById
    );
    Set<Id> associatedAccountIds = new Set<Id>();

    for (Task taskRecord : taskRecords) {
      if (taskRecord.AccountId != null) {
        associatedAccountIds.add(taskRecord.AccountId);
      }
    }

    Map<Id, String> accountNameById = resolveAccountNamesById(associatedAccountIds);

    for (Task taskRecord : taskRecords) {
      Datetime activityDateTime = resolveTaskActivityDateTime(taskRecord);

      List<ActivityTimelineModels.Participant> relatedParticipants = new List<ActivityTimelineModels.Participant>();
      addParticipant(
        relatedParticipants,
        taskRecord.WhoId,
        taskRecord.Who?.Name
      );

      String activityType = resolveTaskActivityType(taskRecord.TaskSubtype);
      ActivityTimelineModels.ActivityItem item = buildItem(
        taskRecord.Id,
        activityDateTime,
        taskRecord.Subject,
        activityType,
        resolveActivityCategory(activityType),
        taskRecord.Status,
        taskRecord.Description,
        taskRecord.OwnerId,
        taskRecord.Owner?.Name,
        relatedParticipants,
        null,
        resolveActivityIcon(activityType)
      );
      applyLinkedRecordReference(item, taskRecord.WhatId, linkedRecordByWhatId);
      applyAssociatedAccountReference(item, taskRecord.AccountId, accountNameById);
      item.hasDueDate = taskRecord.ActivityDate != null;
      items.add(item);
    }

    return items;
  }

  private static List<ActivityTimelineModels.ActivityItem> buildEventActivities(
    Set<Id> whatIds,
    Set<Id> whoIds,
    Map<Id, String> caseNumberById
  ) {
    List<ActivityTimelineModels.ActivityItem> items = new List<ActivityTimelineModels.ActivityItem>();
    List<Event> eventRecords = queryEventsByRelation(whatIds, whoIds);

    Set<Id> eventIds = new Map<Id, Event>(eventRecords).keySet();
    Map<Id, List<ActivityTimelineModels.Participant>> relatedParticipantsByEventId = resolveEventRelatedParticipantsByEventId(
      eventIds
    );
    Set<Id> linkedWhatIds = new Set<Id>();

    for (Event eventRecord : eventRecords) {
      if (eventRecord.WhatId != null) {
        linkedWhatIds.add(eventRecord.WhatId);
      }
    }

    Map<Id, LinkedRecordContext> linkedRecordByWhatId = buildLinkedRecordContextForWhatIds(
      linkedWhatIds,
      caseNumberById
    );
    Set<Id> associatedAccountIds = new Set<Id>();

    for (Event eventRecord : eventRecords) {
      if (eventRecord.AccountId != null) {
        associatedAccountIds.add(eventRecord.AccountId);
      }
    }

    Map<Id, String> accountNameById = resolveAccountNamesById(associatedAccountIds);

    for (Event eventRecord : eventRecords) {
      String activityType = resolveEventActivityType(eventRecord.Type);

      List<ActivityTimelineModels.Participant> relatedParticipants = new List<ActivityTimelineModels.Participant>();
      addParticipant(
        relatedParticipants,
        eventRecord.WhoId,
        eventRecord.Who?.Name
      );

      if (relatedParticipantsByEventId.containsKey(eventRecord.Id)) {
        for (
          ActivityTimelineModels.Participant invitee : relatedParticipantsByEventId.get(
            eventRecord.Id
          )
        ) {
          Id inviteeId = String.isNotBlank(invitee.id)
            ? Id.valueOf(invitee.id)
            : null;
          addParticipant(relatedParticipants, inviteeId, invitee.name);
        }
      }

      ActivityTimelineModels.ActivityItem item = buildItem(
        eventRecord.Id,
        eventRecord.StartDateTime,
        eventRecord.Subject,
        activityType,
        'Interactions',
        'Completed',
        eventRecord.Description,
        eventRecord.OwnerId,
        eventRecord.Owner?.Name,
        relatedParticipants,
        null,
        resolveActivityIcon(activityType)
      );
      applyLinkedRecordReference(item, eventRecord.WhatId, linkedRecordByWhatId);
      applyAssociatedAccountReference(item, eventRecord.AccountId, accountNameById);
      items.add(item);
    }

    return items;
  }

  private static List<Task> queryTasksByRelation(Set<Id> whatIds, Set<Id> whoIds) {
    Map<Id, Task> taskById = new Map<Id, Task>();

    if (whatIds != null) {
      for (Set<Id> whatIdChunk : chunkIdSet(whatIds)) {
        for (Task taskRecord : queryTasksByWhatIds(whatIdChunk)) {
          taskById.put(taskRecord.Id, taskRecord);
        }
      }
    }

    if (whoIds != null) {
      for (Set<Id> whoIdChunk : chunkIdSet(whoIds)) {
        for (Task taskRecord : queryTasksByWhoIds(whoIdChunk)) {
          taskById.put(taskRecord.Id, taskRecord);
        }
      }
    }

    return taskById.values();
  }

  private static List<Task> queryTasksByWhatIds(Set<Id> whatIds) {
    if (whatIds == null || whatIds.isEmpty() || !budget().canRead(1)) {
      return new List<Task>();
    }

    Integer rowLimit = budget().nextLimit(getActivityQueryLimit());
    if (rowLimit <= 0) {
      return new List<Task>();
    }

    List<Task> records = [
      SELECT
        Id,
        Subject,
        Status,
        Description,
        ActivityDate,
        CreatedDate,
        Priority,
        TaskSubtype,
        OwnerId,
        Owner.Name,
        WhoId,
        Who.Name,
        WhatId,
        AccountId
      FROM Task
      WHERE WhatId IN :whatIds
      ORDER BY ActivityDate DESC NULLS LAST, CreatedDate DESC
      LIMIT :rowLimit
    ];
    budget().markTruncatedIfFull(rowLimit, records.size());
    return records;
  }

  private static List<Task> queryTasksByWhoIds(Set<Id> whoIds) {
    if (whoIds == null || whoIds.isEmpty() || !budget().canRead(1)) {
      return new List<Task>();
    }

    Integer rowLimit = budget().nextLimit(getActivityQueryLimit());
    if (rowLimit <= 0) {
      return new List<Task>();
    }

    List<Task> records = [
      SELECT
        Id,
        Subject,
        Status,
        Description,
        ActivityDate,
        CreatedDate,
        Priority,
        TaskSubtype,
        OwnerId,
        Owner.Name,
        WhoId,
        Who.Name,
        WhatId,
        AccountId
      FROM Task
      WHERE WhoId IN :whoIds
      ORDER BY ActivityDate DESC NULLS LAST, CreatedDate DESC
      LIMIT :rowLimit
    ];
    budget().markTruncatedIfFull(rowLimit, records.size());
    return records;
  }

  private static List<Event> queryEventsByRelation(Set<Id> whatIds, Set<Id> whoIds) {
    Map<Id, Event> eventById = new Map<Id, Event>();

    if (whatIds != null) {
      for (Set<Id> whatIdChunk : chunkIdSet(whatIds)) {
        for (Event eventRecord : queryEventsByWhatIds(whatIdChunk)) {
          eventById.put(eventRecord.Id, eventRecord);
        }
      }
    }

    if (whoIds != null) {
      for (Set<Id> whoIdChunk : chunkIdSet(whoIds)) {
        for (Event eventRecord : queryEventsByWhoIds(whoIdChunk)) {
          eventById.put(eventRecord.Id, eventRecord);
        }
      }
    }

    return eventById.values();
  }

  private static List<Event> queryEventsByWhatIds(Set<Id> whatIds) {
    if (whatIds == null || whatIds.isEmpty() || !budget().canRead(1)) {
      return new List<Event>();
    }

    Integer rowLimit = budget().nextLimit(getActivityQueryLimit());
    if (rowLimit <= 0) {
      return new List<Event>();
    }

    List<Event> records = [
      SELECT
        Id,
        Subject,
        Type,
        Description,
        StartDateTime,
        OwnerId,
        Owner.Name,
        WhoId,
        Who.Name,
        WhatId,
        AccountId
      FROM Event
      WHERE WhatId IN :whatIds
      ORDER BY StartDateTime DESC NULLS LAST
      LIMIT :rowLimit
    ];
    budget().markTruncatedIfFull(rowLimit, records.size());
    return records;
  }

  private static List<Event> queryEventsByWhoIds(Set<Id> whoIds) {
    if (whoIds == null || whoIds.isEmpty() || !budget().canRead(1)) {
      return new List<Event>();
    }

    Integer rowLimit = budget().nextLimit(getActivityQueryLimit());
    if (rowLimit <= 0) {
      return new List<Event>();
    }

    List<Event> records = [
      SELECT
        Id,
        Subject,
        Type,
        Description,
        StartDateTime,
        OwnerId,
        Owner.Name,
        WhoId,
        Who.Name,
        WhatId,
        AccountId
      FROM Event
      WHERE WhoId IN :whoIds
      ORDER BY StartDateTime DESC NULLS LAST
      LIMIT :rowLimit
    ];
    budget().markTruncatedIfFull(rowLimit, records.size());
    return records;
  }

  private static List<ActivityTimelineModels.ActivityItem> buildEmailActivities(
    Set<Id> whatIds
  ) {
    List<ActivityTimelineModels.ActivityItem> items = new List<ActivityTimelineModels.ActivityItem>();

    if (whatIds == null || whatIds.isEmpty()) {
      return items;
    }

    Map<Id, EmailMessage> emailById = new Map<Id, EmailMessage>();
    for (Set<Id> whatIdChunk : chunkIdSet(whatIds)) {
      if (!budget().canRead(1)) {
        break;
      }

      for (EmailMessage emailRecord : queryEmailMessagesByRelatedIds(whatIdChunk)) {
        emailById.put(emailRecord.Id, emailRecord);
      }
    }

    for (EmailMessage emailRecord : emailById.values()) {
      List<ActivityTimelineModels.Participant> recipients = buildEmailRecipientParticipants(
        emailRecord
      );

      ActivityTimelineModels.ActivityItem item = buildItem(
        emailRecord.Id,
        emailRecord.MessageDate,
        String.isNotBlank(emailRecord.Subject)
          ? emailRecord.Subject
          : '(No Subject)',
        'Email',
        'Interactions',
        resolveEmailStatusLabel(emailRecord.Status),
        null,
        null,
        null,
        recipients,
        null,
        resolveActivityIcon('Email')
      );
      item.fromAddress = resolveEmailFromAddress(emailRecord);
      items.add(item);
    }

    return items;
  }

  private static String resolveEmailFromAddress(EmailMessage emailRecord) {
    if (String.isNotBlank(emailRecord.FromAddress)) {
      return emailRecord.FromAddress;
    }

    return String.isNotBlank(emailRecord.FromName)
      ? emailRecord.FromName
      : '';
  }

  private static String resolveEmailStatusLabel(String status) {
    if (String.isBlank(status)) {
      return null;
    }

    switch on status {
      when '0' {
        return 'New';
      }
      when '1' {
        return 'Read';
      }
      when '2' {
        return 'Replied';
      }
      when '3' {
        return 'Sent';
      }
      when '4' {
        return 'Forwarded';
      }
      when '5' {
        return 'Draft';
      }
      when else {
        return status;
      }
    }
  }

  private static List<ActivityTimelineModels.Participant> buildEmailRecipientParticipants(
    EmailMessage emailRecord
  ) {
    List<ActivityTimelineModels.Participant> recipients = new List<ActivityTimelineModels.Participant>();

    if (emailRecord.EmailMessageRelations == null) {
      return recipients;
    }

    for (EmailMessageRelation relation : emailRecord.EmailMessageRelations) {
      if (relation.RelationType != 'ToAddress') {
        continue;
      }

      String recipientName = relation.Relation != null
        ? relation.Relation.Name
        : null;
      if (String.isBlank(recipientName)) {
        recipientName = relation.RelationAddress;
      }

      addParticipant(
        recipients,
        relation.RelationId,
        recipientName
      );
    }

    if (recipients.isEmpty() && String.isNotBlank(emailRecord.ToAddress)) {
      ActivityTimelineModels.Participant fallbackRecipient = new ActivityTimelineModels.Participant();
      fallbackRecipient.name = emailRecord.ToAddress;
      recipients.add(fallbackRecipient);
    }

    return recipients;
  }

  private static List<ActivityTimelineModels.ActivityItem> buildEngagementActivities(
    Set<Id> contactIds
  ) {
    List<ActivityTimelineModels.ActivityItem> items = new List<ActivityTimelineModels.ActivityItem>();
    if (contactIds == null || contactIds.isEmpty()) {
      return items;
    }

    Map<Id, String> contactNameById = new Map<Id, String>();
    for (Set<Id> contactIdChunk : chunkIdSet(contactIds)) {
      if (!budget().canRead(2)) {
        break;
      }

      for (Contact contactRecord : [
        SELECT Id, Name
        FROM Contact
        WHERE Id IN :contactIdChunk
      ]) {
        contactNameById.put(contactRecord.Id, contactRecord.Name);
      }

      if (!budget().canRead(1)) {
        break;
      }

      Integer rowLimit = budget().nextLimit(getActivityQueryLimit());
      if (rowLimit <= 0) {
        break;
      }

      List<EngagementInteraction> interactions = [
        SELECT
          Id,
          Reason,
          Status,
          CommunicationChannel,
          Type,
          StartDateTime,
          InitiatingAttendeeId
        FROM EngagementInteraction
        WHERE InitiatingAttendeeId IN :contactIdChunk
        ORDER BY StartDateTime DESC NULLS LAST
        LIMIT :rowLimit
      ];
      budget().markTruncatedIfFull(rowLimit, interactions.size());

      for (EngagementInteraction interaction : interactions) {
        String activityType = resolveEngagementActivityType(
          interaction.CommunicationChannel
        );
        String title = String.isNotBlank(interaction.Reason)
          ? interaction.Reason
          : interaction.CommunicationChannel + ' ' + interaction.Type;

        List<ActivityTimelineModels.Participant> relatedParticipants = new List<ActivityTimelineModels.Participant>();
        addParticipant(
          relatedParticipants,
          interaction.InitiatingAttendeeId,
          contactNameById.get(interaction.InitiatingAttendeeId)
        );

        items.add(
          buildItem(
            interaction.Id,
            interaction.StartDateTime,
            title,
            activityType,
            'Interactions',
            interaction.Status,
            interaction.Reason,
            null,
            null,
            relatedParticipants,
            null,
            resolveActivityIcon(activityType)
          )
        );
      }
    }

    return items;
  }

  private static Datetime resolveTaskActivityDateTime(Task taskRecord) {
    if (taskRecord == null) {
      return null;
    }

    if (taskRecord.ActivityDate != null) {
      return Datetime.newInstance(
        taskRecord.ActivityDate,
        Time.newInstance(12, 0, 0, 0)
      );
    }

    return taskRecord.CreatedDate;
  }

  private static ActivityTimelineModels.ActivityItem buildItem(
    Id recordId,
    Datetime activityDateTime,
    String title,
    String activityType,
    String category,
    String status,
    String description,
    Id ownerId,
    String ownerName,
    List<ActivityTimelineModels.Participant> relatedParticipants,
    String linkedRecord,
    String icon
  ) {
    ActivityTimelineModels.ActivityItem item = new ActivityTimelineModels.ActivityItem();
    item.id = String.valueOf(recordId);
    item.title = title;
    item.activityType = activityType;
    item.category = category;
    item.status = status;
    item.description = description;
    item.ownerId = ownerId != null ? String.valueOf(ownerId) : null;
    item.ownerName = ownerName;
    item.relatedParticipants = relatedParticipants != null
      ? relatedParticipants
      : new List<ActivityTimelineModels.Participant>();
    item.participants = mergeParticipants(
      ownerId,
      ownerName,
      item.relatedParticipants
    );
    item.linkedRecord = linkedRecord;
    item.icon = icon;
    item.recordObjectApiName = recordId.getSobjectType().getDescribe().getName();
    item.hasDueDate = true;

    if (activityDateTime != null) {
      item.activityDateTime = activityDateTime.getTime();
      item.dateValue = activityDateTime.format('yyyy-MM-dd');
    } else {
      item.activityDateTime = 0;
      item.dateValue = '';
    }

    return item;
  }

  private static Map<Id, List<ActivityTimelineModels.Participant>> resolveEventRelatedParticipantsByEventId(
    Set<Id> eventIds
  ) {
    Map<Id, List<ActivityTimelineModels.Participant>> relatedByEventId = new Map<Id, List<ActivityTimelineModels.Participant>>();

    if (eventIds == null || eventIds.isEmpty()) {
      return relatedByEventId;
    }

    for (Id eventId : eventIds) {
      relatedByEventId.put(
        eventId,
        new List<ActivityTimelineModels.Participant>()
      );
    }

    if (!budget().canRead(1)) {
      return relatedByEventId;
    }

    Integer rowLimit = budget().nextLimit(getActivityQueryLimit());
    if (rowLimit <= 0) {
      return relatedByEventId;
    }

    List<EventRelation> eventRelations = [
      SELECT EventId, RelationId, Relation.Name
      FROM EventRelation
      WHERE EventId IN :eventIds AND IsInvitee = TRUE
      ORDER BY Relation.Name ASC NULLS LAST
      LIMIT :rowLimit
    ];
    budget().markTruncatedIfFull(rowLimit, eventRelations.size());

    for (EventRelation eventRelation : eventRelations) {
      if (
        eventRelation.RelationId == null ||
        String.isBlank(eventRelation.Relation?.Name)
      ) {
        continue;
      }

      String objectApiName = eventRelation.RelationId.getSobjectType()
        .getDescribe()
        .getName();

      if (objectApiName != 'Contact' && objectApiName != 'Lead') {
        continue;
      }

      addParticipant(
        relatedByEventId.get(eventRelation.EventId),
        eventRelation.RelationId,
        eventRelation.Relation.Name
      );
    }

    return relatedByEventId;
  }

  private static List<ActivityTimelineModels.Participant> mergeParticipants(
    Id ownerId,
    String ownerName,
    List<ActivityTimelineModels.Participant> relatedParticipants
  ) {
    List<ActivityTimelineModels.Participant> participants = new List<ActivityTimelineModels.Participant>();
    addParticipant(participants, ownerId, ownerName);

    if (relatedParticipants == null) {
      return participants;
    }

    for (ActivityTimelineModels.Participant relatedParticipant : relatedParticipants) {
      Id relatedId = String.isNotBlank(relatedParticipant.id)
        ? Id.valueOf(relatedParticipant.id)
        : null;
      addParticipant(participants, relatedId, relatedParticipant.name);
    }

    return participants;
  }

  private class LinkedRecordContext {
    Id recordId;
    String objectApiName;
    String label;

    LinkedRecordContext(Id recordId, String objectApiName, String label) {
      this.recordId = recordId;
      this.objectApiName = objectApiName;
      this.label = label;
    }
  }

  private static Map<Id, LinkedRecordContext> buildLinkedRecordContextForWhatIds(
    Set<Id> whatIds,
    Map<Id, String> caseNumberById
  ) {
    Map<Id, LinkedRecordContext> contextByWhatId = new Map<Id, LinkedRecordContext>();

    if (whatIds == null || whatIds.isEmpty()) {
      return contextByWhatId;
    }

    Map<String, Set<Id>> recordIdsByObjectApiName = new Map<String, Set<Id>>();

    for (Id whatId : whatIds) {
      if (whatId == null) {
        continue;
      }

      if (caseNumberById != null && caseNumberById.containsKey(whatId)) {
        contextByWhatId.put(
          whatId,
          new LinkedRecordContext(whatId, 'Case', caseNumberById.get(whatId))
        );
        continue;
      }

      String objectApiName = whatId.getSObjectType().getDescribe().getName();
      if (!recordIdsByObjectApiName.containsKey(objectApiName)) {
        recordIdsByObjectApiName.put(objectApiName, new Set<Id>());
      }
      recordIdsByObjectApiName.get(objectApiName).add(whatId);
    }

    for (String objectApiName : recordIdsByObjectApiName.keySet()) {
      contextByWhatId.putAll(
        resolveLinkedRecordContexts(
          objectApiName,
          recordIdsByObjectApiName.get(objectApiName)
        )
      );
    }

    return contextByWhatId;
  }

  private static Map<Id, LinkedRecordContext> resolveLinkedRecordContexts(
    String objectApiName,
    Set<Id> recordIds
  ) {
    Map<Id, LinkedRecordContext> contextByRecordId = new Map<Id, LinkedRecordContext>();

    if (String.isBlank(objectApiName) || recordIds == null || recordIds.isEmpty()) {
      return contextByRecordId;
    }

    String labelField = resolveLinkedRecordLabelField(objectApiName);
    if (String.isBlank(labelField)) {
      return contextByRecordId;
    }

    String escapedObjectApiName = String.escapeSingleQuotes(objectApiName);
    String escapedLabelField = String.escapeSingleQuotes(labelField);

    for (Set<Id> recordIdChunk : chunkIdSet(recordIds)) {
      if (!canContinueSoqlWork(1)) {
        break;
      }

      String queryString =
        'SELECT Id, ' +
        escapedLabelField +
        ' FROM ' +
        escapedObjectApiName +
        ' WHERE Id IN :recordIdChunk';

      for (SObject record : Database.query(queryString)) {
        Id recordId = (Id) record.get('Id');
        Object labelValue = record.get(labelField);
        if (recordId == null || labelValue == null) {
          continue;
        }

        String label = String.valueOf(labelValue).trim();
        if (String.isBlank(label)) {
          continue;
        }

        contextByRecordId.put(
          recordId,
          new LinkedRecordContext(recordId, objectApiName, label)
        );
      }
    }

    return contextByRecordId;
  }

  private static String resolveLinkedRecordLabelField(String objectApiName) {
    if (objectApiName == 'Case') {
      return 'CaseNumber';
    }

    Schema.SObjectType sobjectType = Schema.getGlobalDescribe().get(objectApiName);
    if (sobjectType == null) {
      return null;
    }

    Map<String, Schema.SObjectField> fieldMap = sobjectType.getDescribe().fields.getMap();
    if (fieldMap.containsKey('Name')) {
      return 'Name';
    }
    if (fieldMap.containsKey('Subject')) {
      return 'Subject';
    }
    if (fieldMap.containsKey('CaseNumber')) {
      return 'CaseNumber';
    }

    return null;
  }

  private static void applyLinkedRecordReference(
    ActivityTimelineModels.ActivityItem item,
    Id whatId,
    Map<Id, LinkedRecordContext> linkedRecordByWhatId
  ) {
    if (
      item == null ||
      whatId == null ||
      linkedRecordByWhatId == null ||
      !linkedRecordByWhatId.containsKey(whatId)
    ) {
      return;
    }

    LinkedRecordContext linkedRecordContext = linkedRecordByWhatId.get(whatId);
    item.linkedRecord = linkedRecordContext.label;
    item.linkedRecordId = String.valueOf(linkedRecordContext.recordId);
    item.linkedRecordObjectApiName = linkedRecordContext.objectApiName;
  }

  private static void applyAssociatedAccountReference(
    ActivityTimelineModels.ActivityItem item,
    Id accountId,
    Map<Id, String> accountNameById
  ) {
    if (
      item == null ||
      accountId == null ||
      accountNameById == null ||
      !accountNameById.containsKey(accountId)
    ) {
      return;
    }

    item.associatedAccountId = String.valueOf(accountId);
    item.associatedAccountName = accountNameById.get(accountId);
  }

  private static Map<Id, String> resolveAccountNamesById(Set<Id> accountIds) {
    Map<Id, String> accountNameById = new Map<Id, String>();

    if (accountIds == null || accountIds.isEmpty()) {
      return accountNameById;
    }

    for (Set<Id> accountIdChunk : chunkIdSet(accountIds)) {
      if (!canContinueSoqlWork(1)) {
        break;
      }

      for (Account account : [
        SELECT Id, Name
        FROM Account
        WHERE Id IN :accountIdChunk
      ]) {
        accountNameById.put(account.Id, account.Name);
      }
    }

    return accountNameById;
  }

  private static void addParticipant(
    List<ActivityTimelineModels.Participant> participants,
    Id recordId,
    String name
  ) {
    if (String.isBlank(name)) {
      return;
    }

    for (ActivityTimelineModels.Participant existing : participants) {
      if (existing.name == name) {
        return;
      }
    }

    ActivityTimelineModels.Participant participant = new ActivityTimelineModels.Participant();
    participant.name = name;

    if (recordId != null) {
      String objectApiName = recordId.getSobjectType().getDescribe().getName();
      if (
        objectApiName == 'User' ||
        objectApiName == 'Contact' ||
        objectApiName == 'Lead' ||
        objectApiName == 'Account'
      ) {
        participant.id = String.valueOf(recordId);
        participant.objectApiName = objectApiName;
      }
    }

    participants.add(participant);
  }

  private static String resolveEventActivityType(String eventType) {
    if (EVENT_TYPE_LABELS.containsKey(eventType)) {
      return EVENT_TYPE_LABELS.get(eventType);
    }

    return String.isNotBlank(eventType) ? eventType : 'Meeting';
  }

  private static String resolveTaskActivityType(String taskSubtype) {
    if (TASK_SUBTYPE_LABELS.containsKey(taskSubtype)) {
      return TASK_SUBTYPE_LABELS.get(taskSubtype);
    }

    return 'Task';
  }

  private static String resolveActivityCategory(String activityType) {
    return activityType == 'Case' || activityType == 'Task'
      ? 'Work'
      : 'Interactions';
  }

  private static String resolveEngagementActivityType(String communicationChannel) {
    if (CHANNEL_TYPE_LABELS.containsKey(communicationChannel)) {
      return CHANNEL_TYPE_LABELS.get(communicationChannel);
    }

    return String.isNotBlank(communicationChannel)
      ? communicationChannel
      : 'Chat';
  }

  private static String resolveActivityIcon(String activityType) {
    switch on activityType {
      when 'Case' {
        return 'standard:case';
      }
      when 'Task' {
        return 'standard:task';
      }
      when 'Meeting' {
        return 'standard:event';
      }
      when 'Phone call' {
        return 'standard:call';
      }
      when 'Email' {
        return 'standard:email';
      }
      when 'Text/SMS' {
        return 'utility:sms';
      }
      when 'Chat' {
        return 'standard:live_chat';
      }
      when 'Significant Event' {
        return 'standard:event';
      }
      when else {
        return 'standard:event';
      }
    }
  }

  private List<ActivityTimelineModels.ActivityItem> buildSignificantEventActivitiesForScope(
    Id recordId,
    ActivityQueryScope queryScope,
    Boolean includeCurrentRecordEvents
  ) {
    Set<Id> accountIds = new Set<Id>();
    Set<Id> teamIds = new Set<Id>();

    if (
      includeCurrentRecordEvents == true &&
      recordId != null &&
      recordId.getSObjectType() == Account.SObjectType
    ) {
      accountIds.add(recordId);
    }

    if (queryScope != null) {
      if (queryScope.relatedAccountIds != null) {
        accountIds.addAll(queryScope.relatedAccountIds);
      }
      if (queryScope.householdIds != null) {
        accountIds.addAll(queryScope.householdIds);
      }
      if (queryScope.householdId != null) {
        accountIds.add(queryScope.householdId);
      }
      if (queryScope.financialAdvisorTeamIds != null) {
        teamIds.addAll(queryScope.financialAdvisorTeamIds);
      }
    }

    if (accountIds.isEmpty() && teamIds.isEmpty()) {
      return new List<ActivityTimelineModels.ActivityItem>();
    }

    if (
      teamIds.isEmpty() &&
      includeCurrentRecordEvents == true &&
      recordId != null &&
      accountIds.size() == 1 &&
      accountIds.contains(recordId)
    ) {
      return buildSignificantEventActivities(recordId);
    }

    return mapLinkedContactRowsToActivityItems(
      SIGNIFICANT_EVENT_SERVICE.getLinkedContactsForScope(accountIds, teamIds)
    );
  }

  private List<ActivityTimelineModels.ActivityItem> buildSignificantEventActivities(
    Id recordId
  ) {
    List<ActivityTimelineModels.ActivityItem> items = new List<ActivityTimelineModels.ActivityItem>();

    if (recordId == null || recordId.getSObjectType() != Account.SObjectType) {
      return items;
    }

    Account contextAccount = ACCOUNT_REPOSITORY.selectById(recordId);
    if (contextAccount == null) {
      return items;
    }

    if (FscRelAccountRepository.isHouseholdRecordType(contextAccount)) {
      Map<String, ActivityTimelineModels.ActivityItem> itemByEventId = new Map<String, ActivityTimelineModels.ActivityItem>();

      for (
        SignificantEventActionModels.LinkedContactRow row : SIGNIFICANT_EVENT_SERVICE.getLinkedContactsForAccount(
          recordId
        )
      ) {
        if (
          String.isBlank(row.significantEventId) ||
          String.isBlank(row.accountId)
        ) {
          continue;
        }

        if (!itemByEventId.containsKey(row.significantEventId)) {
          itemByEventId.put(
            row.significantEventId,
            mapLinkedContactRowToActivityItem(row, contextAccount)
          );
          continue;
        }

        mergeSignificantEventParticipant(
          itemByEventId.get(row.significantEventId),
          row
        );
      }

      items.addAll(itemByEventId.values());
      return items;
    }

    for (
      SignificantEventActionModels.SignificantEventRow row : SIGNIFICANT_EVENT_SERVICE.getSignificantEventsForAccount(
        recordId
      )
    ) {
      if (String.isBlank(row.significantEventId)) {
        continue;
      }

      items.add(mapSignificantEventRowToActivityItem(row, contextAccount));
    }

    return items;
  }

  private static ActivityTimelineModels.ActivityItem mapLinkedContactRowToActivityItem(
    SignificantEventActionModels.LinkedContactRow row,
    Account householdAccount
  ) {
    ActivityTimelineModels.ActivityItem item = buildSignificantEventActivityItem(
      row.significantEventId,
      row.eventName,
      row.eventType,
      row.otherEventType,
      row.startDate,
      row.endDate,
      row.approximateDate,
      row.description
    );

    if (householdAccount != null) {
      item.associatedAccountId = String.valueOf(householdAccount.Id);
      item.associatedAccountName = householdAccount.Name;
    } else if (
      String.isNotBlank(row.householdId) &&
      String.isNotBlank(row.householdName)
    ) {
      item.associatedAccountId = row.householdId;
      item.associatedAccountName = row.householdName;
    }

    addParticipant(
      item.relatedParticipants,
      String.isBlank(row.accountId) ? null : Id.valueOf(row.accountId),
      row.accountName
    );
    return item;
  }

  private static ActivityTimelineModels.ActivityItem mapSignificantEventRowToActivityItem(
    SignificantEventActionModels.SignificantEventRow row,
    Account contextAccount
  ) {
    ActivityTimelineModels.ActivityItem item = buildSignificantEventActivityItem(
      row.significantEventId,
      row.eventName,
      row.eventType,
      row.otherEventType,
      row.startDate,
      row.endDate,
      row.approximateDate,
      row.description
    );

    if (String.isNotBlank(row.householdId) && String.isNotBlank(row.householdName)) {
      item.associatedAccountId = row.householdId;
      item.associatedAccountName = row.householdName;
    }

    if (contextAccount != null) {
      addParticipant(
        item.relatedParticipants,
        contextAccount.Id,
        contextAccount.Name
      );
    }

    return item;
  }

  private static ActivityTimelineModels.ActivityItem buildSignificantEventActivityItem(
    String significantEventId,
    String eventName,
    String eventType,
    String otherEventType,
    String startDate,
    String endDate,
    Boolean approximateDate,
    String description
  ) {
    ActivityTimelineModels.ActivityItem item = new ActivityTimelineModels.ActivityItem();
    item.id = significantEventId;
    item.title = eventName;
    item.activityType = 'Significant Event';
    item.category = 'Interactions';
    item.status = resolveSignificantEventTypeLabel(eventType, otherEventType);
    item.description = description;
    item.endDateValue = endDate;
    item.approximateDate = approximateDate == true;
    item.icon = resolveActivityIcon(item.activityType);
    item.recordObjectApiName = 'Significant_Event__c';
    item.hasDueDate = String.isNotBlank(startDate);

    Datetime activityDateTime = resolveSignificantEventActivityDateTime(startDate);
    if (activityDateTime != null) {
      item.activityDateTime = activityDateTime.getTime();
      item.dateValue = activityDateTime.format('yyyy-MM-dd');
    } else {
      item.activityDateTime = 0;
      item.dateValue = '';
      item.hasDueDate = false;
    }

    return item;
  }

  private static List<ActivityTimelineModels.ActivityItem> mapLinkedContactRowsToActivityItems(
    List<SignificantEventActionModels.LinkedContactRow> rows
  ) {
    Map<String, ActivityTimelineModels.ActivityItem> itemByEventId = new Map<String, ActivityTimelineModels.ActivityItem>();

    if (rows == null) {
      return new List<ActivityTimelineModels.ActivityItem>();
    }

    for (SignificantEventActionModels.LinkedContactRow row : rows) {
      if (row == null || String.isBlank(row.significantEventId)) {
        continue;
      }

      if (!itemByEventId.containsKey(row.significantEventId)) {
        itemByEventId.put(
          row.significantEventId,
          mapLinkedContactRowToActivityItem(row, null)
        );
        continue;
      }

      mergeSignificantEventParticipant(
        itemByEventId.get(row.significantEventId),
        row
      );
    }

    return itemByEventId.values();
  }

  private static void mergeSignificantEventParticipant(
    ActivityTimelineModels.ActivityItem item,
    SignificantEventActionModels.LinkedContactRow row
  ) {
    if (item == null || row == null || String.isBlank(row.accountId)) {
      return;
    }

    addParticipant(
      item.relatedParticipants,
      Id.valueOf(row.accountId),
      row.accountName
    );
  }

  private static String resolveSignificantEventTypeLabel(
    String eventType,
    String otherEventType
  ) {
    if (
      eventType == SignificantEventActionRepository.EVENT_TYPE_OTHER &&
      String.isNotBlank(otherEventType)
    ) {
      return otherEventType;
    }

    return eventType;
  }

  private static Datetime resolveSignificantEventActivityDateTime(
    String startDate
  ) {
    if (String.isBlank(startDate)) {
      return null;
    }

    try {
      Date parsedDate = Date.valueOf(startDate);
      return Datetime.newInstance(parsedDate, Time.newInstance(0, 0, 0, 0));
    } catch (Exception error) {
      return null;
    }
  }

  private static Map<String, Integer> buildCategoryCounts(
    List<ActivityTimelineModels.ActivityItem> activities
  ) {
    Map<String, Integer> countsByCategory = new Map<String, Integer>();
    for (String category : CATEGORY_ORDER) {
      countsByCategory.put(category, 0);
    }

    for (ActivityTimelineModels.ActivityItem activity : activities) {
      Integer currentCount = countsByCategory.containsKey(activity.category)
        ? countsByCategory.get(activity.category)
        : 0;
      countsByCategory.put(activity.category, currentCount + 1);
    }

    return countsByCategory;
  }

  private static List<Set<Id>> chunkIdSet(Set<Id> ids) {
    List<Set<Id>> chunks = new List<Set<Id>>();

    if (ids == null || ids.isEmpty()) {
      return chunks;
    }

    List<Id> idList = new List<Id>(ids);
    for (Integer index = 0; index < idList.size(); index += QUERY_CHUNK_SIZE) {
      Set<Id> chunk = new Set<Id>();
      Integer endIndex = Math.min(index + QUERY_CHUNK_SIZE, idList.size());

      for (Integer chunkIndex = index; chunkIndex < endIndex; chunkIndex++) {
        chunk.add(idList[chunkIndex]);
      }

      chunks.add(chunk);
    }

    return chunks;
  }

  private static List<EmailMessage> queryEmailMessagesByRelatedIds(Set<Id> whatIds) {
    if (whatIds == null || whatIds.isEmpty() || !budget().canRead(1)) {
      return new List<EmailMessage>();
    }

    Integer rowLimit = budget().nextLimit(EMAIL_ACTIVITY_QUERY_LIMIT);
    if (rowLimit <= 0) {
      return new List<EmailMessage>();
    }

    List<EmailMessage> records = [
      SELECT
        Id,
        Subject,
        MessageDate,
        FromAddress,
        FromName,
        ToAddress,
        TextBody,
        Status,
        (
          SELECT RelationId, RelationType, RelationAddress, Relation.Name
          FROM EmailMessageRelations
          WHERE RelationType = 'ToAddress'
        )
      FROM EmailMessage
      WHERE RelatedToId IN :whatIds OR ParentId IN :whatIds
      ORDER BY MessageDate DESC NULLS LAST
      LIMIT :rowLimit
    ];
    budget().markTruncatedIfFull(rowLimit, records.size());
    return records;
  }

  private without sharing class ActivityTimelineScopeQuery {
    Set<Id> selectFinancialAdvisorTeamIdsByBranchId(Id branchId) {
      if (branchId == null) {
        return new Set<Id>();
      }

      return selectFinancialAdvisorTeamIdsByBranchIds(new Set<Id>{ branchId });
    }

    Set<Id> selectFinancialAdvisorTeamIdsByBranchIds(Set<Id> branchIds) {
      Set<Id> teamIds = new Set<Id>();

      if (branchIds == null || branchIds.isEmpty()) {
        return teamIds;
      }

      for (Financial_Advisor_Team__c team : [
        SELECT Id
        FROM Financial_Advisor_Team__c
        WHERE Advisor_Group__c IN :branchIds
      ]) {
        teamIds.add(team.Id);
      }

      return teamIds;
    }

    List<Account> selectAccountsForBranchFinancialAdvisorTeams(Set<Id> teamIds) {
      if (teamIds == null || teamIds.isEmpty()) {
        return new List<Account>();
      }

      Set<String> householdDeveloperNames = FscRelAccountRepository.selectHouseholdRecordTypeDeveloperNames();
      Set<String> clientDeveloperNames = FscRelClientAccountUtils.CLIENT_RECORD_TYPE_DEVELOPER_NAMES;
      Set<String> eligibleDeveloperNames = new Set<String>();
      eligibleDeveloperNames.addAll(householdDeveloperNames);
      eligibleDeveloperNames.addAll(clientDeveloperNames);

      Map<Id, Account> accountById = new Map<Id, Account>();
      Set<Id> householdIds = new Set<Id>();
      Integer accountRowLimit = budget().nextLimit(ACCOUNT_SCOPE_QUERY_LIMIT);
      if (accountRowLimit <= 0) {
        return new List<Account>();
      }

      List<Account> teamAccounts = [
        SELECT Id, Household__c, RecordType.DeveloperName, RecordType.Name, Type
        FROM Account
        WHERE Financial_Advisor_Team__c IN :teamIds
        AND RecordType.DeveloperName IN :eligibleDeveloperNames
        LIMIT :accountRowLimit
      ];
      budget().markTruncatedIfFull(accountRowLimit, teamAccounts.size());

      for (Account account : teamAccounts) {
        accountById.put(account.Id, account);

        if (
          account.RecordType != null &&
          householdDeveloperNames.contains(account.RecordType.DeveloperName)
        ) {
          householdIds.add(account.Id);
        }
      }

      if (!householdIds.isEmpty() && budget().canRead(1)) {
        Integer householdMemberLimit = budget().nextLimit(ACCOUNT_SCOPE_QUERY_LIMIT);
        if (householdMemberLimit > 0) {
          List<Account> householdMembers = [
            SELECT Id, Household__c, RecordType.DeveloperName, RecordType.Name, Type
            FROM Account
            WHERE Household__c IN :householdIds
            AND RecordType.DeveloperName IN :clientDeveloperNames
            LIMIT :householdMemberLimit
          ];
          budget().markTruncatedIfFull(householdMemberLimit, householdMembers.size());

          for (Account account : householdMembers) {
            accountById.put(account.Id, account);
          }
        }
      }

      return accountById.values();
    }
  }

  private static List<ActivityTimelineModels.ActivityItem> deduplicateActivitiesById(
    List<ActivityTimelineModels.ActivityItem> activities
  ) {
    Map<String, ActivityTimelineModels.ActivityItem> itemById = new Map<String, ActivityTimelineModels.ActivityItem>();

    if (activities == null || activities.isEmpty()) {
      return new List<ActivityTimelineModels.ActivityItem>();
    }

    for (ActivityTimelineModels.ActivityItem item : activities) {
      if (item == null || String.isBlank(item.id)) {
        continue;
      }

      itemById.put(item.id, item);
    }

    return itemById.values();
  }

  private class ActivityItemComparator implements Comparator<ActivityTimelineModels.ActivityItem> {
    public Integer compare(
      ActivityTimelineModels.ActivityItem first,
      ActivityTimelineModels.ActivityItem second
    ) {
      Long firstDateTime = first.activityDateTime == null ? 0 : first.activityDateTime;
      Long secondDateTime = second.activityDateTime == null
        ? 0
        : second.activityDateTime;
      if (firstDateTime == secondDateTime) {
        String firstTitle = first.title == null ? '' : first.title;
        String secondTitle = second.title == null ? '' : second.title;
        return firstTitle.compareTo(secondTitle);
      }
      return firstDateTime > secondDateTime ? -1 : 1;
    }
  }
}