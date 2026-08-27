import { LightningElement, api, wire } from "lwc";
import { CurrentPageReference } from "lightning/navigation";
import { getObjectInfo } from "lightning/uiObjectInfoApi";
import { resolveRecordIdFromPageReference } from "c/recordNavigationUtils";
import getRecordFeed from "@salesforce/apex/ArcCaseFeedController.getRecordFeed";
import getRelatedRecordsBatch from "@salesforce/apex/ArcRelatedListController.getRelatedRecordsBatch";

/**
 * arcCaseFeedTabs
 *
 * The Feed and Related tabs from Lightning's own record page, rebuilt for ARC.
 * Self-contained: it renders its own feed posts and its own related-list cards
 * rather than delegating to c/arcRelatedList or anything else already on the
 * case page, so adding it changes nothing that is there today.
 *
 * NO FILES TAB. Lightning shows Feed / Related / Files; only the first two are
 * wanted here. ContentDocumentLink is deliberately absent from RELATED_CARDS
 * below — the row is not commented out, it is gone, so nobody has to guess
 * whether it was an oversight.
 *
 * APEX. Both tabs read through Apex that already existed:
 *   Related — ArcRelatedListController.getRelatedRecordsBatch, which is generic
 *             over object, parent lookup and columns, and runs all six cards in
 *             one transaction rather than one round trip per card.
 *   Feed    — ArcCaseFeedController.getRecordFeed, added alongside this
 *             component because nothing existed to read a feed. It is read-only
 *             and nothing else calls it.
 *
 * The feed is READ-ONLY. Posting or commenting is DML, which this deliberately
 * does not do.
 */

/** Tabs, in order. Files is not one of them — see the note above. */
const TAB_FEED = "feed";
const TAB_RELATED = "related";

/**
 * The related lists to show, in order.
 *
 * These are the same object/parent/column triples the case page already renders
 * through c/arcRelatedList, copied rather than invented so the tab shows what
 * the business already sees, with the proven relationship paths. `key` is what
 * getRelatedRecordsBatch matches results back by.
 */
const RELATED_CARDS = [
  {
    key: "caseComments",
    label: "Case Comments",
    objectApiName: "CaseComment",
    parentFieldApiName: "ParentId",
    columns: [
      { label: "Comment", field: "CommentBody" },
      { label: "By", field: "CreatedBy.Name" },
      { label: "Added", field: "CreatedDate" }
    ]
  },
  {
    key: "orderTickets",
    label: "Order Tickets",
    objectApiName: "Order_Ticket__c",
    parentFieldApiName: "Case__c",
    columns: [
      { label: "Order Ticket", field: "Name" },
      { label: "Financial Account", field: "Wizard_Financial_Account__r.Name" },
      { label: "Created", field: "CreatedDate" }
    ]
  },
  {
    key: "relatedProducts",
    label: "Related Products",
    objectApiName: "Financial_Account_Related_Product__c",
    parentFieldApiName: "Case__c",
    columns: [
      { label: "Product", field: "Name" },
      { label: "Financial Account", field: "Wizard_Financial_Account__r.Name" },
      { label: "Created", field: "CreatedDate" }
    ]
  },
  {
    key: "checkLogs",
    label: "Check Logs",
    objectApiName: "Check_Log__c",
    parentFieldApiName: "Case__c",
    columns: [
      { label: "Check Log", field: "Name" },
      { label: "Amount", field: "Amount__c" },
      { label: "Status", field: "Status__c" }
    ]
  },
  {
    key: "tradeErrors",
    label: "Trade Errors Log",
    objectApiName: "Trade_Error_Log__c",
    parentFieldApiName: "Case__c",
    columns: [
      { label: "Trade Error", field: "Name" },
      { label: "Amount", field: "Total_Trade_Error_Amount__c" },
      { label: "Status", field: "Status__c" }
    ]
  },
  {
    key: "services",
    label: "Services",
    objectApiName: "Service__c",
    parentFieldApiName: "Case__c",
    columns: [
      { label: "Service", field: "Name" },
      { label: "Type", field: "Type__c" },
      { label: "Start Date", field: "Start_Date__c" }
    ]
  }
];

/** Request payload for getRelatedRecordsBatch, derived once. */
const RELATED_REQUESTS = RELATED_CARDS.map((card) => ({
  key: card.key,
  objectApiName: card.objectApiName,
  parentFieldApiName: card.parentFieldApiName,
  fieldApiNames: card.columns.map((column) => column.field),
  linkFieldApiName: ""
}));

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

  recordId;
  feed;
  feedError;
  relatedData;
  relatedError;

  /**
   * Set the first time the Related tab is opened, and never unset. The batch
   * query is six SOQL queries; there is no reason to pay for them for a user
   * who only ever looks at the feed.
   */
  _relatedRequested = false;

  @wire(CurrentPageReference)
  wiredPageReference(pageRef) {
    this.recordId = resolveRecordIdFromPageReference(
      pageRef,
      this.objectApiName
    );
  }

  @wire(getObjectInfo, { objectApiName: "$objectApiName" })
  objectInfo;

  @wire(getRecordFeed, { recordId: "$recordId", pageSize: "$feedPageSize" })
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

  @wire(getRelatedRecordsBatch, {
    recordId: "$relatedRecordId",
    requests: RELATED_REQUESTS
  })
  wiredRelated({ data, error }) {
    if (data) {
      this.relatedData = data;
      this.relatedError = undefined;
      return;
    }

    if (error) {
      this.relatedData = undefined;
      this.relatedError = "Unable to load the related lists for this record.";
    }
  }

  /** Undefined until the Related tab is opened, which keeps the wire idle. */
  get relatedRecordId() {
    return this._relatedRequested ? this.recordId : undefined;
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

  get isFeedLoading() {
    return !this.feed && !this.feedError;
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
   * Cards in configured order, each carrying its own rows. A card whose request
   * failed validation server-side is simply absent from the response, which the
   * batch method does on purpose so one bad card cannot blank the others — such
   * a card renders as empty rather than disappearing.
   */
  get relatedCards() {
    return RELATED_CARDS.map((card) => {
      const result = this.relatedData?.[card.key];
      const rows = (result?.rows || []).map((row) => ({
        id: row.id,
        cells: (row.cells || []).map((value, index) => ({
          key: `${row.id}-${index}`,
          value
        }))
      }));

      return {
        key: card.key,
        label: card.label,
        columns: card.columns.map((column) => ({
          key: `${card.key}-${column.label}`,
          label: column.label
        })),
        rows,
        hasRows: rows.length > 0,
        count: rows.length,
        hasMore: Boolean(result?.hasMore)
      };
    });
  }

  get isRelatedLoading() {
    return this._relatedRequested && !this.relatedData && !this.relatedError;
  }
}