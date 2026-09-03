/**
 * WebinarLifecycle — the ONE derivation of a webinar's lifecycle status.
 *
 * A webinar is a Resource__c with Resource_Type__c = 'Webinar' that keeps that
 * type forever (its slug, links, and junction rows must stay stable). Status is
 * computed, never stored:
 *   Upcoming — Event_Datetime__c is in the future
 *   Past     — the date has passed and no recording exists yet
 *   Recorded — the date has passed and a recording exists (Video_Embed_URL__c
 *              or the newest attached file, the same mechanisms Video and
 *              file-backed types already use)
 *
 * Called from ResourceCenterService (cards, detail, agenda),
 * ResourceAdminController (admin list chips), and UnifiedSearchService (search
 * hits). LWC never re-derives — it reads `webinarStatus` off the DTOs. Client
 * mirror of the vocabulary: lwc/rcConstants WEBINAR_STATUS_* — change both
 * together.
 *
 * `now` is always passed in so a caller can bind the same instant into its
 * SOQL and into the derivation (no "just turned Upcoming between the query and
 * the loop" edge, and tests pick the boundary explicitly).
 */
public with sharing class WebinarLifecycle {
    public static final String TYPE_WEBINAR = 'Webinar';
    public static final String UPCOMING = 'Upcoming';
    public static final String PAST = 'Past';
    public static final String RECORDED = 'Recorded';

    public static Boolean isWebinar(String resourceType) {
        return resourceType == TYPE_WEBINAR;
    }

    /** A recording is an embed URL or an attached file — either is enough. */
    public static Boolean hasRecording(String videoEmbedUrl, Boolean hasFile) {
        return String.isNotBlank(videoEmbedUrl) || hasFile == true;
    }

    /**
     * Upcoming strictly after `now`; at exactly `now` the event has started,
     * so it is Past/Recorded. Null eventAt (unreachable through the admin
     * console — the validation rule and saveResource both require it) yields
     * null: no status, and the UI falls back to the plain resource treatment.
     */
    public static String status(Datetime eventAt, Boolean hasRecording, Datetime now) {
        if (eventAt == null) {
            return null;
        }
        if (eventAt > now) {
            return UPCOMING;
        }
        return hasRecording == true ? RECORDED : PAST;
    }

    /**
     * Status for a queried row, or null for non-webinars. The row must carry
     * Resource_Type__c, Event_Datetime__c, and Video_Embed_URL__c; `hasFile` is
     * the caller's ContentDocumentLink lookup (ResourceCenterService.fileInfoByResource).
     */
    public static String statusFor(Resource__c r, Boolean hasFile, Datetime now) {
        if (r == null || !isWebinar(r.Resource_Type__c)) {
            return null;
        }
        return status(r.Event_Datetime__c, hasRecording(r.Video_Embed_URL__c, hasFile), now);
    }
}