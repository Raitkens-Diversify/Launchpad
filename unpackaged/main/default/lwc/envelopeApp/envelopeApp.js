import { LightningElement, api, wire, track } from "lwc";
import { EnclosingTabId, setTabLabel } from "lightning/platformWorkspaceApi";
import { loadStyle } from "lightning/platformResourceLoader";
import ToastContainer from "lightning/toastContainer";
import envelopeWizardStyles from "@salesforce/resourceUrl/envelopeWizardStyles";
import getWizEnvelopes from "@salesforce/apex/EnvelopeLandingApex.getWizEnvelopes";

export default class EnvelopeApp extends LightningElement {
  /** Hides the top bar's Diversify logo for sites/pages with their own header/branding. */
  _hideBranding = false;
  @api
  get hideBranding() {
    return this._hideBranding;
  }
  set hideBranding(value) {
    this._hideBranding = value !== false && value !== "false";
  }

  @track currentView = "list";

  // Populated when an envelope is created from the list modal; passed to the
  // new shellV2 page for display.
  createdEnvelopeId = null;
  createdEnvelopeTitle = "";
  createdHouseholdName = "";
  // Set only when the envelope was created against an existing household; lets the
  // shell prepopulate the outline rail.
  createdHouseholdId = null;

  // The breadcrumb crumb for the shell's active sub-view (e.g. "Entity - Action" for an
  // action's interview, "Manage Documents" for the documents screen); null on the default
  // workspace. Set from the shell's `subviewchange`.
  subViewCrumb = null;

  // Descriptor for the focused top-bar variant when a full-screen review view is open
  // (e.g. Review Missing Items, Review & Submit): { mode, showReview, statusText }. Null for
  // breadcrumb sub-views (action interview, Manage Documents) and the default workspace. Set
  // from the shell's `subviewchange`.
  _focusedHeader = null;

  // Whether the shell's envelope is ready to review (has items and everything is populated);
  // announced by the shell via `reviewablechange` and drives the top bar's "Review and
  // Submit" enablement.
  shellReviewable = false;

  connectedCallback() {
    // LWR sites ship no default toast container, so lightning/toast calls render
    // nothing there without one; in the core app this is a harmless no-op container.
    try {
      ToastContainer.instance().toastPosition = "top-center";
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error(
        "[envelopeApp] Failed to initialize toast container",
        error
      );
    }
    // Load the shared base-component theme sheet for the whole V2 subtree.
    loadStyle(this, envelopeWizardStyles).catch((error) => {
      // eslint-disable-next-line no-console
      console.error("[envelopeApp] Failed to load wizard styles", error);
    });
    // Mark the document root while the wizard is mounted. The platform toast renders in the
    // overlay layer (outside this subtree), so the shared sheet scopes its toast overrides
    // under this class rather than .env-layout; removed on disconnect so other Lightning
    // toasts in the session keep their default styling.
    document.documentElement.classList.add("env-wizard-toast");
    this._openEnvelopeFromUrl();
  }

  // Deep-link support: row links elsewhere in the app (e.g. the Home dashboard's Envelopes
  // table) navigate here as `/envelope?id=<recordId>` expecting that specific envelope to
  // open, not the list. Reuses the same wizard-envelope read the list view already fetches
  // from, rather than adding a single-record Apex method just for this lookup.
  _openEnvelopeFromUrl() {
    const envelopeId = new URLSearchParams(window.location.search || "").get(
      "id"
    );
    if (!envelopeId) {
      return;
    }

    getWizEnvelopes()
      .then((result) => {
        const envelope = (result.envelopes || []).find(
          (candidate) => candidate.Id === envelopeId
        );
        if (!envelope) {
          return;
        }

        const record = (result.envelopeRecords || []).find(
          (candidate) => candidate.Envelope__c === envelopeId
        );

        this.createdEnvelopeId = envelopeId;
        this.createdEnvelopeTitle = envelope.Name || "";
        this.createdHouseholdName = envelope.Household_Name__c || "";
        this.createdHouseholdId = record ? record.Account__c : (envelope.Household__c || null);
        this._resetShellChrome();
        this.currentView = "shellV2";
      })
      .catch((error) => {
        // eslint-disable-next-line no-console
        console.error("[envelopeApp] Failed to open envelope from URL", error);
      });
  }

  disconnectedCallback() {
    document.documentElement.classList.remove("env-wizard-toast");
  }

  @wire(EnclosingTabId)
  wiredTabId(tabId) {
    // Console-only: outside a console (standard nav, Experience Cloud) the wire
    // yields no tabId and setTabLabel is unavailable, so degrade silently.
    if (tabId) {
      try {
        setTabLabel(tabId, "Envelope Wizard");
      } catch (error) {
        // eslint-disable-next-line no-console
        console.error("[envelopeApp] Failed to set console tab label", error);
      }
    }
  }

  get isListView() {
    return this.currentView === "list";
  }

  get isShellV2() {
    return this.currentView === "shellV2";
  }

  // The body row scrolls only for views that don't bring their own scrollport. Every shell
  // sub-view renders one (the action interview, Review Missing Items, Review & Submit and the
  // default workspace each own theirs), so keeping this one would nest two scrollers over the
  // same content — and a composited sticky box inside the inner scroller of a nested pair leaves
  // stale bands on screen while scrolling. envelopeListV2 has no scroller of its own, so the list
  // view keeps this one.
  get bodyClass() {
    return this.isShellV2
      ? "env-layout__body env-layout__body_inner-scroll"
      : "env-layout__body";
  }

  // Breadcrumb for the shared top bar, derived from the active v2 view. In the
  // shell, "Envelopes" stays a link so clicking it swaps the body back to the list.
  get topBreadcrumb() {
    if (this.isShellV2) {
      const crumbs = [
        { label: "Envelopes", key: "envelopes" },
        {
          label: this.createdEnvelopeTitle || "New Envelope",
          key: "current",
          current: !this.subViewCrumb
        }
      ];
      // Add a 3rd level while a sub-view (action interview, Manage Documents) is open.
      if (this.subViewCrumb) {
        crumbs.push({
          label: this.subViewCrumb,
          key: "subview",
          current: true
        });
      }
      return crumbs;
    }
    return [{ label: "Envelopes", key: "envelopes", current: true }];
  }

  // Track the breadcrumb crumb dispatched by the shell as it opens/closes a sub-view
  // (action interview, Manage Documents, or a focused review view).
  handleSubViewChange(event) {
    const detail = event?.detail || {};
    this.subViewCrumb = detail.crumb || null;
    // A focused review view also carries a header descriptor; clear it when the crumb does.
    this._focusedHeader = detail.crumb ? detail.header || null : null;
  }

  // Clear the chrome the shell drives: the breadcrumb sub-view, the focused top-bar variant and
  // the review enablement. Every path that tears down or swaps the shell must go through this —
  // a focused review view left by submit, delete or the Envelopes crumb never dispatches a
  // closing `subviewchange`, so its header descriptor would otherwise persist into the next
  // envelope and render the top bar without its logo and breadcrumb.
  _resetShellChrome() {
    this.subViewCrumb = null;
    this._focusedHeader = null;
    this.shellReviewable = false;
  }

  get topBarMode() {
    return this._focusedHeader ? "focused" : "default";
  }

  get topBarLeadingTitle() {
    return this.subViewCrumb || "";
  }

  get topBarEnvelopeName() {
    return this.createdEnvelopeTitle || "";
  }

  get topBarStatusText() {
    return this._focusedHeader?.statusText || "";
  }

  get topBarShowReview() {
    return this._focusedHeader
      ? Boolean(this._focusedHeader.showReview)
      : this.isShellV2;
  }

  get topBarShowClose() {
    return Boolean(this._focusedHeader);
  }

  get topBarReviewDisabled() {
    return !this.shellReviewable;
  }

  handleReviewableChange(event) {
    this.shellReviewable = Boolean(event?.detail?.reviewable);
  }

  // The top bar's "Review and Submit" action opens the shell's Review & Submit view.
  handleTopBarReview() {
    this.refs.shellV2?.openReview();
  }

  handleTopBarClose() {
    this.refs.shellV2?.closeSubView();
  }

  // Fired by envelopeListV2 once the New-envelope modal has created the
  // record; routes the user into the redesigned shellV2 working page.
  handleEnvelopeCreated(event) {
    const detail = event?.detail || {};
    this.createdEnvelopeId = detail.envelopeId || null;
    this.createdEnvelopeTitle = detail.title || "";
    this.createdHouseholdName = detail.householdName || "";
    this.createdHouseholdId = detail.householdId || null;
    this._resetShellChrome();
    // Defer the list->shell swap out of the originating row-click's render
    // cycle. The click mutates the data table's own reactive state in the
    // same tick, so swapping synchronously queues this component's re-render
    // alongside the table's; the engine renders the parent first and tears
    // the table out from under its own pending re-render, crashing the patch
    // ("Invalid value used as weak map key") and leaving both views mounted.
    // A microtask lets the table settle first, then we swap a clean subtree.
    Promise.resolve().then(() => {
      this.currentView = "shellV2";
    });
  }

  handleEnvelopeRenamed(event) {
    this.createdEnvelopeTitle =
      event?.detail?.name || this.createdEnvelopeTitle;
  }

  handleEnvelopeDeleted() {
    Promise.resolve().then(() => {
      this.currentView = "list";
      this.createdEnvelopeId = null;
      this.createdEnvelopeTitle = "";
      this.createdHouseholdName = "";
      this.createdHouseholdId = null;
      this._resetShellChrome();
    });
  }

  // Once submitted, the envelope is locked and no longer editable — return to the list, the
  // same teardown as a delete. The shell has already shown the success toast.
  handleEnvelopeSubmitted() {
    this.handleEnvelopeDeleted();
  }

  handleShellNavigate(event) {
    const key = event?.detail?.key;
    if (key === "envelopes") {
      this.currentView = "list";
      this.createdEnvelopeId = null;
      this.createdEnvelopeTitle = "";
      this.createdHouseholdName = "";
      this.createdHouseholdId = null;
      this._resetShellChrome();
    } else if (key === "current") {
      // The envelope crumb is a link only while a sub-view is open; clicking it
      // returns to the workspace.
      this.refs.shellV2?.closeSubView();
    }
  }
}