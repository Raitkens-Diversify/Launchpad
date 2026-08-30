/**
 * Check Log detail page for Experience Cloud, shaped like arcTaskDetail /
 * arcCaseDetail (Case-style header card over the generic c-arc-record-detail
 * sections) instead of the bare generic form the page used to be.
 *
 * What the generic pipeline could not do, this page's own controller
 * (ArcCheckLogController) supplies:
 *  - The FinServ financial account's name/number (invisible to portal users
 *    through USER_MODE — see ArcFinServAccountLabels).
 *  - The Check Deposits list with the same columns as the Lightning record
 *    page: Name, Financial Account, Account Number, Amount.
 *  - The Files list, whose rows open the file itself in a new tab; the old
 *    generic list navigated to a ContentDocument record page this site does
 *    not have, which landed on the error page.
 *
 * Check deposit rows open a read-only quick-view popup
 * (c-arc-check-deposit-quick-view) instead of navigating: every field on a
 * deposit is read-only, so a popup keeps the user on the check log.
 */
import { LightningElement, wire } from "lwc";
import { NavigationMixin, CurrentPageReference } from "lightning/navigation";
import communityBasePath from "@salesforce/community/basePath";
import {
  resolveRecordIdFromPageReference,
  isValidSalesforceRecordId,
  buildRecordNavigationReference
} from "c/recordNavigationCommunityUtils";
import getCheckLogContext from "@salesforce/apex/ArcCheckLogController.getCheckLogContext";
import getCheckDeposits from "@salesforce/apex/ArcCheckLogController.getCheckDeposits";
import getCheckLogFiles from "@salesforce/apex/ArcCheckLogController.getCheckLogFiles";
import getFileData from "@salesforce/apex/ArcFileViewerController.getFileData";

const CURRENCY_FORMAT = new Intl.NumberFormat("en-US", {
  style: "currency",
  currency: "USD"
});

/* Lightning's Check Deposits related list columns, in its order. */
const DEPOSIT_COLUMNS = [
  {
    label: "Check Deposit",
    fieldName: "name",
    isLink: true,
    linkObjectApiName: "Check_Deposit__c"
  },
  { label: "Financial Account", fieldName: "financialAccountName" },
  { label: "Account Number", fieldName: "financialAccountNumber" },
  { label: "Amount", fieldName: "amount", type: "currency" }
];

const FILE_COLUMNS = [
  {
    label: "File",
    fieldName: "title",
    isLink: true,
    linkObjectApiName: "ContentDocument"
  },
  { label: "Type", fieldName: "fileExtension" },
  { label: "Updated", fieldName: "contentModifiedDate", type: "date" }
];

export default class ArcCheckLogDetail extends NavigationMixin(
  LightningElement
) {
  _recordId;
  depositColumns = DEPOSIT_COLUMNS;
  fileColumns = FILE_COLUMNS;

  context = {};
  deposits = [];
  files = [];
  fileErrorMessage = "";

  @wire(CurrentPageReference)
  wiredPageReference(pageRef) {
    this._recordId = resolveRecordIdFromPageReference(pageRef, "Check_Log__c");
  }

  @wire(getCheckLogContext, { checkLogId: "$_recordId" })
  wiredContext(result) {
    this.context = result?.data || {};
  }

  @wire(getCheckDeposits, { checkLogId: "$_recordId" })
  wiredDeposits(result) {
    this.deposits = (result?.data || []).map((deposit) => ({
      ...deposit,
      id: deposit.id
    }));
  }

  @wire(getCheckLogFiles, { checkLogId: "$_recordId" })
  wiredFiles(result) {
    this.files = (result?.data || []).map((file) => ({
      ...file,
      id: file.contentDocumentId
    }));
  }

  get hasRecordId() {
    return isValidSalesforceRecordId(this._recordId);
  }

  get name() {
    return this.context?.name || "";
  }

  get status() {
    return this.context?.status || "";
  }

  get reviewStatus() {
    return this.context?.reviewStatus || "";
  }

  get hasReviewStatus() {
    return Boolean(this.reviewStatus);
  }

  get reviewStatusLabel() {
    return `Review: ${this.reviewStatus}`;
  }

  get methodOfForwarding() {
    return this.context?.methodOfForwarding || "";
  }

  get hasMethodOfForwarding() {
    return Boolean(this.methodOfForwarding);
  }

  get hasClient() {
    return Boolean(this.context?.clientId && this.context?.clientName);
  }

  get hasCase() {
    return Boolean(this.context?.caseId && this.context?.caseNumber);
  }

  /** FinServ account: display identity only — the site has no page for it. */
  get financialAccountName() {
    return this.context?.financialAccountName || "";
  }

  get hasFinancialAccount() {
    return Boolean(this.financialAccountName);
  }

  get financialAccountNumber() {
    return this.context?.financialAccountNumber || "";
  }

  get hasFinancialAccountNumber() {
    return Boolean(this.financialAccountNumber);
  }

  get hasWizardFinancialAccount() {
    return Boolean(
      this.context?.wizardFinancialAccountId &&
        this.context?.wizardFinancialAccountName
    );
  }

  get hasAmount() {
    return this.context?.amount !== null && this.context?.amount !== undefined;
  }

  get formattedAmount() {
    return this.hasAmount ? CURRENCY_FORMAT.format(this.context.amount) : "";
  }

  get hasReceivedDate() {
    return Boolean(this.context?.receivedDate);
  }

  get formattedReceivedDate() {
    if (!this.context?.receivedDate) {
      return "";
    }
    const [year, month, day] = this.context.receivedDate.split("-");
    return `${month}/${day}/${year}`;
  }

  get depositsLabel() {
    return `Check Deposits (${this.deposits.length})`;
  }

  get hasDeposits() {
    return this.deposits.length > 0;
  }

  get filesLabel() {
    return `Files (${this.files.length})`;
  }

  get hasFiles() {
    return this.files.length > 0;
  }

  handleClientClick(event) {
    event.preventDefault();
    this.navigateToRecord(this.context.clientId, "Account");
  }

  handleCaseClick(event) {
    event.preventDefault();
    this.navigateToRecord(this.context.caseId, "Case");
  }

  handleWizardFinancialAccountClick(event) {
    event.preventDefault();
    this.navigateToRecord(
      this.context.wizardFinancialAccountId,
      "Financial_Account__c"
    );
  }

  /** Deposits are all read-only fields, so the row opens the popup in place. */
  handleDepositRowNavigate(event) {
    event.preventDefault();
    const recordId = event.detail?.recordId;
    if (recordId) {
      this.refs.depositQuickView?.open(recordId);
    }
  }

  /**
   * A file row opens the document itself in a new tab — there is no
   * ContentDocument page in this site to navigate to (the old behavior,
   * which landed on the error page).
   *
   * The bytes come through Apex and open as a blob URL rather than the
   * platform's /sfc/servlet.shepherd download endpoint, because the
   * live-preview host does not serve that servlet (404) and preview is
   * where this site is tested. The tab is opened synchronously in the
   * click so popup blocking never eats it, then pointed at the blob once
   * the data arrives. Files over the server's size cap fall back to the
   * platform download URL, which works on the published site.
   */
  async handleFileRowNavigate(event) {
    event.preventDefault();
    const contentDocumentId = event.detail?.recordId;
    if (!contentDocumentId) {
      return;
    }

    this.fileErrorMessage = "";
    const viewerTab = window.open("", "_blank");
    try {
      const payload = await getFileData({ contentDocumentId });
      if (payload.tooLarge) {
        const downloadUrl = `${communityBasePath}/sfc/servlet.shepherd/document/download/${contentDocumentId}`;
        if (viewerTab) {
          viewerTab.location = downloadUrl;
        }
        return;
      }

      const bytes = Uint8Array.from(atob(payload.base64Data), (char) =>
        char.charCodeAt(0)
      );
      const blob = new Blob([bytes], { type: payload.mimeType });
      const blobUrl = URL.createObjectURL(blob);
      if (viewerTab) {
        viewerTab.location = blobUrl;
      } else {
        window.open(blobUrl, "_blank");
      }
    } catch (error) {
      if (viewerTab) {
        viewerTab.close();
      }
      this.fileErrorMessage =
        error?.body?.message || "Unable to open this file right now.";
    }
  }

  navigateToRecord(recordId, objectApiName) {
    if (!recordId || !objectApiName) {
      return;
    }
    const pageReference = buildRecordNavigationReference(recordId, objectApiName);
    if (!pageReference) {
      return;
    }
    this[NavigationMixin.Navigate](pageReference);
  }
}