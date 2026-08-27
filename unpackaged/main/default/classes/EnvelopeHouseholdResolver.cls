/**
 * Resolves the household Account behind an Envelope, so every Case the envelope app opens carries
 * the household the envelope belongs to.
 *
 * The household is read from Envelope__c.Household__c first, then falls back to the envelope's
 * Household-record-type junction row (Envelope_Content__c.Account__c). Both create paths need
 * covering: only createWizEnvelopeV2 populates Envelope__c.Household__c, while every path — the
 * older createWizEnvelope included — inserts a household junction row. See the note on
 * EnvelopeLandingApex.EnvelopeContents for the same convention read the other direction.
 */
public with sharing class EnvelopeHouseholdResolver {

    // Matches EnvelopeLandingApex; the household member's Account record type.
    private static final String HOUSEHOLD_RECORD_TYPE_DEVELOPER_NAME = 'Household';

    // The household Id for the given envelope, or null when the envelope is missing or has no
    // resolvable household. Callers with a secondary source (e.g. the servicing Financial Account)
    // fall back to it on null rather than stamping a null household. Accepts a String so both the
    // Id-typed and String-typed envelope references the callers hold pass without coercion throwing
    // on a blank value.
    public static Id resolveHouseholdId(String envelopeId) {
        if (String.isBlank(envelopeId)) {
            return null;
        }
        List<Envelope__c> envelopes = [
            SELECT Household__c,
                (SELECT Account__c
                 FROM Wizard_Envelope_Records__r
                 WHERE Account__c != null
                 AND Account__r.RecordType.DeveloperName = :HOUSEHOLD_RECORD_TYPE_DEVELOPER_NAME
                 ORDER BY CreatedDate ASC
                 LIMIT 1)
            FROM Envelope__c
            WHERE Id = :envelopeId
            LIMIT 1
        ];
        if (envelopes.isEmpty()) {
            return null;
        }
        Envelope__c envelope = envelopes[0];
        if (envelope.Household__c != null) {
            return envelope.Household__c;
        }
        return envelope.Wizard_Envelope_Records__r.isEmpty()
            ? null
            : envelope.Wizard_Envelope_Records__r[0].Account__c;
    }
}