/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-14
 */
import { LightningElement, api, wire } from "lwc";
import { getObjectInfo } from "lightning/uiObjectInfoApi";
import { refreshApex } from "@salesforce/apex";
import getLinkedContactsForAccount from "@salesforce/apex/SignificantEventActionController.getLinkedContactsForAccount";
import SIGNIFICANT_EVENT_CONTACT_OBJECT from "@salesforce/schema/Significant_Event_Contact__c";
import { SORT_DESC, sortRecords } from "c/dataTableSortUtils";
import {
  bindPreviewPointerListeners,
  createPreviewPointerState,
  findDatatableRowElement,
  findPreviewAnchorFromActiveElement,
  findPreviewButtonAnchorRectForRow,
  getSafeComposedPath,
  isPreviewTriggerClick,
  resolveDatatablePreviewPosition,
  unbindPreviewPointerListeners
} from "c/previewPanelPositionUtils";
import SignificantEventCreateActionModal from "c/significantEventCreateActionModal";

const DEFAULT_TITLE = "Significant Event Linked Contacts";
const DEFAULT_MAX_ROWS = 5;

const ROW_ACTIONS = [{ label: "Edit", name: "edit_event" }];

const SORT_TO_DATATABLE_FIELD = {
  participantName: "participantLink",
  eventName: "eventLink",
  accountName: "accountLink",
  startDate: "formattedStartDate",
  endDate: "formattedEndDate",
  eventType: "eventType",
  otherEventType: "formattedOtherEventType",
  approximateDateLabel: "approximateDateLabel"
};

const DATATABLE_TO_SORT_FIELD = Object.freeze(
  Object.fromEntries(
    Object.entries(SORT_TO_DATATABLE_FIELD).map(
      ([sortField, datatableField]) => [datatableField, sortField]
    )
  )
);

const buildRecordLink = (recordId) => (recordId ? `/${recordId}` : "");

const TABLE_COLUMNS = [
  {
    fieldName: "participantName",
    label: "Significant Event Contact",
    sortable: true
  },
  { fieldName: "eventName", label: "Event Name", sortable: true },
  { fieldName: "eventType", label: "Event Type", sortable: true },
  { fieldName: "otherEventType", label: "Other Event Type", sortable: true },
  {
    fieldName: "startDate",
    label: "Start Date",
    sortable: true,
    type: "date-local"
  },
  {
    fieldName: "endDate",
    label: "End Date",
    sortable: true,
    type: "date-local"
  },
  {
    fieldName: "approximateDateLabel",
    label: "Approximate Date",
    sortable: true
  },
  { fieldName: "accountName", label: "Account", sortable: true }
];

const formatDateValue = (value) => {
  if (!value) {
    return "";
  }

  const parsedDate = new Date(`${value}T00:00:00`);
  if (Number.isNaN(parsedDate.getTime())) {
    return value;
  }

  return new Intl.DateTimeFormat(undefined, {
    year: "numeric",
    month: "short",
    day: "2-digit"
  }).format(parsedDate);
};

const formatRelativeUpdatedLabel = (timestamp) => {
  if (!timestamp) {
    return "Updated just now";
  }

  const elapsedSeconds = Math.max(
    0,
    Math.floor((Date.now() - timestamp) / 1000)
  );

  if (elapsedSeconds < 60) {
    return "Updated just now";
  }

  const elapsedMinutes = Math.floor(elapsedSeconds / 60);
  if (elapsedMinutes < 60) {
    return elapsedMinutes === 1
      ? "Updated a minute ago"
      : `Updated ${elapsedMinutes} minutes ago`;
  }

  const elapsedHours = Math.floor(elapsedMinutes / 60);
  if (elapsedHours < 24) {
    return elapsedHours === 1
      ? "Updated an hour ago"
      : `Updated ${elapsedHours} hours ago`;
  }

  const elapsedDays = Math.floor(elapsedHours / 24);
  return elapsedDays === 1
    ? "Updated a day ago"
    : `Updated ${elapsedDays} days ago`;
};

export default class SignificantEventLinkedContactsTable extends LightningElement {
  @api recordId;
  @api title = DEFAULT_TITLE;
  @api maxRows = DEFAULT_MAX_ROWS;

  showAll = false;
  lastLoadedAt = Date.now();
  sortedBy = "startDate";
  sortedDirection = SORT_DESC;
  sortedRows = [];
  wiredLinkedContactsResult;

  previewPanel = {
    isOpen: false,
    recordId: "",
    memberName: "",
    sourceId: "",
    left: 24,
    top: 24,
    useFixedPosition: true
  };

  _frozenPreviewAnchorRect = null;
  _boundOutsideClickHandler = null;
  _boundEscapeHandler = null;
  _previewPointerHandlers = null;
  _previewPointerState = createPreviewPointerState();
  _ignoreOutsideClick = false;
  objectInfo;

  @wire(getObjectInfo, { objectApiName: SIGNIFICANT_EVENT_CONTACT_OBJECT })
  wiredObjectInfo({ data }) {
    if (data) {
      this.objectInfo = data;
    }
  }

  @wire(getLinkedContactsForAccount, { accountId: "$recordId" })
  wiredLinkedContacts(result) {
    this.wiredLinkedContactsResult = result;
    const { data, error } = result;

    if (data) {
      this.lastLoadedAt = Date.now();
      this.applySort();
      return;
    }

    if (error) {
      this.sortedRows = [];
      this.lastLoadedAt = Date.now();
    }
  }

  get showHeaderCount() {
    return this.totalCount > 0;
  }

  get showStatusLine() {
    return this.totalCount > 0;
  }

  get showCardBody() {
    return this.hasRows;
  }

  get tableColumns() {
    return TABLE_COLUMNS;
  }

  get datatableColumns() {
    return [
      {
        label: "Significant Event Contact",
        fieldName: "participantLink",
        type: "url",
        sortable: true,
        typeAttributes: {
          label: { fieldName: "participantName" },
          target: "_self"
        }
      },
      {
        label: "Event Name",
        fieldName: "eventLink",
        type: "url",
        sortable: true,
        typeAttributes: {
          label: { fieldName: "eventName" },
          target: "_self"
        }
      },
      {
        label: "Event Type",
        fieldName: "eventType",
        type: "text",
        sortable: true
      },
      {
        label: "Other Event Type",
        fieldName: "formattedOtherEventType",
        type: "text",
        sortable: true
      },
      {
        label: "Start Date",
        fieldName: "formattedStartDate",
        type: "text",
        sortable: true
      },
      {
        label: "End Date",
        fieldName: "formattedEndDate",
        type: "text",
        sortable: true
      },
      {
        label: "Approximate Date",
        fieldName: "approximateDateLabel",
        type: "text",
        sortable: true
      },
      {
        label: "",
        fieldName: "previewAction",
        type: "button-icon",
        fixedWidth: 42,
        typeAttributes: {
          iconName: "utility:preview",
          name: "preview_account",
          variant: "bare",
          alternativeText: "Preview account",
          title: "Preview account",
          disabled: { fieldName: "isPreviewDisabled" }
        }
      },
      {
        label: "Account",
        fieldName: "accountLink",
        type: "url",
        sortable: true,
        typeAttributes: {
          label: { fieldName: "accountName" },
          target: "_self"
        }
      },
      {
        type: "action",
        typeAttributes: {
          rowActions: ROW_ACTIONS
        }
      }
    ];
  }

  get totalCount() {
    return this.sourceRows.length;
  }

  get sourceRows() {
    const data = this.wiredLinkedContactsResult?.data || [];
    return data.map((row, index) => ({
      ...row,
      rowKey: row.participantId || `row-${index}`,
      approximateDateLabel: row.approximateDate ? "Yes" : "No",
      formattedStartDate: formatDateValue(row.startDate),
      formattedEndDate: formatDateValue(row.endDate),
      formattedOtherEventType:
        row.eventType === "Other" ? row.otherEventType || "" : "",
      previewSourceId: `preview-${row.participantId || index}`,
      isPreviewDisabled: !row.accountId,
      participantLink: buildRecordLink(row.participantId),
      eventLink: buildRecordLink(row.significantEventId),
      accountLink: buildRecordLink(row.accountId)
    }));
  }

  get datatableRows() {
    return this.showAll
      ? this.sortedRows
      : this.sortedRows.slice(0, this.maxRowsNumber);
  }

  get datatableSortedBy() {
    return SORT_TO_DATATABLE_FIELD[this.sortedBy] || this.sortedBy;
  }

  get maxRowsNumber() {
    const parsed = Number(this.maxRows);
    return Number.isFinite(parsed) && parsed > 0 ? parsed : DEFAULT_MAX_ROWS;
  }

  get hasRows() {
    return this.datatableRows.length > 0;
  }

  get headerCountLabel() {
    return ` (${this.totalCount})`;
  }

  get headerIconName() {
    return this.objectInfo?.themeInfo?.iconName || "standard:contact";
  }

  get statusCountLabel() {
    const itemLabel = this.totalCount === 1 ? "item" : "items";
    return `${this.totalCount} ${itemLabel}`;
  }

  get statusSortedByLabel() {
    const column = this.tableColumns.find(
      (entry) => entry.fieldName === this.sortedBy
    );
    const columnLabel = column?.label || this.sortedBy;

    return ` • Sorted by ${columnLabel}`;
  }

  get statusUpdatedLabel() {
    return ` • ${formatRelativeUpdatedLabel(this.lastLoadedAt)}`;
  }

  get showViewAll() {
    return !this.showAll && this.totalCount > this.maxRowsNumber;
  }

  get showPreviewPanel() {
    return this.previewPanel.isOpen && Boolean(this.previewPanel.recordId);
  }

  resolvePreviewPosition(rowKey, row) {
    return resolveDatatablePreviewPosition({
      datatableElement: this.getDatatableElement(),
      datatableRows: this.datatableRows,
      rowKey,
      row,
      pointerState: this._previewPointerState,
      frozenAnchorRect: this._frozenPreviewAnchorRect,
      preferFixedPosition: true
    });
  }

  capturePreviewAnchorForRow(row) {
    const rowElement = findDatatableRowElement(
      this.getDatatableElement(),
      this.datatableRows,
      row.rowKey,
      row
    );

    this._frozenPreviewAnchorRect =
      this._previewPointerState.lastPreviewClickRect ||
      findPreviewAnchorFromActiveElement() ||
      findPreviewButtonAnchorRectForRow(rowElement) ||
      null;
  }

  applyPreviewPanelPosition(row) {
    const position = this.resolvePreviewPosition(row.rowKey, row);

    this.previewPanel = {
      ...this.previewPanel,
      left: position.left,
      top: position.top,
      useFixedPosition: position.useFixedPosition !== false
    };
  }

  connectedCallback() {
    this.applySort();
    this._previewPointerHandlers = bindPreviewPointerListeners(
      () => this.template.querySelector("lightning-datatable"),
      this._previewPointerState
    );
  }

  disconnectedCallback() {
    this.unbindPreviewDismissListeners();
    unbindPreviewPointerListeners(this._previewPointerHandlers);
    this._previewPointerHandlers = null;
  }

  getDatatableElement() {
    return this.template.querySelector("lightning-datatable");
  }

  getPreviewCanvas() {
    return this.template.querySelector("[data-preview-canvas]");
  }

  openPreviewPanel(row) {
    const sourceId = row.previewSourceId || "";

    if (this.previewPanel.isOpen && this.previewPanel.sourceId === sourceId) {
      this.handlePreviewClose();
      return;
    }

    this.capturePreviewAnchorForRow(row);
    const position = this.resolvePreviewPosition(row.rowKey, row);

    this.previewPanel = {
      isOpen: true,
      recordId: row.accountId,
      memberName: row.accountName || "",
      sourceId,
      left: position.left,
      top: position.top,
      useFixedPosition: position.useFixedPosition !== false
    };

    this._ignoreOutsideClick = true;
    const reposition = () => this.applyPreviewPanelPosition(row);
    reposition();
    window.requestAnimationFrame(() => {
      reposition();
      window.requestAnimationFrame(() => {
        reposition();
        this._ignoreOutsideClick = false;
        this.bindPreviewDismissListeners();
      });
    });
    window.setTimeout(reposition, 50);
  }

  bindPreviewDismissListeners() {
    this.unbindPreviewDismissListeners();
    this._boundOutsideClickHandler = (event) => this.handleOutsideClick(event);
    this._boundEscapeHandler = (event) => {
      if (event.key === "Escape") {
        this.handlePreviewClose();
      }
    };

    window.addEventListener("mousedown", this._boundOutsideClickHandler, true);
    window.addEventListener("keydown", this._boundEscapeHandler);
  }

  unbindPreviewDismissListeners() {
    if (this._boundOutsideClickHandler) {
      window.removeEventListener(
        "mousedown",
        this._boundOutsideClickHandler,
        true
      );
      this._boundOutsideClickHandler = null;
    }

    if (this._boundEscapeHandler) {
      window.removeEventListener("keydown", this._boundEscapeHandler);
      this._boundEscapeHandler = null;
    }
  }

  isClickInsidePreviewPopover(event) {
    const popover = this.template.querySelector("c-fsc-rel-member-popover");
    if (!popover) {
      return false;
    }

    const panel = popover.shadowRoot?.querySelector(".member-panel");
    const panelRect = panel?.getBoundingClientRect?.();

    if (
      panelRect &&
      Number.isFinite(event.clientX) &&
      Number.isFinite(event.clientY) &&
      event.clientX >= panelRect.left &&
      event.clientX <= panelRect.right &&
      event.clientY >= panelRect.top &&
      event.clientY <= panelRect.bottom
    ) {
      return true;
    }

    const path = getSafeComposedPath(event);
    return path.includes(popover);
  }

  bindOutsideClickListener() {
    this.bindPreviewDismissListeners();
  }

  unbindOutsideClickListener() {
    this.unbindPreviewDismissListeners();
  }

  handleOutsideClick(event) {
    if (!this.previewPanel.isOpen || this._ignoreOutsideClick) {
      return;
    }

    if (this.isClickInsidePreviewPopover(event)) {
      return;
    }

    if (isPreviewTriggerClick(event, this.getDatatableElement())) {
      return;
    }

    this.handlePreviewClose();
  }

  applySort() {
    this.sortedRows = sortRecords(
      this.sourceRows,
      this.sortedBy,
      this.sortedDirection,
      this.tableColumns
    );
  }

  handleRefresh = async () => {
    if (!this.wiredLinkedContactsResult) {
      return;
    }

    await refreshApex(this.wiredLinkedContactsResult);
    this.lastLoadedAt = Date.now();
  };

  @api
  refresh() {
    return this.handleRefresh();
  }

  handleHeaderLinkClick = (event) => {
    event.preventDefault();

    if (!this.showAll && this.totalCount > this.maxRowsNumber) {
      this.showAll = true;
    }
  };

  handleNew = async () => {
    const result = await SignificantEventCreateActionModal.open({
      description: "Create a new Significant Event",
      recordId: this.recordId,
      editMode: false
    });

    if (result?.refreshed) {
      await this.handleRefresh();
    }
  };

  handleEdit = async (significantEventId) => {
    if (!significantEventId) {
      return;
    }

    const result = await SignificantEventCreateActionModal.open({
      description: "Edit Significant Event",
      recordId: significantEventId,
      editMode: true
    });

    if (result?.refreshed) {
      await this.handleRefresh();
    }
  };

  handleViewAll = (event) => {
    event.preventDefault();
    this.showAll = true;
  };

  handleDatatableSort = (event) => {
    const fieldName = event.detail?.fieldName;
    const sortDirection = event.detail?.sortDirection;

    if (!fieldName || !sortDirection) {
      return;
    }

    this.sortedBy = DATATABLE_TO_SORT_FIELD[fieldName] || fieldName;
    this.sortedDirection = sortDirection;
    this.applySort();
  };

  handleRowAction = async (event) => {
    const actionName = event.detail?.action?.name;
    const row = event.detail?.row;

    if (actionName === "preview_account") {
      if (!row?.accountId) {
        return;
      }

      this.openPreviewPanel(row);
      return;
    }

    if (actionName === "edit_event") {
      await this.handleEdit(row?.significantEventId);
    }
  };

  handlePreviewClose = () => {
    this.unbindPreviewDismissListeners();
    this._previewPointerState.clear();
    this._frozenPreviewAnchorRect = null;
    this.previewPanel = {
      isOpen: false,
      recordId: "",
      memberName: "",
      sourceId: "",
      left: this.previewPanel.left,
      top: this.previewPanel.top,
      useFixedPosition: true
    };
  };
}