/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-28
 */
public with sharing class SignificantEventActionService {
  private final SignificantEventActionRepository repository;
  private final FscRelRelationshipTreeService treeService;

  public SignificantEventActionService() {
    this.repository = new SignificantEventActionRepository();
    this.treeService = new FscRelRelationshipTreeService();
  }

  public SignificantEventActionService(
    SignificantEventActionRepository repository
  ) {
    this.repository = repository;
    this.treeService = new FscRelRelationshipTreeService();
  }

  @TestVisible
  private SignificantEventActionService(
    SignificantEventActionRepository repository,
    FscRelRelationshipTreeService treeService
  ) {
    this.repository = repository;
    this.treeService = treeService;
  }

  public SignificantEventActionModels.CreateContext getActionContext(Id recordId) {
    if (recordId == null) {
      throw new AuraHandledException('No record id provided.');
    }

    Schema.SObjectType sobjectType = recordId.getSobjectType();

    if (sobjectType == Significant_Event__c.SObjectType) {
      return getEditContext(recordId);
    }

    if (sobjectType == Account.SObjectType) {
      return getCreateContext(recordId);
    }

    throw new AuraHandledException('Unsupported record context.');
  }

  public SignificantEventActionModels.CreateContext getCreateContext(Id accountId) {
    if (accountId == null) {
      throw new AuraHandledException('No account id provided.');
    }

    Account contextAccount = repository.selectContextAccount(accountId);
    if (contextAccount == null) {
      throw new AuraHandledException('Account not found.');
    }

    SignificantEventActionModels.CreateContext context = new SignificantEventActionModels.CreateContext();
    context.isEditMode = false;
    context.contextAccountId = String.valueOf(contextAccount.Id);
    context.contextAccountName = contextAccount.Name;
    context.contextRecordTypeDeveloperName = contextAccount.RecordType == null
      ? null
      : contextAccount.RecordType.DeveloperName;
    context.isHouseholdLaunch = FscRelAccountRepository.isHouseholdRecordTypeDeveloperName(
      context.contextRecordTypeDeveloperName
    );

    Id householdId = resolveHouseholdId(contextAccount);
    context.householdId = householdId == null ? null : String.valueOf(householdId);
    context.financialAdvisorTeamId = formatId(
      resolveFinancialAdvisorTeamId(contextAccount, householdId)
    );

    context.defaultSelectedAccounts = buildDefaultSelectedAccounts(contextAccount);

    return context;
  }

  public SignificantEventActionModels.CreateContext getEditContext(
    Id significantEventId
  ) {
    if (significantEventId == null) {
      throw new AuraHandledException('No significant event id provided.');
    }

    Significant_Event__c eventRecord = repository.selectSignificantEventById(
      significantEventId
    );
    if (eventRecord == null) {
      throw new AuraHandledException('Significant Event not found.');
    }

    SignificantEventActionModels.CreateContext context = new SignificantEventActionModels.CreateContext();
    context.isEditMode = true;
    context.isHouseholdLaunch = false;
    context.householdId = eventRecord.Household__c == null
      ? null
      : String.valueOf(eventRecord.Household__c);
    context.contextAccountId = context.householdId;
    context.financialAdvisorTeamId = formatId(eventRecord.Financial_Advisor_Team__c);
    context.eventData = buildFormData(eventRecord);

    return context;
  }

  public List<SignificantEventActionModels.SuggestedContactGroup> getSuggestedLinkedContacts(
    Id householdId,
    Id contextAccountId,
    List<String> selectedAccountIds,
    Boolean isHouseholdLaunch
  ) {
    return mapGroupedContactSuggestions(
      treeService.getGroupedContactSuggestions(
        householdId,
        contextAccountId,
        parseAccountIds(selectedAccountIds),
        isHouseholdLaunch == true
      )
    );
  }

  public List<SignificantEventActionModels.LinkedAccountOption> searchNonHouseholdAccounts(
    String searchTerm
  ) {
    List<SignificantEventActionModels.LinkedAccountOption> options = new List<SignificantEventActionModels.LinkedAccountOption>();

    for (Account account : repository.searchNonHouseholdAccounts(searchTerm, 8)) {
      options.add(
        buildLinkedAccountOption(account.Id, account.Name, false)
      );
    }

    return options;
  }

  public List<SignificantEventActionModels.LinkedContactRow> getLinkedContactsForAccount(
    Id accountId
  ) {
    if (accountId == null) {
      throw new AuraHandledException('No account id provided.');
    }

    Account contextAccount = repository.selectContextAccount(accountId);
    if (contextAccount == null) {
      throw new AuraHandledException('Account not found.');
    }

    Set<Id> scopedAccountIds = buildLinkedContactsScopeAccountIds(
      contextAccount
    );
    Map<Id, Significant_Event_Contact__c> participantById = new Map<Id, Significant_Event_Contact__c>();

    if (!scopedAccountIds.isEmpty()) {
      for (
        Significant_Event_Contact__c participant : repository.selectParticipantsByAccountIds(
          scopedAccountIds
        )
      ) {
        participantById.put(participant.Id, participant);
      }
    }

    for (
      Significant_Event_Contact__c participant : repository.selectParticipantsByDirectEventAccountId(
        contextAccount.Id
      )
    ) {
      participantById.put(participant.Id, participant);
    }

    List<SignificantEventActionModels.LinkedContactRow> rows = new List<SignificantEventActionModels.LinkedContactRow>();
    for (Significant_Event_Contact__c participant : participantById.values()) {
      rows.add(buildLinkedContactRow(participant));
    }

    return rows;
  }

  public List<SignificantEventActionModels.LinkedContactRow> getLinkedContactsForSignificantEvent(
    Id significantEventId
  ) {
    if (significantEventId == null) {
      throw new AuraHandledException('No significant event id provided.');
    }

    Significant_Event__c eventRecord = repository.selectSignificantEventById(
      significantEventId
    );
    if (eventRecord == null) {
      throw new AuraHandledException('Significant Event not found.');
    }

    List<SignificantEventActionModels.LinkedContactRow> rows = new List<SignificantEventActionModels.LinkedContactRow>();
    for (
      Significant_Event_Contact__c participant : repository.selectParticipantsByEventId(
        significantEventId
      )
    ) {
      rows.add(buildLinkedContactRow(participant));
    }

    return rows;
  }

  public List<SignificantEventActionModels.LinkedContactRow> getLinkedContactsForScope(
    Set<Id> accountIds,
    Set<Id> financialAdvisorTeamIds
  ) {
    Map<Id, Significant_Event_Contact__c> participantById = new Map<Id, Significant_Event_Contact__c>();
    Set<Id> scopedAccountIds = accountIds == null
      ? new Set<Id>()
      : accountIds;
    Set<Id> scopedTeamIds = financialAdvisorTeamIds == null
      ? new Set<Id>()
      : financialAdvisorTeamIds;

    if (!scopedAccountIds.isEmpty()) {
      for (
        Significant_Event_Contact__c participant : repository.selectParticipantsByAccountIds(
          scopedAccountIds
        )
      ) {
        participantById.put(participant.Id, participant);
      }

      for (
        Significant_Event_Contact__c participant : repository.selectParticipantsByDirectEventAccountIds(
          scopedAccountIds
        )
      ) {
        participantById.put(participant.Id, participant);
      }
    }

    if (!scopedTeamIds.isEmpty()) {
      for (
        Significant_Event_Contact__c participant : repository.selectParticipantsByFinancialAdvisorTeamIds(
          scopedTeamIds
        )
      ) {
        participantById.put(participant.Id, participant);
      }
    }

    List<SignificantEventActionModels.LinkedContactRow> rows = new List<SignificantEventActionModels.LinkedContactRow>();
    for (Significant_Event_Contact__c participant : participantById.values()) {
      rows.add(buildLinkedContactRow(participant));
    }

    return rows;
  }

  public List<SignificantEventActionModels.SignificantEventRow> getSignificantEventsForAccount(
    Id accountId
  ) {
    if (accountId == null) {
      throw new AuraHandledException('No account id provided.');
    }

    Account contextAccount = repository.selectContextAccount(accountId);
    if (contextAccount == null) {
      throw new AuraHandledException('Account not found.');
    }

    Map<Id, SignificantEventActionModels.SignificantEventRow> eventById = new Map<Id, SignificantEventActionModels.SignificantEventRow>();

    for (
      Significant_Event_Contact__c participant : repository.selectParticipantsByAccountIds(
        new Set<Id>{ contextAccount.Id }
      )
    ) {
      if (participant.Significant_Event__c == null) {
        continue;
      }

      if (eventById.containsKey(participant.Significant_Event__c)) {
        continue;
      }

      eventById.put(
        participant.Significant_Event__c,
        buildSignificantEventRow(buildLinkedContactRow(participant))
      );
    }

    return eventById.values();
  }

  public SignificantEventActionModels.SaveResult createSignificantEvent(
    SignificantEventActionModels.SaveRequest request
  ) {
    validateSaveRequest(request, false);
    Account contextAccount = repository.selectContextAccount(
      Id.valueOf(request.contextAccountId)
    );
    Id householdId = resolveHouseholdIdFromRequest(request, contextAccount);
    Id financialAdvisorTeamId = resolveFinancialAdvisorTeamId(
      contextAccount,
      householdId
    );

    Significant_Event__c eventRecord = buildEventRecord(
      request,
      householdId,
      financialAdvisorTeamId
    );
    repository.insertSignificantEvent(eventRecord);
    syncParticipants(
      eventRecord.Id,
      parseAccountIds(request.linkedAccountIds),
      financialAdvisorTeamId,
      new Map<Id, Significant_Event_Contact__c>()
    );

    return new SignificantEventActionModels.SaveResult(
      true,
      'Significant Event created.',
      String.valueOf(eventRecord.Id)
    );
  }

  public SignificantEventActionModels.SaveResult updateSignificantEvent(
    SignificantEventActionModels.SaveRequest request
  ) {
    if (request == null) {
      throw new AuraHandledException('Save request is required.');
    }

    if (String.isBlank(request.significantEventId)) {
      throw new AuraHandledException('Significant Event id is required.');
    }

    if (
      request.linkedAccountIds == null ||
      request.linkedAccountIds.isEmpty()
    ) {
      return deleteSignificantEvent(Id.valueOf(request.significantEventId));
    }

    validateSaveRequest(request, true);

    Significant_Event__c existingEvent = repository.selectSignificantEventById(
      Id.valueOf(request.significantEventId)
    );
    if (existingEvent == null) {
      throw new AuraHandledException('Significant Event not found.');
    }

    Id householdId = String.isBlank(request.householdId)
      ? existingEvent.Household__c
      : Id.valueOf(request.householdId);
    Id financialAdvisorTeamId = existingEvent.Financial_Advisor_Team__c;

    if (financialAdvisorTeamId == null && householdId != null) {
      Account householdAccount = repository.selectContextAccount(householdId);
      financialAdvisorTeamId = resolveFinancialAdvisorTeamId(
        householdAccount,
        householdId
      );
    }

    applyEventUpdates(existingEvent, request, householdId, financialAdvisorTeamId);
    repository.updateSignificantEvent(existingEvent);

    Map<Id, Significant_Event_Contact__c> existingParticipantByAccountId = buildExistingParticipantMap(
      existingEvent.Id
    );
    syncParticipants(
      existingEvent.Id,
      parseAccountIds(request.linkedAccountIds),
      financialAdvisorTeamId,
      existingParticipantByAccountId
    );

    return new SignificantEventActionModels.SaveResult(
      true,
      'Significant Event updated.',
      String.valueOf(existingEvent.Id)
    );
  }

  private SignificantEventActionModels.SaveResult deleteSignificantEvent(
    Id significantEventId
  ) {
    Significant_Event__c existingEvent = repository.selectSignificantEventById(
      significantEventId
    );
    if (existingEvent == null) {
      throw new AuraHandledException('Significant Event not found.');
    }

    repository.deleteParticipants(
      repository.selectParticipantsByEventId(existingEvent.Id)
    );
    repository.deleteSignificantEvent(existingEvent);

    return new SignificantEventActionModels.SaveResult(
      true,
      'Significant Event deleted.',
      String.valueOf(existingEvent.Id)
    );
  }

  private SignificantEventActionModels.SignificantEventFormData buildFormData(
    Significant_Event__c eventRecord
  ) {
    SignificantEventActionModels.SignificantEventFormData formData = new SignificantEventActionModels.SignificantEventFormData();
    formData.significantEventId = String.valueOf(eventRecord.Id);
    formData.eventName = eventRecord.Name;
    formData.eventType = eventRecord.Event_Type__c;
    formData.otherEventType = eventRecord.Other_Event_Type__c;
    formData.startDate = formatDate(eventRecord.Start_Date__c);
    formData.endDate = formatDate(eventRecord.End_Date_Optional__c);
    formData.approximateDate = eventRecord.Approximate_Date__c == true;
    formData.description = eventRecord.Description__c;
    formData.selectedAccounts = new List<SignificantEventActionModels.LinkedAccountOption>();

    for (
      Significant_Event_Contact__c participant : repository.selectParticipantsByEventId(
        eventRecord.Id
      )
    ) {
      if (participant.Account__c == null) {
        continue;
      }

      formData.selectedAccounts.add(
        buildLinkedAccountOption(
          participant.Account__c,
          participant.Account__r == null ? null : participant.Account__r.Name,
          true
        )
      );
    }

    return formData;
  }

  private List<SignificantEventActionModels.SuggestedContactGroup> mapGroupedContactSuggestions(
    List<FscRelRelationshipTreeModels.GroupedAccountContacts> groupedContacts
  ) {
    List<SignificantEventActionModels.SuggestedContactGroup> groups = new List<SignificantEventActionModels.SuggestedContactGroup>();

    if (groupedContacts == null) {
      return groups;
    }

    for (
      FscRelRelationshipTreeModels.GroupedAccountContacts groupedContact : groupedContacts
    ) {
      List<SignificantEventActionModels.LinkedAccountOption> contacts = new List<SignificantEventActionModels.LinkedAccountOption>();

      if (groupedContact.contacts != null) {
        for (
          FscRelRelationshipTreeModels.ScopedAccountSummary contact : groupedContact.contacts
        ) {
          contacts.add(
            buildLinkedAccountOption(
              String.isBlank(contact.accountId) ? null : Id.valueOf(contact.accountId),
              contact.name,
              contact.isHouseholdRelated
            )
          );
        }
      }

      groups.add(buildSuggestionGroup(groupedContact.category, contacts));
    }

    return groups;
  }

  private SignificantEventActionModels.SuggestedContactGroup buildSuggestionGroup(
    String category,
    List<SignificantEventActionModels.LinkedAccountOption> contacts
  ) {
    SignificantEventActionModels.SuggestedContactGroup suggestionGroup = new SignificantEventActionModels.SuggestedContactGroup();
    suggestionGroup.category = category;
    suggestionGroup.contacts = contacts == null
      ? new List<SignificantEventActionModels.LinkedAccountOption>()
      : contacts;
    return suggestionGroup;
  }

  private List<SignificantEventActionModels.LinkedAccountOption> buildDefaultSelectedAccounts(
    Account contextAccount
  ) {
    List<SignificantEventActionModels.LinkedAccountOption> defaultSelectedAccounts = new List<SignificantEventActionModels.LinkedAccountOption>();

    if (
      contextAccount == null ||
      FscRelAccountRepository.isHouseholdRecordType(contextAccount)
    ) {
      return defaultSelectedAccounts;
    }

    defaultSelectedAccounts.add(
      buildLinkedAccountOption(contextAccount.Id, contextAccount.Name, false)
    );

    return defaultSelectedAccounts;
  }

  private SignificantEventActionModels.LinkedAccountOption buildLinkedAccountOption(
    Id accountId,
    String name,
    Boolean isHouseholdRelated
  ) {
    SignificantEventActionModels.LinkedAccountOption option = new SignificantEventActionModels.LinkedAccountOption();
    option.accountId = accountId == null ? null : String.valueOf(accountId);
    option.name = name;
    option.isHouseholdRelated = isHouseholdRelated == true;
    return option;
  }

  private Id resolveHouseholdId(Account contextAccount) {
    return treeService.resolveHouseholdId(contextAccount);
  }

  private Id resolveHouseholdIdFromRequest(
    SignificantEventActionModels.SaveRequest request,
    Account contextAccount
  ) {
    if (!String.isBlank(request.householdId)) {
      return Id.valueOf(request.householdId);
    }

    return resolveHouseholdId(contextAccount);
  }

  private Id resolveFinancialAdvisorTeamId(
    Account contextAccount,
    Id householdId
  ) {
    Id financialAdvisorTeamId = contextAccount == null
      ? null
      : contextAccount.Financial_Advisor_Team__c;

    if (financialAdvisorTeamId != null) {
      return financialAdvisorTeamId;
    }

    if (householdId == null) {
      return null;
    }

    Account householdAccount = repository.selectContextAccount(householdId);
    return householdAccount == null
      ? null
      : householdAccount.Financial_Advisor_Team__c;
  }

  private String formatId(Id value) {
    return value == null ? null : String.valueOf(value);
  }

  private void validateSaveRequest(
    SignificantEventActionModels.SaveRequest request,
    Boolean isEdit
  ) {
    if (request == null) {
      throw new AuraHandledException('Save request is required.');
    }

    if (isEdit && String.isBlank(request.significantEventId)) {
      throw new AuraHandledException('Significant Event id is required.');
    }

    if (!isEdit && String.isBlank(request.contextAccountId)) {
      throw new AuraHandledException('Context account id is required.');
    }

    if (String.isBlank(request.eventName)) {
      throw new AuraHandledException('Event Name is required.');
    }

    if (String.isBlank(request.eventType)) {
      throw new AuraHandledException('Event Type is required.');
    }

    if (
      request.eventType == SignificantEventActionRepository.EVENT_TYPE_OTHER &&
      String.isBlank(request.otherEventType)
    ) {
      throw new AuraHandledException('Other Event Type is required.');
    }

    if (String.isBlank(request.startDate)) {
      throw new AuraHandledException('Start Date is required.');
    }

    if (
      request.linkedAccountIds == null ||
      request.linkedAccountIds.isEmpty()
    ) {
      throw new AuraHandledException('Add at least one linked contact.');
    }

    Date startDate = parseDate(request.startDate);
    Date endDate = parseDate(request.endDate);

    if (endDate != null && startDate != null && endDate < startDate) {
      throw new AuraHandledException(
        'End Date must be on or after Start Date.'
      );
    }
  }

  private Significant_Event__c buildEventRecord(
    SignificantEventActionModels.SaveRequest request,
    Id householdId,
    Id financialAdvisorTeamId
  ) {
    Significant_Event__c eventRecord = new Significant_Event__c();
    applyEventUpdates(eventRecord, request, householdId, financialAdvisorTeamId);
    return eventRecord;
  }

  private void applyEventUpdates(
    Significant_Event__c eventRecord,
    SignificantEventActionModels.SaveRequest request,
    Id householdId,
    Id financialAdvisorTeamId
  ) {
    eventRecord.Name = request.eventName.trim();
    eventRecord.Event_Type__c = request.eventType;
    eventRecord.Other_Event_Type__c =
      request.eventType == SignificantEventActionRepository.EVENT_TYPE_OTHER
        ? request.otherEventType == null
          ? null
          : request.otherEventType.trim()
        : null;
    eventRecord.Start_Date__c = parseDate(request.startDate);
    eventRecord.End_Date_Optional__c = parseDate(request.endDate);
    eventRecord.Approximate_Date__c = request.approximateDate == true;
    eventRecord.Description__c = request.description;
    eventRecord.Household__c = householdId;
    eventRecord.Financial_Advisor_Team__c = financialAdvisorTeamId;
  }

  private Map<Id, Significant_Event_Contact__c> buildExistingParticipantMap(
    Id significantEventId
  ) {
    Map<Id, Significant_Event_Contact__c> participantByAccountId = new Map<Id, Significant_Event_Contact__c>();

    for (
      Significant_Event_Contact__c participant : repository.selectParticipantsByEventId(
        significantEventId
      )
    ) {
      if (participant.Account__c != null) {
        participantByAccountId.put(participant.Account__c, participant);
      }
    }

    return participantByAccountId;
  }

  private void syncParticipants(
    Id significantEventId,
    Set<Id> linkedAccountIds,
    Id financialAdvisorTeamId,
    Map<Id, Significant_Event_Contact__c> existingParticipantByAccountId
  ) {
    List<Significant_Event_Contact__c> toInsert = new List<Significant_Event_Contact__c>();
    List<Significant_Event_Contact__c> toUpdate = new List<Significant_Event_Contact__c>();
    List<Significant_Event_Contact__c> toDelete = new List<Significant_Event_Contact__c>();

    for (Id accountId : linkedAccountIds) {
      if (existingParticipantByAccountId.containsKey(accountId)) {
        Significant_Event_Contact__c existingParticipant = existingParticipantByAccountId.get(
          accountId
        );
        if (existingParticipant.Financial_Advisor_Team__c != financialAdvisorTeamId) {
          existingParticipant.Financial_Advisor_Team__c = financialAdvisorTeamId;
          toUpdate.add(existingParticipant);
        }
        existingParticipantByAccountId.remove(accountId);
        continue;
      }

      Significant_Event_Contact__c participant = new Significant_Event_Contact__c(
        Significant_Event__c = significantEventId,
        Account__c = accountId,
        Financial_Advisor_Team__c = financialAdvisorTeamId
      );
      toInsert.add(participant);
    }

    toDelete.addAll(existingParticipantByAccountId.values());
    repository.insertParticipants(toInsert);
    repository.updateParticipants(toUpdate);
    repository.deleteParticipants(toDelete);
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

      ids.add(Id.valueOf(rawId));
    }

    return ids;
  }

  private Date parseDate(String value) {
    if (String.isBlank(value)) {
      return null;
    }

    return Date.valueOf(value);
  }

  private String formatDate(Date value) {
    return value == null ? null : String.valueOf(value);
  }

  private Set<Id> buildLinkedContactsScopeAccountIds(Account contextAccount) {
    Set<Id> scopedAccountIds = new Set<Id>();
    scopedAccountIds.add(contextAccount.Id);

    try {
      Boolean isHouseholdLaunch = FscRelAccountRepository.isHouseholdRecordTypeDeveloperName(
        contextAccount.RecordType == null
          ? null
          : contextAccount.RecordType.DeveloperName
      );
      Id householdId = treeService.resolveHouseholdId(contextAccount);

      if (isHouseholdLaunch) {
        Set<Id> memberAccountIds = treeService.buildMemberAccountIds(
          householdId,
          contextAccount.Id,
          true
        );
        scopedAccountIds.addAll(memberAccountIds);
        scopedAccountIds.addAll(
          collectAarRelatedAccountIds(memberAccountIds, memberAccountIds)
        );
        return scopedAccountIds;
      }

      scopedAccountIds.addAll(
        collectAarRelatedAccountIds(
          new Set<Id>{ contextAccount.Id },
          new Set<Id>{ contextAccount.Id }
        )
      );
    } catch (Exception error) {
      return scopedAccountIds;
    }

    return scopedAccountIds;
  }

  private Set<Id> collectAarRelatedAccountIds(
    Set<Id> memberAccountIds,
    Set<Id> excludedAccountIds
  ) {
    Set<Id> relatedAccountIds = new Set<Id>();
    Set<String> allowedRecordTypes = new Set<String>();
    allowedRecordTypes.addAll(
      FscRelRelationshipTreeRepository.FAMILY_AAR_RECORD_TYPES
    );
    allowedRecordTypes.addAll(
      FscRelRelationshipTreeRepository.NETWORK_AAR_RECORD_TYPES
    );

    Map<String, List<FscRelHouseholdModels.TreeMemberAccountRelationship>> relationshipsByMemberAccountId = treeService.getMemberRelationshipsByMemberAccountIds(
      memberAccountIds
    );

    if (relationshipsByMemberAccountId == null) {
      return relatedAccountIds;
    }

    for (
      List<FscRelHouseholdModels.TreeMemberAccountRelationship> relationships : relationshipsByMemberAccountId.values()
    ) {
      if (relationships == null) {
        continue;
      }

      for (
        FscRelHouseholdModels.TreeMemberAccountRelationship relationship : relationships
      ) {
        addAarRelatedAccountId(
          relatedAccountIds,
          excludedAccountIds,
          relationship,
          allowedRecordTypes
        );
      }
    }

    return relatedAccountIds;
  }

  private void addAarRelatedAccountId(
    Set<Id> relatedAccountIds,
    Set<Id> excludedAccountIds,
    FscRelHouseholdModels.TreeMemberAccountRelationship relationship,
    Set<String> allowedRecordTypes
  ) {
    if (relationship == null || String.isBlank(relationship.relatedAccountId)) {
      return;
    }

    String normalizedRecordType = FscRelRecordTypeUtils.normalizeAccountRelationRecordTypeDeveloperName(
      relationship.recordTypeDeveloperName
    );

    if (!allowedRecordTypes.contains(normalizedRecordType)) {
      return;
    }

    Id relatedAccountId = Id.valueOf(relationship.relatedAccountId);
    if (excludedAccountIds.contains(relatedAccountId)) {
      return;
    }

    relatedAccountIds.add(relatedAccountId);
  }

  private SignificantEventActionModels.SignificantEventRow buildSignificantEventRow(
    SignificantEventActionModels.LinkedContactRow contactRow
  ) {
    SignificantEventActionModels.SignificantEventRow row = new SignificantEventActionModels.SignificantEventRow();
    row.significantEventId = contactRow.significantEventId;
    row.eventName = contactRow.eventName;
    row.eventType = contactRow.eventType;
    row.otherEventType = contactRow.otherEventType;
    row.startDate = contactRow.startDate;
    row.endDate = contactRow.endDate;
    row.approximateDate = contactRow.approximateDate;
    row.description = contactRow.description;
    row.householdId = contactRow.householdId;
    row.householdName = contactRow.householdName;
    return row;
  }

  private SignificantEventActionModels.LinkedContactRow buildLinkedContactRow(
    Significant_Event_Contact__c participant
  ) {
    SignificantEventActionModels.LinkedContactRow row = new SignificantEventActionModels.LinkedContactRow();
    row.participantId = String.valueOf(participant.Id);
    row.participantName = participant.Name;
    row.accountId = participant.Account__c == null
      ? null
      : String.valueOf(participant.Account__c);
    row.accountName = participant.Account__r == null
      ? null
      : participant.Account__r.Name;

    if (participant.Significant_Event__r != null) {
      Significant_Event__c eventRecord = participant.Significant_Event__r;
      row.significantEventId = participant.Significant_Event__c == null
        ? null
        : String.valueOf(participant.Significant_Event__c);
      row.eventName = eventRecord.Name;
      row.eventType = eventRecord.Event_Type__c;
      row.otherEventType = eventRecord.Other_Event_Type__c;
      row.startDate = formatDate(eventRecord.Start_Date__c);
      row.endDate = formatDate(eventRecord.End_Date_Optional__c);
      row.approximateDate = eventRecord.Approximate_Date__c == true;
      row.description = eventRecord.Description__c;
      row.householdId = eventRecord.Household__c == null
        ? null
        : String.valueOf(eventRecord.Household__c);
      row.householdName = eventRecord.Household__r == null
        ? null
        : eventRecord.Household__r.Name;
      row.financialAdvisorTeamId = eventRecord.Financial_Advisor_Team__c == null
        ? null
        : String.valueOf(eventRecord.Financial_Advisor_Team__c);
      row.financialAdvisorTeamName = eventRecord.Financial_Advisor_Team__r == null
        ? null
        : eventRecord.Financial_Advisor_Team__r.Name;
    }

    return row;
  }
}