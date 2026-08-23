/**
 * When Case.Pitstop_Start__c is cleared, accumulate business minutes into Pitstop_Total_Minutes__c
 * using BusinessHours.diff.
 *
 * Uses oldMap for BusinessHoursId / EntitlementId / existing total because partial Case updates
 * leave those fields null on Trigger.new.
 */
public with sharing class CasePitStopMinutesService {
    @TestVisible
    private static Id testBusinessHoursIdOverride;

    /** When true, resolveBusinessHoursId always returns null (for coverage of skip path). */
    @TestVisible
    private static Boolean testForceNoBusinessHours = false;

    private static String cachedBusinessHoursName;
    private static Id cachedCmdtBusinessHoursId;

    @TestVisible
    private static void resetCachesForTest() {
        cachedBusinessHoursName = null;
        cachedCmdtBusinessHoursId = null;
        testBusinessHoursIdOverride = null;
        testForceNoBusinessHours = false;
    }

    /** Inject blank CMDT BH name so getCmdtBusinessHoursId returns null after cache miss. */
    @TestVisible
    private static void setCachedBusinessHoursNameForTest(String name) {
        cachedBusinessHoursName = name;
        cachedCmdtBusinessHoursId = null;
    }

    public static void accumulateMinutesOnStopClear(List<Case> newCases, Map<Id, Case> oldMap) {
        if (newCases == null || newCases.isEmpty() || oldMap == null) {
            return;
        }

        List<Case> candidates = new List<Case>();
        Set<Id> entitlementIds = new Set<Id>();
        for (Case newCase : newCases) {
            Case oldCase = oldMap.get(newCase.Id);
            if (oldCase == null) {
                continue;
            }
            if (oldCase.Pitstop_Start__c != null && newCase.Pitstop_Start__c == null) {
                candidates.add(newCase);
                Id entitlementId = newCase.EntitlementId != null
                    ? newCase.EntitlementId
                    : oldCase.EntitlementId;
                if (entitlementId != null) {
                    entitlementIds.add(entitlementId);
                }
            }
        }
        if (candidates.isEmpty()) {
            return;
        }

        Map<Id, Id> entitlementIdToBusinessHoursId = new Map<Id, Id>();
        if (!entitlementIds.isEmpty()) {
            for (Entitlement entitlementRecord : [
                SELECT Id, BusinessHoursId
                FROM Entitlement
                WHERE Id IN :entitlementIds
            ]) {
                entitlementIdToBusinessHoursId.put(entitlementRecord.Id, entitlementRecord.BusinessHoursId);
            }
        }

        Datetime endTime = System.now();
        for (Case newCase : candidates) {
            Case oldCase = oldMap.get(newCase.Id);
            Id businessHoursId = resolveBusinessHoursId(newCase, oldCase, entitlementIdToBusinessHoursId);
            if (businessHoursId == null) {
                System.debug(
                    LoggingLevel.WARN,
                    'CasePitStopMinutesService: no BusinessHoursId for Case ' + newCase.Id
                );
                continue;
            }

            Long milliseconds = BusinessHours.diff(
                businessHoursId,
                oldCase.Pitstop_Start__c,
                endTime
            );
            Decimal minutes = Decimal.valueOf(milliseconds) / 60000;
            Decimal existing = oldCase.Pitstop_Total_Minutes__c == null
                ? 0
                : oldCase.Pitstop_Total_Minutes__c;
            if (newCase.Pitstop_Total_Minutes__c != null
                && newCase.Pitstop_Total_Minutes__c != oldCase.Pitstop_Total_Minutes__c) {
                existing = newCase.Pitstop_Total_Minutes__c;
            }
            newCase.Pitstop_Total_Minutes__c = existing + minutes.setScale(2);
        }
    }

    private static Id resolveBusinessHoursId(
        Case newCase,
        Case oldCase,
        Map<Id, Id> entitlementIdToBusinessHoursId
    ) {
        if (testForceNoBusinessHours == true) {
            return null;
        }
        if (testBusinessHoursIdOverride != null) {
            return testBusinessHoursIdOverride;
        }
        if (newCase.BusinessHoursId != null) {
            return newCase.BusinessHoursId;
        }
        if (oldCase.BusinessHoursId != null) {
            return oldCase.BusinessHoursId;
        }
        Id entitlementId = newCase.EntitlementId != null
            ? newCase.EntitlementId
            : oldCase.EntitlementId;
        if (entitlementId != null
            && entitlementIdToBusinessHoursId.containsKey(entitlementId)
            && entitlementIdToBusinessHoursId.get(entitlementId) != null) {
            return entitlementIdToBusinessHoursId.get(entitlementId);
        }
        return getCmdtBusinessHoursId();
    }

    private static Id getCmdtBusinessHoursId() {
        if (cachedCmdtBusinessHoursId != null) {
            return cachedCmdtBusinessHoursId;
        }
        String bhName = getBusinessHoursName();
        if (String.isBlank(bhName)) {
            return null;
        }
        List<BusinessHours> businessHoursList = [
            SELECT Id
            FROM BusinessHours
            WHERE Name = :bhName
            LIMIT 1
        ];
        cachedCmdtBusinessHoursId = businessHoursList.isEmpty() ? null : businessHoursList[0].Id;
        return cachedCmdtBusinessHoursId;
    }

    private static String getBusinessHoursName() {
        if (cachedBusinessHoursName != null) {
            return cachedBusinessHoursName;
        }
        List<Case_Entitlement_Values__mdt> entitlementValues = [
            SELECT Business_Hours__c
            FROM Case_Entitlement_Values__mdt
            WHERE Business_Hours__c != null
            LIMIT 1
        ];
        cachedBusinessHoursName = entitlementValues.isEmpty()
            ? ''
            : entitlementValues[0].Business_Hours__c;
        return cachedBusinessHoursName;
    }
}