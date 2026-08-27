import { LightningElement, api, wire } from "lwc";
import { CurrentPageReference } from "lightning/navigation";
import { getObjectInfo } from "lightning/uiObjectInfoApi";
import { resolveRecordIdFromPageReference } from "c/recordNavigationUtils";
import getRecordFeed from "@salesforce/apex/ArcCaseFeedController.getRecordFeed";
import getRecordHistory from "@salesforce/apex/ArcCaseFeedController.getRecordHistory";

/**
 * arcCaseFeedTabs
 *
 * The Feed and Related tabs from Lightning's own record page, rebuilt for ARC.
 * Self-contained: it renders its own feed posts and its own related-list cards
 * rather than delegating to c/arcRelatedList or anything else already on the
 * case page, so adding it changes nothing that is there today.
 *
 * NO FILES TAB. Lightning shows Feed / Related / Files; only the first two are
 * wanted here, so there is no Files tab and nothing that would build one.
 *
 * WHAT THE TABS CONTAIN was taken from the real page, not guessed: opening
 * /lightning/r/Case/<id>/view and reading the rendered panels shows a Chatter
 * feed under Feed, and under Related exactly one related list, Case History.
 * The rail's other cards — Case Comments, Order Tickets and the rest — belong
 * to Lightning's right COLUMN, which is a different thing, and arcCaseDetail
 * renders those itself.
 *
 * APEX. Both tabs read ArcCaseFeedController, added alongside this component
 * because nothing existed to read either a feed or history in a display-ready
 * shape:
 *   Feed    — getRecordFeed
 *   Related — getRecordHistory
 * Both are read-only and nothing else calls them. The generic
 * ArcRelatedListController could query CaseHistory, but it returns raw SOQL,
 * and raw history is not what the page shows — see the note on the history
 * wire below.
 *
 * The feed is READ-ONLY. Posting or commenting is DML, which this deliberately
 * does not do.
 */

/** Tabs, in order. Files is not one of them — see the note above. */
const TAB_FEED = "feed";
const TAB_RELATED = "related";


/** FeedItem.Type values that describe a change to the record itself. */
const TYPE_CREATED = "CreateRecordEvent";
const TYPE_CHANGED = "TrackedChange";

export default class ArcCaseFeedTabs extends LightningElement {
  /**
   * Object whose record page this sits on. A design property rather than a
   * constant so the component is not silently Case-only; the record id is
   * resolved against it.
   */
  @api objectApiName = "Case";

  /** Posts per page. ArcCaseFeedController caps this at 50. */
  @api feedPageSize = 10;

  activeTab = TAB_FEED;

  /**
   * Record to read. Passed by the parent as record-id, the way every other
   * child in arcCaseDetail's rail gets it.
   *
   * WHY THIS EXISTS RATHER THAN JUST READING THE PAGE REFERENCE. An Apex @wire
   * does not call the server while any reactive $parameter is `undefined`. When
   * the id came only from CurrentPageReference and that did not resolve — which
   * happens for a nested component in an LWR site — the feed wire never fired,
   * so `feed` stayed undefined and the loading spinner ran forever. Taking the
   * id from the parent, which already has it, removes that whole failure mode.
   *
   * The page reference is still used as a fallback so the component keeps
   * working if it is ever dropped straight onto a record page.
   */
  @api
  get recordId() {
    return this._recordIdInput;
  }

  set recordId(value) {
    this._recordIdInput = value || undefined;
    this.syncActiveRecordId();
  }

  /**
   * The id the wires actually read. A real field, not a getter, so the reactive
   * $activeRecordId parameter is unambiguous.
   */
  activeRecordId;

  _recordIdInput;
  _pageRefRecordId;

  feed;
  feedError;
  history;
  relatedError;

  /**
   * Set the first time the Related tab is opened, and never unset. The batch
   * query is six SOQL queries; there is no reason to pay for them for a user
   * who only ever looks at the feed.
   */
  _relatedRequested = false;

  @wire(CurrentPageReference)
  wiredPageReference(pageRef) {
    this._pageRefRecordId =
      resolveRecordIdFromPageReference(pageRef, this.objectApiName) || undefined;
    this.syncActiveRecordId();
  }

  /** An explicit record-id wins; the page reference is the fallback. */
  syncActiveRecordId() {
    const next = this._recordIdInput || this._pageRefRecordId;

    if (next !== this.activeRecordId) {
      this.activeRecordId = next;
    }
  }

  @wire(getObjectInfo, { objectApiName: "$objectApiName" })
  objectInfo;

  @wire(getRecordFeed, {
    recordId: "$activeRecordId",
    pageSize: "$feedPageSize"
  })
  wiredFeed({ data, error }) {
    if (data) {
      this.feed = data;
      this.feedError = undefined;
      return;
    }

    if (error) {
      this.feed = undefined;
      this.feedError = "Unable to load the feed for this record.";
    }
  }

  /**
   * Case History, through ArcCaseFeedController rather than the generic
   * related-list controller.
   *
   * The generic one can query CaseHistory, but it returns raw SOQL: "created"
   * where the page shows "Created.", API names where the page shows labels, and
   * a lookup change as the duplicated id/name row pair the platform writes
   * rather than the single readable line the page shows. All three need describe
   * access and dedupe, so they live in Apex.
   */
  @wire(getRecordHistory, {
    recordId: "$relatedRecordId",
    objectApiName: "$objectApiName",
    pageSize: "$feedPageSize"
  })
  wiredHistory({ data, error }) {
    if (data) {
      this.history = data;
      this.relatedError = undefined;
      return;
    }

    if (error) {
      this.history = undefined;
      this.relatedError = "Unable to load the history for this record.";
    }
  }

  /** Undefined until the Related tab is opened, which keeps the wire idle. */
  get relatedRecordId() {
    return this._relatedRequested ? this.activeRecordId : undefined;
  }

  // ---- tabs ---------------------------------------------------------------

  get tabs() {
    return [
      { value: TAB_FEED, label: "Feed" },
      { value: TAB_RELATED, label: "Related" }
    ];
  }

  get showFeed() {
    return this.activeTab === TAB_FEED;
  }

  get showRelated() {
    return this.activeTab === TAB_RELATED;
  }

  handleTabChange(event) {
    const value = event.detail?.value || event.detail;

    if (value !== TAB_FEED && value !== TAB_RELATED) {
      return;
    }

    this.activeTab = value;

    if (value === TAB_RELATED) {
      this._relatedRequested = true;
    }
  }

  // ---- feed ---------------------------------------------------------------

  get objectLabel() {
    return this.objectInfo?.data?.label || "Record";
  }

  /**
   * Feed posts as the template needs them. The header mirrors Lightning's
   * wording ("Case created"), and a post with no header is a plain text post,
   * where the body is the whole content.
   */
  get feedEntries() {
    return (this.feed?.entries || []).map((entry) => {
      const changes = (entry.changes || []).map((change, index) => ({
        ...change,
        key: `${entry.id}-${index}`,
        // A creation post has no previous value, so "was X" would be noise.
        // A genuine change shows both sides.
        showOldValue: Boolean(change.oldValue)
      }));

      return {
        id: entry.id,
        actorName: entry.actorName || "Unknown user",
        createdDate: entry.createdDate,
        body: entry.body,
        hasBody: Boolean(entry.body),
        changes,
        hasChanges: changes.length > 0,
        header: this.headerFor(entry.type),
        hasHeader: Boolean(this.headerFor(entry.type))
      };
    });
  }

  headerFor(type) {
    if (type === TYPE_CREATED) {
      return `${this.objectLabel} created`;
    }

    if (type === TYPE_CHANGED) {
      return `${this.objectLabel} updated`;
    }

    return null;
  }

  get hasFeedEntries() {
    return this.feedEntries.length > 0;
  }

  get feedHasMore() {
    return Boolean(this.feed?.hasMore);
  }

  /**
   * Only true while a request can actually be in flight. Gated on having an id,
   * because without one the Apex wire never calls the server and an ungated
   * spinner would run forever — which is exactly what it did.
   */
  get isFeedLoading() {
    return Boolean(this.activeRecordId) && !this.feed && !this.feedError;
  }

  /**
   * "Genuinely nothing to show", as opposed to "not loaded yet" or "failed".
   * A single getter rather than nested template conditions, because an
   * lwc:if/lwc:else pair cannot express three outcomes and stacking them reads
   * as an empty feed while the request is still in flight.
   */
  get showFeedEmpty() {
    return !this.isFeedLoading && !this.feedError && !this.hasFeedEntries;
  }

  // ---- related ------------------------------------------------------------

  /**
   * History entries as Lightning's history card lists them: Date, Field, User,
   * Original Value, New Value.
   *
   * A blank value is kept rather than dropped. "Original Value:" with nothing
   * after it is exactly what the page shows for a creation entry, and it is
   * information -- the field went from nothing to something.
   */
  get historyEntries() {
    return (this.history?.entries || []).map((entry) => ({
      id: entry.id,
      createdDate: entry.createdDate,
      actorName: entry.actorName || "Unknown user",
      fieldLabel: entry.fieldLabel,
      oldValue: entry.oldValue,
      newValue: entry.newValue
    }));
  }

  get hasHistory() {
    return this.historyEntries.length > 0;
  }

  get historyCount() {
    return this.historyEntries.length;
  }

  get historyHasMore() {
    return Boolean(this.history?.hasMore);
  }

  /** "Genuinely empty", as distinct from still loading or failed. */
  get showHistoryEmpty() {
    return (
      this._relatedRequested &&
      !this.isRelatedLoading &&
      !this.relatedError &&
      !this.hasHistory
    );
  }

  /** Gated on the id for the same reason as isFeedLoading. */
  get isRelatedLoading() {
    return (
      this._relatedRequested &&
      Boolean(this.activeRecordId) &&
      !this.history &&
      !this.relatedError
    );
  }
}