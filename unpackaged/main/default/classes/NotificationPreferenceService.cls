/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-03
 *
 * Resolves notification preferences using explicit user, household, and global scopes.
 *
 * Resolution order for recipient U on household H:
 * 1. User+Household override (User__c = U, Household__c = H)
 * 2. User default (User__c = U, Household__c blank)
 * 3. Household setting (Household__c = H, User__c blank)
 * 4. Global default (both blank)
 *
 * Per-channel resolution: when a household-scoped rule exists for H, only channels
 * explicitly configured on that household rule (or a higher user+household override)
 * are used. Lower-scope user defaults and org defaults do not backfill missing channels.
 */
public with sharing class NotificationPreferenceService {
  public enum PreferenceScope {
    ORG_DEFAULT,
    HOUSEHOLD_SETTING,
    USER_DEFAULT,
    USER_HOUSEHOLD_OVERRIDE
  }

  @TestVisible
  private static Map<String, List<Notification_Rule__c>> systemDefaultsByObjectType = new Map<String, List<Notification_Rule__c>>();

  private final NotificationPreferenceRepository preferenceRepository;

  public NotificationPreferenceService() {
    this(new NotificationPreferenceRepository());
  }

  @TestVisible
  private NotificationPreferenceService(
    NotificationPreferenceRepository preferenceRepository
  ) {
    this.preferenceRepository = preferenceRepository;
  }

  public ResolveResult resolve(
    String objectType,
    Id recipientId,
    Id householdId
  ) {
    Map<Id, ResolveResult> resultsByRecipientId = resolveForRecipients(
      objectType,
      new List<Id>{ recipientId },
      householdId
    );
    return resultsByRecipientId.containsKey(recipientId)
      ? resultsByRecipientId.get(recipientId)
      : new ResolveResult(NotificationConstants.SUPPRESSION_NO_PREFERENCE);
  }

  public Map<Id, ResolveResult> resolveForRecipients(
    String objectType,
    List<Id> recipientIds,
    Id householdId
  ) {
    Map<Id, ResolveResult> resultsByRecipientId = new Map<Id, ResolveResult>();
    if (recipientIds == null || recipientIds.isEmpty()) {
      return resultsByRecipientId;
    }

    List<Notification_Rule__c> systemDefaults = selectCachedSystemDefaults(objectType);

    Integer chunkSize = NotificationConstants.MAX_RECIPIENT_IDS_PER_SOQL_IN;
    for (
      Integer startIndex = 0;
      startIndex < recipientIds.size();
      startIndex += chunkSize
    ) {
      Integer endIndex = Math.min(startIndex + chunkSize, recipientIds.size());
      List<Id> recipientIdChunk = NotificationGovernorLimitService.sliceIds(
        recipientIds,
        startIndex,
        endIndex
      );
      Set<Id> recipientIdSet = new Set<Id>(recipientIdChunk);
      List<Notification_Rule__c> scopedPreferences = preferenceRepository.selectActiveScopedPreferencesForRecipients(
        objectType,
        recipientIdSet,
        householdId
      );

      for (Id recipientId : recipientIdChunk) {
        resultsByRecipientId.put(
          recipientId,
          resolveForRecipient(
            scopedPreferences,
            systemDefaults,
            recipientId,
            householdId
          )
        );
      }
    }

    return resultsByRecipientId;
  }

  public Map<Id, Map<String, ResolveResult>> resolveForRecipientsByChannel(
    String objectType,
    List<Id> recipientIds,
    Id householdId
  ) {
    Map<Id, Map<String, ResolveResult>> resultsByRecipientId = new Map<Id, Map<String, ResolveResult>>();

    if (recipientIds == null || recipientIds.isEmpty()) {
      return resultsByRecipientId;
    }

    List<Notification_Rule__c> systemDefaults = selectCachedSystemDefaults(objectType);
    Integer chunkSize = NotificationConstants.MAX_RECIPIENT_IDS_PER_SOQL_IN;

    for (
      Integer startIndex = 0;
      startIndex < recipientIds.size();
      startIndex += chunkSize
    ) {
      Integer endIndex = Math.min(startIndex + chunkSize, recipientIds.size());
      List<Id> recipientIdChunk = NotificationGovernorLimitService.sliceIds(
        recipientIds,
        startIndex,
        endIndex
      );
      Set<Id> recipientIdSet = new Set<Id>(recipientIdChunk);
      List<Notification_Rule__c> scopedPreferences = preferenceRepository.selectActiveScopedPreferencesForRecipients(
        objectType,
        recipientIdSet,
        householdId
      );

      for (Id recipientId : recipientIdChunk) {
        resultsByRecipientId.put(
          recipientId,
          resolveChannelsForRecipient(
            scopedPreferences,
            systemDefaults,
            recipientId,
            householdId
          )
        );
      }
    }

    return resultsByRecipientId;
  }

  /**
   * Forces immediate In_App and Email delivery for pit stop tasks, ignoring user preferences.
   */
  public Map<Id, Map<String, ResolveResult>> buildPitStopImmediateChannelResultsForRecipients(
    List<Id> recipientIds
  ) {
    Map<Id, Map<String, ResolveResult>> resultsByRecipientId = new Map<Id, Map<String, ResolveResult>>();

    if (recipientIds == null || recipientIds.isEmpty()) {
      return resultsByRecipientId;
    }

    Notification_Rule__c seedRule = selectPitStopBypassSeedRule();
    Map<String, ResolveResult> channelResults = buildPitStopImmediateChannelResults(
      seedRule
    );

    for (Id recipientId : recipientIds) {
      resultsByRecipientId.put(recipientId, channelResults);
    }

    return resultsByRecipientId;
  }

  @TestVisible
  private Map<String, ResolveResult> buildPitStopImmediateChannelResults(
    Notification_Rule__c seedRule
  ) {
    Map<String, ResolveResult> resultsByChannel = new Map<String, ResolveResult>();

    if (seedRule == null) {
      return resultsByChannel;
    }

    for (String channelName : NotificationConstants.CHANNEL_ORDER) {
      Notification_Rule__c channelPreference = seedRule.clone(false, true, false, false);
      channelPreference.Frequency__c = NotificationConstants.FREQUENCY_IMMEDIATE;
      resultsByChannel.put(
        channelName,
        new ResolveResult(
          channelPreference,
          NotificationConstants.PREFERENCE_SCOPE_PIT_STOP_BYPASS
        )
      );
    }

    return resultsByChannel;
  }

  private Notification_Rule__c selectPitStopBypassSeedRule() {
    List<Notification_Rule__c> systemDefaults = preferenceRepository.selectActiveSystemDefaults(
      NotificationConstants.OBJECT_TYPE_TASK
    );

    return systemDefaults.isEmpty() ? null : systemDefaults[0];
  }

  private Map<String, ResolveResult> resolveChannelsForRecipient(
    List<Notification_Rule__c> scopedPreferences,
    List<Notification_Rule__c> systemDefaults,
    Id recipientId,
    Id householdId
  ) {
    Map<String, ResolveResult> resultsByChannel = new Map<String, ResolveResult>();
    List<Notification_Rule__c> candidatePreferences = filterPreferencesForHouseholdGovernance(
      buildCandidatePreferences(
        scopedPreferences,
        systemDefaults,
        recipientId,
        householdId
      ),
      recipientId,
      householdId
    );

    for (String channelName : NotificationConstants.CHANNEL_ORDER) {
      Notification_Rule__c preference = selectBestPreferenceForChannel(
        candidatePreferences,
        channelName,
        recipientId,
        householdId
      );

      if (preference == null) {
        continue;
      }

      PreferenceScope scope = classifyScope(preference, recipientId, householdId);
      resultsByChannel.put(
        channelName,
        new ResolveResult(preference, scope.name())
      );
    }

    return resultsByChannel;
  }

  private List<Notification_Rule__c> buildCandidatePreferences(
    List<Notification_Rule__c> scopedPreferences,
    List<Notification_Rule__c> systemDefaults,
    Id recipientId,
    Id householdId
  ) {
    List<Notification_Rule__c> candidatePreferences = filterScopedPreferences(
      scopedPreferences,
      recipientId,
      householdId
    );

    if (systemDefaults != null) {
      candidatePreferences.addAll(systemDefaults);
    }

    return candidatePreferences;
  }

  @TestVisible
  private static List<Notification_Rule__c> filterPreferencesForHouseholdGovernance(
    List<Notification_Rule__c> preferences,
    Id recipientId,
    Id householdId
  ) {
    if (householdId == null || preferences == null || preferences.isEmpty()) {
      return preferences;
    }

    Boolean hasUserHouseholdOverride = false;
    Boolean hasHouseholdSetting = false;

    for (Notification_Rule__c preference : preferences) {
      PreferenceScope scope = classifyScope(preference, recipientId, householdId);

      if (scope == PreferenceScope.USER_HOUSEHOLD_OVERRIDE) {
        hasUserHouseholdOverride = true;
      } else if (scope == PreferenceScope.HOUSEHOLD_SETTING) {
        hasHouseholdSetting = true;
      }
    }

    if (!hasUserHouseholdOverride && !hasHouseholdSetting) {
      return preferences;
    }

    List<Notification_Rule__c> governedPreferences = new List<Notification_Rule__c>();

    for (Notification_Rule__c preference : preferences) {
      PreferenceScope scope = classifyScope(preference, recipientId, householdId);

      if (scope == null) {
        continue;
      }

      if (hasUserHouseholdOverride) {
        if (scope == PreferenceScope.USER_HOUSEHOLD_OVERRIDE) {
          governedPreferences.add(preference);
        }

        continue;
      }

      if (
        scope == PreferenceScope.HOUSEHOLD_SETTING ||
        scope == PreferenceScope.USER_HOUSEHOLD_OVERRIDE
      ) {
        governedPreferences.add(preference);
      }
    }

    return governedPreferences;
  }

  private ResolveResult resolveForRecipient(
    List<Notification_Rule__c> scopedPreferences,
    List<Notification_Rule__c> systemDefaults,
    Id recipientId,
    Id householdId
  ) {
    List<Notification_Rule__c> scopedPreferencesForRecipient = filterScopedPreferences(
      scopedPreferences,
      recipientId,
      householdId
    );
    Notification_Rule__c scopedPreference = selectBestPreference(
      scopedPreferencesForRecipient,
      recipientId,
      householdId
    );

    if (scopedPreference != null) {
      PreferenceScope scopedResult = classifyScope(
        scopedPreference,
        recipientId,
        householdId
      );
      return new ResolveResult(scopedPreference, scopedResult.name());
    }

    Notification_Rule__c systemDefault = selectBestPreference(
      systemDefaults,
      recipientId,
      householdId
    );
    if (systemDefault != null) {
      return new ResolveResult(systemDefault, PreferenceScope.ORG_DEFAULT.name());
    }

    return new ResolveResult(NotificationConstants.SUPPRESSION_NO_PREFERENCE);
  }

  public static PreferenceScope determineScope(
    Notification_Rule__c preference
  ) {
    if (preference.User__c != null && preference.Household__c != null) {
      return PreferenceScope.USER_HOUSEHOLD_OVERRIDE;
    }

    if (preference.User__c != null && preference.Household__c == null) {
      return PreferenceScope.USER_DEFAULT;
    }

    if (preference.Household__c != null && preference.User__c == null) {
      return PreferenceScope.HOUSEHOLD_SETTING;
    }

    return PreferenceScope.ORG_DEFAULT;
  }

  @TestVisible
  private static List<Notification_Rule__c> selectCachedSystemDefaults(
    String objectType
  ) {
    if (!systemDefaultsByObjectType.containsKey(objectType)) {
      systemDefaultsByObjectType.put(
        objectType,
        new NotificationPreferenceRepository().selectActiveSystemDefaults(
          objectType
        )
      );
    }

    return systemDefaultsByObjectType.get(objectType);
  }

  @TestVisible
  public static void clearSystemDefaultCache() {
    systemDefaultsByObjectType.clear();
  }

  @TestVisible
  private static List<Notification_Rule__c> filterScopedPreferences(
    List<Notification_Rule__c> preferences,
    Id recipientId,
    Id householdId
  ) {
    List<Notification_Rule__c> scopedPreferences = new List<Notification_Rule__c>();

    for (Notification_Rule__c preference : preferences) {
      Boolean isUserMatch =
        preference.User__c == null || preference.User__c == recipientId;
      Boolean isHouseholdMatch =
        preference.Household__c == null ||
        (householdId != null && preference.Household__c == householdId);

      if (isUserMatch && isHouseholdMatch) {
        scopedPreferences.add(preference);
      }
    }

    return scopedPreferences;
  }

  @TestVisible
  private static PreferenceScope classifyScope(
    Notification_Rule__c preference,
    Id recipientId,
    Id householdId
  ) {
    Boolean isUserMatch = preference.User__c == recipientId;
    Boolean isHouseholdMatch =
      householdId != null &&
      preference.Household__c == householdId;

    if (isUserMatch && isHouseholdMatch) {
      return PreferenceScope.USER_HOUSEHOLD_OVERRIDE;
    }

    if (isUserMatch && preference.Household__c == null) {
      return PreferenceScope.USER_DEFAULT;
    }

    if (isHouseholdMatch && preference.User__c == null) {
      return PreferenceScope.HOUSEHOLD_SETTING;
    }

    if (preference.User__c == null && preference.Household__c == null) {
      return PreferenceScope.ORG_DEFAULT;
    }

    return null;
  }

  @TestVisible
  private static Integer scopeRank(PreferenceScope scope) {
    switch on scope {
      when USER_HOUSEHOLD_OVERRIDE {
        return 3;
      }
      when USER_DEFAULT {
        return 2;
      }
      when HOUSEHOLD_SETTING {
        return 1;
      }
      when ORG_DEFAULT {
        return 0;
      }
      when else {
        return -1;
      }
    }
  }

  private Notification_Rule__c selectBestPreference(
    List<Notification_Rule__c> preferences,
    Id recipientId,
    Id householdId
  ) {
    Integer bestRank = -1;
    Notification_Rule__c bestPreference;

    for (Notification_Rule__c preference : preferences) {
      PreferenceScope scope = classifyScope(
        preference,
        recipientId,
        householdId
      );
      if (scope == null) {
        continue;
      }

      Integer rank = scopeRank(scope);
      if (bestPreference == null || rank > bestRank) {
        bestRank = rank;
        bestPreference = preference;
        continue;
      }

      if (rank == bestRank && hasHigherPriority(preference, bestPreference)) {
        bestPreference = preference;
      }
    }

    return bestPreference;
  }

  private Notification_Rule__c selectBestPreferenceForChannel(
    List<Notification_Rule__c> preferences,
    String channelName,
    Id recipientId,
    Id householdId
  ) {
    Integer bestRank = -1;
    Notification_Rule__c bestPreference;

    for (Notification_Rule__c preference : preferences) {
      if (
        !NotificationChannelUtils.includesChannel(
          preference.Channel__c,
          channelName
        )
      ) {
        continue;
      }

      PreferenceScope scope = classifyScope(
        preference,
        recipientId,
        householdId
      );

      if (scope == null) {
        continue;
      }

      Integer rank = scopeRank(scope);

      if (bestPreference == null || rank > bestRank) {
        bestRank = rank;
        bestPreference = preference;
        continue;
      }

      if (rank == bestRank && hasHigherPriority(preference, bestPreference)) {
        bestPreference = preference;
      }
    }

    return bestPreference;
  }

  private Boolean hasHigherPriority(
    Notification_Rule__c candidate,
    Notification_Rule__c incumbent
  ) {
    Decimal candidatePriority = candidate.Priority__c == null
      ? 0
      : candidate.Priority__c;
    Decimal incumbentPriority = incumbent.Priority__c == null
      ? 0
      : incumbent.Priority__c;
    return candidatePriority > incumbentPriority;
  }

  public class ResolveResult {
    @AuraEnabled
    public Boolean isAllowed { get; private set; }
    @AuraEnabled
    public String suppressionReason { get; private set; }
    @AuraEnabled
    public Notification_Rule__c preference { get; private set; }
    @AuraEnabled
    public String resolvedScope { get; private set; }

    public ResolveResult(
      Notification_Rule__c preference,
      String resolvedScope
    ) {
      isAllowed = true;
      this.preference = preference;
      this.resolvedScope = resolvedScope;
    }

    public ResolveResult(String suppressionReason) {
      isAllowed = false;
      this.suppressionReason = suppressionReason;
    }
  }
}