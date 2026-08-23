/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-14
 */
public with sharing class SignificantEventActionController {
  private static final SignificantEventActionService SERVICE = new SignificantEventActionService();

  @AuraEnabled(cacheable=true)
  public static SignificantEventActionModels.CreateContext getActionContext(
    Id recordId
  ) {
    try {
      return SERVICE.getActionContext(recordId);
    } catch (Exception error) {
      throw handleError(error);
    }
  }

  @AuraEnabled(cacheable=true)
  public static SignificantEventActionModels.CreateContext getCreateContext(
    Id accountId
  ) {
    try {
      return SERVICE.getCreateContext(accountId);
    } catch (Exception error) {
      throw handleError(error);
    }
  }

  @AuraEnabled(cacheable=true)
  public static SignificantEventActionModels.CreateContext getEditContext(
    Id significantEventId
  ) {
    try {
      return SERVICE.getEditContext(significantEventId);
    } catch (Exception error) {
      throw handleError(error);
    }
  }

  @AuraEnabled(cacheable=true)
  public static List<SignificantEventActionModels.SuggestedContactGroup> getSuggestedLinkedContacts(
    Id householdId,
    Id contextAccountId,
    List<String> selectedAccountIds,
    Boolean isHouseholdLaunch
  ) {
    try {
      return SERVICE.getSuggestedLinkedContacts(
        householdId,
        contextAccountId,
        selectedAccountIds,
        isHouseholdLaunch
      );
    } catch (Exception error) {
      throw handleError(error);
    }
  }

  @AuraEnabled
  public static List<SignificantEventActionModels.LinkedAccountOption> searchNonHouseholdAccounts(
    String searchTerm
  ) {
    try {
      return SERVICE.searchNonHouseholdAccounts(searchTerm);
    } catch (Exception error) {
      throw handleError(error);
    }
  }

  @AuraEnabled
  public static SignificantEventActionModels.SaveResult createSignificantEvent(
    String requestJson
  ) {
    try {
      SignificantEventActionModels.SaveRequest request = parseSaveRequest(
        requestJson
      );
      return SERVICE.createSignificantEvent(request);
    } catch (Exception error) {
      throw handleError(error);
    }
  }

  @AuraEnabled
  public static SignificantEventActionModels.SaveResult updateSignificantEvent(
    String requestJson
  ) {
    try {
      SignificantEventActionModels.SaveRequest request = parseSaveRequest(
        requestJson
      );
      return SERVICE.updateSignificantEvent(request);
    } catch (Exception error) {
      throw handleError(error);
    }
  }

  @AuraEnabled(cacheable=true)
  public static List<SignificantEventActionModels.LinkedContactRow> getLinkedContactsForAccount(
    Id accountId
  ) {
    try {
      return SERVICE.getLinkedContactsForAccount(accountId);
    } catch (Exception error) {
      throw handleError(error);
    }
  }

  @AuraEnabled(cacheable=true)
  public static List<SignificantEventActionModels.SignificantEventRow> getSignificantEventsForAccount(
    Id accountId
  ) {
    try {
      return SERVICE.getSignificantEventsForAccount(accountId);
    } catch (Exception error) {
      throw handleError(error);
    }
  }

  private static SignificantEventActionModels.SaveRequest parseSaveRequest(
    String requestJson
  ) {
    if (String.isBlank(requestJson)) {
      throw new AuraHandledException('Save request is required.');
    }

    return (SignificantEventActionModels.SaveRequest) JSON.deserialize(
      requestJson,
      SignificantEventActionModels.SaveRequest.class
    );
  }

  private static AuraHandledException handleError(Exception error) {
    if (error instanceof AuraHandledException) {
      return (AuraHandledException) error;
    }

    return new AuraHandledException(error.getMessage());
  }
}