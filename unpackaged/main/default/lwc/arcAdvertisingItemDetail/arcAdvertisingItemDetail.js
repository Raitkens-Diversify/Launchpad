/**
 * Rich Advertising Item detail page for Experience sites, built the same way
 * arcCaseDetail/arcProductDetail were: read the real Lightning record page
 * rather than guess, then reproduce what it shows.
 *
 * Structure comes from AdvertisingItemRecordPage.flexipage on Cosmos --
 * confirmed the actually-assigned page (not a same-named decoy) via the
 * object's own actionOverrides, which name it directly for the View action --
 * retrieved and parsed directly (label/visibilityRule/field list per
 * section, and per-field sub-conditions), not eyeballed:
 *   - Highlights: Advertising_Item_Highlights compact layout (Name, Review
 *     Case, Financial Advisor Team, Status, Advertising Type, Date of
 *     Intended First Use) -- confirmed against what the user described
 *     seeing live on a real record.
 *   - Information / System Information: the two always-shown sections.
 *   - 13 Advertising_Type__c-conditional sections, each with the reference
 *     page's own exact visibility rule and field list, including several
 *     fields with a SECOND, nested condition of their own (e.g.
 *     x3rd_Party__c only when Produced_by_a_3rd_Party__c = "Yes") --
 *     rendered outside each section's lightning-record-form since that
 *     component can't conditionally hide one field within a fixed list.
 *   - 6 related lists tied to specific types: 3 "Cost Line Item" child
 *     objects (Event_Cost_Line_Item__c, Radio_TV_Ad_Cost_Line_Item__c,
 *     Sponsorship_Cost_Line_Item__c) and 3 SELF-referential "Advertising
 *     Items Related to X" lists (other Advertising_Item__c records whose
 *     own Event__c/Public_Appearance__c/Radio_TV_Ad__c lookup points back
 *     at this one) -- confirmed via field metadata, not assumed from the
 *     related list's plain-English label.
 *   - Files: the reference page's AttachedContentDocuments related list.
 *   - Activity: the reference page uses runtime_sales_activities:
 *     activityPanel, Salesforce's native Log-a-Call/Task/Event composer +
 *     feed -- not an LWR-embeddable component, and not something to clone
 *     wholesale. Built as a read-only Tasks/Events rail instead (no New
 *     Task/New Event composer, per explicit confirmation -- just the
 *     lists), reusing c/arcRelatedList exactly as every other rail card in
 *     ARC does.
 *   - History: the flexipage's own History related list (standard field
 *     history tracking), as a full-width paginated table matching Related
 *     Products' own c/arcDataTable treatment -- fetched through
 *     ArcCaseFeedController.getRecordHistoryPage, which resolves
 *     Advertising_Item__c -> Advertising_Item__History generically (built
 *     for Case, never made Case-only). No row links: the User column would
 *     be the only sensible target and ARC has no User detail route today.
 */
import { LightningElement, api, wire } from "lwc";
import { NavigationMixin, CurrentPageReference } from "lightning/navigation";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import { resolveRecordIdFromPageReference } from "c/recordNavigationUtils";
import {
  buildExperienceRecordPath,
  buildRecordNavigationReference
} from "c/recordNavigationCommunityUtils";
import getRecordHistoryPage from "@salesforce/apex/ArcCaseFeedController.getRecordHistoryPage";

const OBJECT_API_NAME = "Advertising_Item__c";

/**
 * Date, Field, User, Original Value, New Value -- the exact column order
 * requested, matching Lightning's own History related list. No isLink: the
 * User column would be the only sensible target and ARC has no User detail
 * route today, so every row stays plain text.
 */
const HISTORY_COLUMNS = [
  { label: "Date", fieldName: "createdDate", type: "date" },
  { label: "Field", fieldName: "fieldLabel" },
  { label: "User", fieldName: "actorName" },
  { label: "Original Value", fieldName: "oldValue" },
  { label: "New Value", fieldName: "newValue" }
];
const HISTORY_PAGE_SIZE = 25;

const mapHistoryEntries = (entries) =>
  (entries || []).map((entry) => ({
    id: entry.id,
    createdDate: entry.createdDate,
    fieldLabel: entry.fieldLabel,
    actorName: entry.actorName || "Unknown user",
    oldValue: entry.isCreation ? "" : entry.oldValue,
    newValue: entry.isCreation ? "Created." : entry.newValue
  }));

const HEADER_FIELDS = [
  "Name",
  "Status__c",
  "Advertising_Type__c",
  "Financial_Advisor_Team__r.Name",
  "Date_of_Intended_First_Use__c",
  "Review_Case__c",
  "Review_Case__r.CaseNumber"
];

/**
 * System Information -- read as plain relationship paths rather than through
 * lightning-record-form. Passing CreatedById/LastModifiedById straight to
 * record-form throws "Expected '.' in all qualified names: LastModifiedById
 * is invalid"; arcRelatedProductQuickView hit the same UI API restriction and
 * worked around it the same way, reading CreatedBy.Name/LastModifiedBy.Name
 * through getRecord instead.
 */
const SYSTEM_INFO_FIELDS = ["CreatedBy.Name", "LastModifiedBy.Name"];

/** Information section -- always shown. */
const INFORMATION_FIELDS = [
  "Advertising_Type__c",
  "Intended_Audience__c",
  "Financial_Advisor_Team__c",
  "Date_of_Intended_First_Use__c",
  "Submission_Notes__c"
];

/**
 * The fields behind every section's own condition, plus every field that
 * has a nested sub-condition of its own and every self-referential lookup
 * rendered as a cross-record link -- fetched alongside the header fields so
 * one getRecord wire covers everything the template's own lwc:if gates and
 * plain-text (non-form) rows need.
 */
const CONDITION_FIELDS = [
  "Produced_by_a_3rd_Party__c",
  "x3rd_Party__c",
  "Include_Raffles_Gifts_etc__c",
  "Raffles_Gifts_Explanation__c",
  "Participate_in_Drafting_Content__c",
  "Providing_Additional_Commentary__c",
  "Do_you_have_detailed_talking_points__c",
  "Detailed_Talking_Points__c",
  "Has_Public_Appearance__c",
  "Public_Appearance__c",
  "Public_Appearance__r.Name",
  "hasSocialMediaProfile__c",
  "Social_Media_Profile__c",
  "Social_Media_Profile__r.Name",
  "Has_Radio_TV__c",
  "Radio_TV_Ad__c",
  "Radio_TV_Ad__r.Name"
];

const ALL_FIELDS = [
  ...new Set([
    ...HEADER_FIELDS,
    ...INFORMATION_FIELDS,
    ...CONDITION_FIELDS,
    ...SYSTEM_INFO_FIELDS
  ])
].map((path) => `${OBJECT_API_NAME}.${path}`);

/** Section field lists -- see the class doc comment for where these came from. */
const SECTION_FIELDS = {
  brochure: ["Produced_by_a_3rd_Party__c", "FINRA_Review_Letter__c"],
  event: [
    "Event_Type__c",
    "Event_Location__c",
    "Include_Raffles_Gifts_etc__c",
    "Estimated_Cost_of_Event__c",
    "Date_of_Event__c",
    "Approximate_Number_of_Attendees__c",
    "Event_Paid_By_Sponsors__c"
  ],
  groupEmail: ["Email_Address_Sent_From__c"],
  newsletter: ["Produced_by_a_3rd_Party__c"],
  periodical: ["Participate_in_Drafting_Content__c"],
  presentation: ["Produced_by_a_3rd_Party__c", "FINRA_Review_Letter__c"],
  publicAppearance: [
    "Public_Appearance_Location__c",
    "Do_you_have_detailed_talking_points__c",
    "Public_Appearance_Date__c"
  ],
  radioTvAd: ["Someone_Else_Paying__c"],
  seminar: [
    "Produced_by_a_3rd_Party__c",
    "FINRA_Review_Letter__c",
    "x3rd_Party__c"
  ],
  socialMediaContent: ["Social_Media_Profile__c", "Repost_Link__c"],
  socialMediaProfile: ["Social_Media_Platform__c", "Link_to_Profile__c"],
  sponsorship: ["Someone_Else_Paying__c"],
  videoAudio: ["Where_will_it_be_Posted__c"],
  website: ["Link_to_Website__c", "Website_Password__c", "Website_Username__c"]
};

export default class ArcAdvertisingItemDetail extends NavigationMixin(
  LightningElement
) {
  recordId;
  errorMessage;
  _record;

  historyRows = [];
  historyError;
  historyHasMore = false;
  isLoadingMoreHistory = false;
  _historyRequested = false;
  _historyLoaded = false;
  /** Where the next loadmore fetch should pick up -- advances by HISTORY_PAGE_SIZE each batch. */
  _historyOffset = 0;

  @wire(CurrentPageReference)
  wiredPageReference(pageRef) {
    const resolved = resolveRecordIdFromPageReference(pageRef, OBJECT_API_NAME);
    if (resolved && resolved !== this.recordId) {
      this.recordId = resolved;
    }
  }

  @wire(getRecord, { recordId: "$recordId", fields: ALL_FIELDS })
  wiredRecord({ data, error }) {
    if (data) {
      this._record = data;
      this.errorMessage = undefined;
    } else if (error) {
      this._record = undefined;
      this.errorMessage =
        error?.body?.message ||
        "Unable to load this advertising item right now.";
    }
  }

  @wire(getRecordHistoryPage, {
    recordId: "$recordId",
    objectApiName: OBJECT_API_NAME,
    offsetValue: 0,
    pageSize: HISTORY_PAGE_SIZE
  })
  wiredHistory({ data, error }) {
    this._historyRequested = true;
    if (data) {
      this._historyLoaded = true;
      this.historyRows = mapHistoryEntries(data.entries);
      this.historyHasMore = data.hasMore === true;
      this._historyOffset = HISTORY_PAGE_SIZE;
      this.historyError = undefined;
    } else if (error) {
      this._historyLoaded = true;
      this.historyRows = [];
      this.historyHasMore = false;
      this.historyError = "Unable to load the history for this record.";
    }
  }

  get isLoading() {
    return !this._record && !this.errorMessage;
  }

  get hasDetail() {
    return Boolean(this._record);
  }

  get objectApiName() {
    return OBJECT_API_NAME;
  }

  // ---- History (full-width paginated table) -----------------------------

  get historyColumns() {
    return HISTORY_COLUMNS;
  }

  get isHistoryLoading() {
    return (
      this._historyRequested && Boolean(this.recordId) && !this._historyLoaded
    );
  }

  /**
   * arcDataTable's own loadmore event -- fires when the reader pages past
   * what's currently loaded while hasMoreRows is true, matching Related
   * Products' own handleRelatedProductsLoadMore exactly.
   */
  async handleHistoryLoadMore() {
    if (this.isLoadingMoreHistory || !this.historyHasMore) {
      return;
    }

    this.isLoadingMoreHistory = true;

    try {
      const result = await getRecordHistoryPage({
        recordId: this.recordId,
        objectApiName: OBJECT_API_NAME,
        offsetValue: this._historyOffset,
        pageSize: HISTORY_PAGE_SIZE
      });
      this.historyRows = [
        ...this.historyRows,
        ...mapHistoryEntries(result?.entries)
      ];
      this._historyOffset += HISTORY_PAGE_SIZE;
      this.historyHasMore = result?.hasMore === true;
    } catch (error) {
      this.historyError =
        error?.body?.message || "Unable to load more history right now.";
    } finally {
      this.isLoadingMoreHistory = false;
    }
  }

  fieldValue(path) {
    return this._record
      ? getFieldValue(this._record, `${OBJECT_API_NAME}.${path}`)
      : undefined;
  }

  // ---- Header ---------------------------------------------------------

  get itemName() {
    return this.fieldValue("Name");
  }

  get statusValue() {
    return this.fieldValue("Status__c");
  }

  get hasStatus() {
    return Boolean(this.statusValue);
  }

  get advertisingTypeValue() {
    return this.fieldValue("Advertising_Type__c");
  }

  get hasAdvertisingType() {
    return Boolean(this.advertisingTypeValue);
  }

  get financialAdvisorTeamName() {
    return this.fieldValue("Financial_Advisor_Team__r.Name");
  }

  get hasFinancialAdvisorTeam() {
    return Boolean(this.financialAdvisorTeamName);
  }

  get dateOfIntendedFirstUseValue() {
    return this.fieldValue("Date_of_Intended_First_Use__c");
  }

  get hasDateOfIntendedFirstUse() {
    return Boolean(this.dateOfIntendedFirstUseValue);
  }

  get reviewCaseId() {
    return this.fieldValue("Review_Case__c");
  }

  get reviewCaseNumber() {
    return this.fieldValue("Review_Case__r.CaseNumber");
  }

  get hasReviewCase() {
    return Boolean(this.reviewCaseId);
  }

  get reviewCaseUrl() {
    return this.reviewCaseId
      ? buildExperienceRecordPath(this.reviewCaseId, "Case")
      : "";
  }

  handleReviewCaseClick(event) {
    event.preventDefault();
    // No popup to close on this page -- straight navigation, same as any
    // other cross-record link on a full detail page (contrast the Related
    // Products quick-view popup, which has to close itself first).
    this.navigateToRecord(this.reviewCaseId, "Case");
  }

  navigateToRecord(recordId, objectApiName) {
    if (!recordId) {
      return;
    }

    const pageReference = buildRecordNavigationReference(
      recordId,
      objectApiName
    );

    if (!pageReference) {
      return;
    }

    this[NavigationMixin.Navigate](pageReference);
  }

  get informationFields() {
    return INFORMATION_FIELDS;
  }

  // ---- System Information (plain reads -- see SYSTEM_INFO_FIELDS) ------

  get createdByName() {
    return this.fieldValue("CreatedBy.Name");
  }

  get lastModifiedByName() {
    return this.fieldValue("LastModifiedBy.Name");
  }

  // ---- Advertising_Type__c section gates -------------------------------

  get isBrochureType() {
    return this.advertisingTypeValue === "Brochure/Worksheet/Pamphlet";
  }

  get isEventType() {
    return this.advertisingTypeValue === "Event";
  }

  get isGroupEmailType() {
    return this.advertisingTypeValue === "Group Email";
  }

  get isNewsletterType() {
    return this.advertisingTypeValue === "Newsletter/Circular";
  }

  get isPeriodicalType() {
    return this.advertisingTypeValue === "Periodical Print/Reprint";
  }

  get isPresentationType() {
    return this.advertisingTypeValue === "Presentation";
  }

  get isPublicAppearanceType() {
    return this.advertisingTypeValue === "Public Appearance";
  }

  get isRadioTvAdType() {
    return this.advertisingTypeValue === "Radio/TV Ad";
  }

  get isSeminarType() {
    return this.advertisingTypeValue === "Seminar Handout";
  }

  get isSocialMediaContentType() {
    return this.advertisingTypeValue === "Social Media Content";
  }

  get isSocialMediaProfileType() {
    return this.advertisingTypeValue === "Social Media Profile";
  }

  get isSponsorshipType() {
    return this.advertisingTypeValue === "Sponsorship";
  }

  get isVideoAudioType() {
    return this.advertisingTypeValue === "Video/Audio";
  }

  get isWebsiteType() {
    return this.advertisingTypeValue === "Website";
  }

  get brochureFields() {
    return SECTION_FIELDS.brochure;
  }

  get eventFields() {
    return SECTION_FIELDS.event;
  }

  get groupEmailFields() {
    return SECTION_FIELDS.groupEmail;
  }

  get newsletterFields() {
    return SECTION_FIELDS.newsletter;
  }

  get periodicalFields() {
    return SECTION_FIELDS.periodical;
  }

  get presentationFields() {
    return SECTION_FIELDS.presentation;
  }

  get publicAppearanceFields() {
    return SECTION_FIELDS.publicAppearance;
  }

  get radioTvAdFields() {
    return SECTION_FIELDS.radioTvAd;
  }

  get seminarFields() {
    return SECTION_FIELDS.seminar;
  }

  get socialMediaContentFields() {
    return SECTION_FIELDS.socialMediaContent;
  }

  get socialMediaProfileFields() {
    return SECTION_FIELDS.socialMediaProfile;
  }

  get sponsorshipFields() {
    return SECTION_FIELDS.sponsorship;
  }

  get videoAudioFields() {
    return SECTION_FIELDS.videoAudio;
  }

  get websiteFields() {
    return SECTION_FIELDS.website;
  }

  // ---- Nested (sub-conditional) fields, rendered outside their section's
  // lightning-record-form since that component shows every field in its
  // list unconditionally. ----------------------------------------------

  get showThirdPartyField() {
    return this.fieldValue("Produced_by_a_3rd_Party__c") === "Yes";
  }

  get thirdPartyValue() {
    return this.fieldValue("x3rd_Party__c");
  }

  get showRafflesExplanation() {
    return this.fieldValue("Include_Raffles_Gifts_etc__c") === "Yes";
  }

  get rafflesExplanationValue() {
    return this.fieldValue("Raffles_Gifts_Explanation__c");
  }

  get showAdditionalCommentary() {
    return this.fieldValue("Participate_in_Drafting_Content__c") === "No";
  }

  get additionalCommentaryValue() {
    return this.fieldValue("Providing_Additional_Commentary__c");
  }

  get showTalkingPoints() {
    return this.fieldValue("Do_you_have_detailed_talking_points__c") === "Yes";
  }

  get talkingPointsValue() {
    return this.fieldValue("Detailed_Talking_Points__c");
  }

  get showRelatedPublicAppearance() {
    return this.fieldValue("Has_Public_Appearance__c") === true;
  }

  get relatedPublicAppearanceId() {
    return this.fieldValue("Public_Appearance__c");
  }

  get relatedPublicAppearanceName() {
    return this.fieldValue("Public_Appearance__r.Name");
  }

  get showRelatedSocialMediaProfile() {
    return this.fieldValue("hasSocialMediaProfile__c") === true;
  }

  get relatedSocialMediaProfileId() {
    return this.fieldValue("Social_Media_Profile__c");
  }

  get relatedSocialMediaProfileName() {
    return this.fieldValue("Social_Media_Profile__r.Name");
  }

  get showRelatedRadioTvAd() {
    return this.fieldValue("Has_Radio_TV__c") === true;
  }

  get relatedRadioTvAdId() {
    return this.fieldValue("Radio_TV_Ad__c");
  }

  get relatedRadioTvAdName() {
    return this.fieldValue("Radio_TV_Ad__r.Name");
  }

  handleRelatedItemClick(event) {
    event.preventDefault();
    const recordId = event.currentTarget.dataset.recordId;
    this.navigateToRecord(recordId, OBJECT_API_NAME);
  }
}