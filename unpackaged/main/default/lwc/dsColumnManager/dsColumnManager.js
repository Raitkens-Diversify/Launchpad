/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-22
 */
import { LightningElement, api, wire, track } from "lwc";
import { loadStyle } from "lightning/platformResourceLoader";
import getAccessibleFields from "@salesforce/apex/ObjectFieldController.getAccessibleFields";
import diversifyStyles from "@salesforce/resourceUrl/diversifyStyles";

const NUMERIC_FIELD_TOKENS = ["CURRENCY", "DOUBLE", "INTEGER", "PERCENT"];

const buildColumnFromFieldOption = (fieldOption) => {
  const apiName = fieldOption.apiName;
  const fieldType = (fieldOption.type || "STRING").toUpperCase();
  const isNumeric = NUMERIC_FIELD_TOKENS.some((token) =>
    fieldType.includes(token)
  );

  return {
    key: apiName,
    label: fieldOption.label || apiName,
    fieldName: apiName,
    type: isNumeric ? "currency" : "text",
    sortable: fieldOption.sortable !== false,
    visible: true,
    numeric: isNumeric
  };
};

const CLASS_NAMES = Object.freeze({
  modal: "div-modal",
  modalBackdrop: "div-modal__backdrop",
  modalPanel: "div-modal__panel",
  modalPanelWide: "div-modal__panel--wide",
  modalHeader: "div-modal__header",
  modalIntro: "div-modal__intro",
  modalTitle: "div-modal__title",
  modalSubtitle: "div-modal__subtitle",
  modalBody: "div-modal__body",
  modalFooter: "div-modal__footer",
  modalFooterHint: "div-modal__footer-hint",
  modalFooterActions: "div-modal__footer-actions",
  modalActions: "div-modal__actions",
  modalMoveButton: "div-modal__move-button",
  btn: "div-btn",
  btnPrimary: "div-btn div-btn--primary",
  btnGroup: "div-btn-group",
  input: "div-input",
  rootEmbedded: "ds-column-manager__embedded",
  embeddedPanel: "ds-column-manager__embedded-panel",
  embeddedBody: "ds-column-manager__embedded-body",
  search: "ds-column-manager__search",
  searchInput: "ds-column-manager__search-input",
  panels: "ds-column-manager__panels",
  panelsTwoCol: "ds-column-manager__panels--two-col",
  panel: "ds-column-manager__panel",
  panelAvailable: "ds-column-manager__panel--available",
  panelActive: "ds-column-manager__panel--active",
  panelHeader: "ds-column-manager__panel-header",
  panelTitle: "ds-column-manager__panel-title",
  panelCount: "ds-column-manager__panel-count",
  list: "ds-column-manager__list",
  item: "ds-column-manager__item",
  itemActive: "ds-column-manager__item--active",
  itemDragging: "ds-column-manager__item--dragging",
  itemHidden: "ds-column-manager__item--hidden",
  itemAvailable: "ds-column-manager__item--available",
  dropBefore: "ds-column-manager__item--drop-before",
  dropAfter: "ds-column-manager__item--drop-after",
  listDropEnd: "ds-column-manager__list--drop-end",
  fieldCopy: "ds-column-manager__field-copy",
  label: "ds-column-manager__label",
  apiName: "ds-column-manager__api-name",
  position: "ds-column-manager__position",
  dragHandle: "ds-column-manager__drag-handle",
  visibilityIcon: "ds-column-manager__visibility-icon",
  empty: "ds-column-manager__empty"
});

const PANEL_AVAILABLE_CLASS = `${CLASS_NAMES.panel} ${CLASS_NAMES.panelAvailable}`;
const PANEL_ACTIVE_CLASS = `${CLASS_NAMES.panel} ${CLASS_NAMES.panelActive}`;
const HIDDEN_ITEM_CLASS = `${CLASS_NAMES.item} ${CLASS_NAMES.itemHidden}`;
const AVAILABLE_ITEM_CLASS = `${CLASS_NAMES.item} ${CLASS_NAMES.itemAvailable}`;
const MODAL_PANEL_CLASS = `${CLASS_NAMES.modalPanel} ${CLASS_NAMES.modalPanelWide}`;

const joinClasses = (...values) =>
  values.filter((value) => Boolean(value && String(value).trim())).join(" ");

const isColumnVisible = (column) => column.visible !== false;

const cloneColumns = (columns = []) => columns.map((column) => ({ ...column }));

const matchesSearch = (normalizedSearch, label, apiName) => {
  if (!normalizedSearch) {
    return true;
  }

  const normalizedLabel = (label || "").toLowerCase();
  const normalizedApiName = (apiName || "").toLowerCase();

  return (
    normalizedLabel.includes(normalizedSearch) ||
    normalizedApiName.includes(normalizedSearch)
  );
};

const getActiveIndices = (columns) => {
  const indices = [];

  for (let index = 0; index < columns.length; index += 1) {
    if (isColumnVisible(columns[index])) {
      indices.push(index);
    }
  }

  return indices;
};

const moveColumnInArray = (columns, fromIndex, toIndex) => {
  if (
    fromIndex < 0 ||
    toIndex < 0 ||
    fromIndex >= columns.length ||
    toIndex >= columns.length ||
    fromIndex === toIndex
  ) {
    return columns;
  }

  const nextColumns = [...columns];
  const [movedColumn] = nextColumns.splice(fromIndex, 1);
  nextColumns.splice(toIndex, 0, movedColumn);
  return nextColumns;
};

const setColumnVisibility = (columns, columnKey, isVisible) => {
  const nextColumns = columns.map((column) =>
    column.key === columnKey ? { ...column, visible: isVisible } : column
  );

  if (!isVisible) {
    let activeCount = 0;

    for (const column of nextColumns) {
      if (isColumnVisible(column)) {
        activeCount += 1;
      }
    }

    if (activeCount === 0) {
      return columns;
    }
  }

  return nextColumns;
};

const moveActiveColumn = (columns, columnKey, direction) => {
  const activeIndices = getActiveIndices(columns);
  let currentPosition = -1;

  for (let index = 0; index < activeIndices.length; index += 1) {
    if (columns[activeIndices[index]].key === columnKey) {
      currentPosition = index;
      break;
    }
  }

  if (currentPosition < 0) {
    return columns;
  }

  const targetPosition =
    direction === "up" ? currentPosition - 1 : currentPosition + 1;

  if (targetPosition < 0 || targetPosition >= activeIndices.length) {
    return columns;
  }

  return moveColumnInArray(
    columns,
    activeIndices[currentPosition],
    activeIndices[targetPosition]
  );
};

const showColumnAtEndOfActive = (columns, columnKey) => {
  const nextColumns = setColumnVisibility(columns, columnKey, true);
  const columnIndex = nextColumns.findIndex((column) => column.key === columnKey);

  if (columnIndex < 0) {
    return nextColumns;
  }

  const activeIndices = getActiveIndices(nextColumns);
  const lastActiveIndex = activeIndices[activeIndices.length - 1];
  return moveColumnInArray(nextColumns, columnIndex, lastActiveIndex);
};

const insertColumnBefore = (columns, columnKey, targetKey) => {
  const sourceIndex = columns.findIndex((column) => column.key === columnKey);
  const targetIndex = columns.findIndex((column) => column.key === targetKey);

  if (sourceIndex < 0 || targetIndex < 0) {
    return columns;
  }

  const nextColumns = isColumnVisible(columns[sourceIndex])
    ? columns
    : setColumnVisibility(columns, columnKey, true);

  const refreshedSourceIndex = nextColumns.findIndex(
    (column) => column.key === columnKey
  );
  const refreshedTargetIndex = nextColumns.findIndex(
    (column) => column.key === targetKey
  );

  return moveColumnInArray(
    nextColumns,
    refreshedSourceIndex,
    refreshedTargetIndex
  );
};

const appendColumnDefinition = (columns, columnDefinition) => {
  const existingIndex = columns.findIndex(
    (column) => column.key === columnDefinition.key
  );

  if (existingIndex >= 0) {
    return setColumnVisibility(columns, columnDefinition.key, true);
  }

  return [...columns, { ...columnDefinition, visible: true }];
};

const buildActiveItemClass = (isDragging, showDropBefore, showDropAfter) =>
  joinClasses(
    CLASS_NAMES.item,
    CLASS_NAMES.itemActive,
    isDragging ? CLASS_NAMES.itemDragging : null,
    showDropBefore ? CLASS_NAMES.dropBefore : null,
    showDropAfter ? CLASS_NAMES.dropAfter : null
  );

const resolveDropPlacement = (event) => {
  const rect = event.currentTarget.getBoundingClientRect();
  const offset = event.clientY - rect.top;

  return offset < rect.height / 2 ? "before" : "after";
};

const buildAvailableListItem = (item) => ({
  ...item,
  iconName: "utility:add",
  itemClass: AVAILABLE_ITEM_CLASS
});

export default class DsColumnManager extends LightningElement {
  @api columns = [];
  @api defaultColumns = [];
  @api objectApiName = "Account";
  @api title = "Manage columns";
  @api subtitle = "Search fields, drag to reorder, and click to toggle visibility.";
  @api footerHint = "Drag between panels to show/hide.";
  @api embedded = false;
  @api showHiddenPanel = false;
  @api panelCountClass = "";

  _isOpen = false;
  _stylesLoaded = false;
  _viewVersion = 0;
  _viewCacheToken = "";
  _viewCache = null;
  _fieldOptionByApiName = new Map();

  draftColumns = [];
  availableFields = [];
  fieldSearchTerm = "";

  @track draggedColumnKey = null;
  @track dragOverKey = null;
  @track dropPlacement = "before";
  didDrag = false;

  @wire(getAccessibleFields, { objectApiName: "$objectApiName" })
  wiredAccessibleFields({ data, error }) {
    if (data) {
      this.availableFields = data;
      this._fieldOptionByApiName = new Map(
        data.map((fieldOption) => [fieldOption.apiName, fieldOption])
      );
      this.invalidateView();
      return;
    }

    if (error) {
      console.warn("[dsColumnManager] Failed to load accessible fields", error);
      this.availableFields = [];
      this._fieldOptionByApiName = new Map();
      this.invalidateView();
    }
  }

  connectedCallback() {
    if (!this._stylesLoaded) {
      this._stylesLoaded = true;
      loadStyle(this, diversifyStyles).catch(() => {
        this._stylesLoaded = false;
      });
    }

    this._handleWindowDragEnd = this.handleDragEnd.bind(this);

    if (this.embedded) {
      this.initializeDraftColumns(this.columns);
    }
  }

  disconnectedCallback() {
    window.removeEventListener("dragend", this._handleWindowDragEnd);
  }

  @api
  get isOpen() {
    return this._isOpen;
  }

  set isOpen(value) {
    const nextValue = Boolean(value);

    if (nextValue && !this._isOpen) {
      this.initializeDraftColumns(this.columns);
    }

    this._isOpen = nextValue;
  }

  @api
  initializeDraftColumns(columns = []) {
    this.draftColumns = cloneColumns(columns);
    this.fieldSearchTerm = "";
    this.invalidateView();
  }

  @api
  getDraftColumns() {
    return cloneColumns(this.draftColumns);
  }

  invalidateView() {
    this._viewVersion += 1;
    this._viewCache = null;
    this._viewCacheToken = "";
  }

  get snapshot() {
    const token = `${this._viewVersion}|${this.fieldSearchTerm}|${this.draggedColumnKey}|${this.dragOverKey}|${this.dropPlacement}|${this.showHiddenPanel}`;

    if (this._viewCacheToken === token && this._viewCache) {
      return this._viewCache;
    }

    this._viewCache = this.composeView();
    this._viewCacheToken = token;
    return this._viewCache;
  }

  composeView() {
    const columns = this.draftColumns || [];
    const normalizedSearch = (this.fieldSearchTerm || "").trim().toLowerCase();
    const draggedKey = this.draggedColumnKey;
    const dragOverKey = this.dragOverKey;
    const placement = this.dropPlacement;

    const activeColumns = [];
    const hiddenColumns = [];
    const activeKeys = new Set();
    const managedKeys = new Set();

    for (const column of columns) {
      managedKeys.add(column.key);

      if (isColumnVisible(column)) {
        activeKeys.add(column.key);
        activeColumns.push(column);
        continue;
      }

      hiddenColumns.push(column);
    }

    const activeItems = activeColumns.map((column, index) => {
      const key = column.key;
      const showDropBefore = dragOverKey === key && placement === "before";
      const showDropAfter = dragOverKey === key && placement === "after";

      return {
        key,
        label: column.label,
        apiName: column.fieldName || column.key,
        position: index + 1,
        canMoveUp: index > 0,
        canMoveDown: index < activeColumns.length - 1,
        moveUpAriaLabel: `Move ${column.label} up`,
        moveDownAriaLabel: `Move ${column.label} down`,
        hideAriaLabel: `Hide ${column.label}`,
        itemClass: buildActiveItemClass(
          key === draggedKey,
          showDropBefore,
          showDropAfter
        )
      };
    });

    const hiddenItems = hiddenColumns.map((column) => ({
      key: column.key,
      label: column.label,
      showAriaLabel: `Show ${column.label}`
    }));

    const hiddenColumnItems = [];

    if (!this.showHiddenPanel) {
      for (const column of hiddenColumns) {
        const apiName = column.fieldName || column.key;

        if (
          activeKeys.has(column.key) ||
          !matchesSearch(normalizedSearch, column.label, apiName)
        ) {
          continue;
        }

        hiddenColumnItems.push(
          buildAvailableListItem({
            key: column.key,
            label: column.label,
            apiName,
            source: "hidden",
            actionAriaLabel: `Show ${column.label} column`
          })
        );
      }
    }

    const fieldItems = [];

    for (const fieldOption of this.availableFields || []) {
      const apiName = fieldOption.apiName;

      if (
        managedKeys.has(apiName) ||
        !matchesSearch(normalizedSearch, fieldOption.label, apiName)
      ) {
        continue;
      }

      fieldItems.push(
        buildAvailableListItem({
          key: apiName,
          label: fieldOption.label,
          apiName,
          source: "field",
          actionAriaLabel: `Add ${fieldOption.label} column`
        })
      );
    }

    const availableItems = this.showHiddenPanel
      ? fieldItems
      : hiddenColumnItems.concat(
          fieldItems.filter((item) => !activeKeys.has(item.key))
        );

    const showDropAtEnd =
      Boolean(draggedKey) && !dragOverKey && placement === "end";

    return {
      activeItems,
      hiddenItems,
      availableItems,
      activeCount: activeItems.length,
      hiddenCount: hiddenItems.length,
      availableCount: availableItems.length,
      activeListClass: joinClasses(
        CLASS_NAMES.list,
        showDropAtEnd ? CLASS_NAMES.listDropEnd : null
      )
    };
  }

  get shouldRender() {
    return this.embedded || this._isOpen;
  }

  get isModalMode() {
    return !this.embedded;
  }

  get c() {
    return CLASS_NAMES;
  }

  get panelAvailablePanelClass() {
    return PANEL_AVAILABLE_CLASS;
  }

  get panelActivePanelClass() {
    return PANEL_ACTIVE_CLASS;
  }

  get hiddenItemClass() {
    return HIDDEN_ITEM_CLASS;
  }

  get panelCountClassName() {
    return joinClasses(CLASS_NAMES.panelCount, this.panelCountClass);
  }

  get rootClass() {
    return this.embedded ? CLASS_NAMES.rootEmbedded : CLASS_NAMES.modal;
  }

  get panelClass() {
    return this.embedded ? CLASS_NAMES.embeddedPanel : MODAL_PANEL_CLASS;
  }

  get bodyClass() {
    return this.embedded ? CLASS_NAMES.embeddedBody : CLASS_NAMES.modalBody;
  }

  get panelsClass() {
    return joinClasses(
      CLASS_NAMES.panels,
      !this.showHiddenPanel ? CLASS_NAMES.panelsTwoCol : null
    );
  }

  get dialogRole() {
    return this.isModalMode ? "dialog" : undefined;
  }

  get ariaModal() {
    return this.isModalMode ? "true" : undefined;
  }

  get activeItems() {
    return this.snapshot.activeItems;
  }

  get activeListClass() {
    return this.snapshot.activeListClass;
  }

  get hiddenItems() {
    return this.snapshot.hiddenItems;
  }

  get availableItems() {
    return this.snapshot.availableItems;
  }

  get activeCount() {
    return this.snapshot.activeCount;
  }

  get hiddenCount() {
    return this.snapshot.hiddenCount;
  }

  get availableCount() {
    return this.snapshot.availableCount;
  }

  get hasNoActiveColumns() {
    return this.snapshot.activeCount === 0;
  }

  get hasNoHiddenColumns() {
    return this.snapshot.hiddenCount === 0;
  }

  get hasNoAvailableFields() {
    return this.snapshot.availableCount === 0;
  }

  updateDraftColumns(nextColumns) {
    this.draftColumns = nextColumns;
    this.invalidateView();
    this.dispatchEvent(
      new CustomEvent("draftchange", {
        detail: {
          columns: cloneColumns(nextColumns)
        }
      })
    );
  }

  handleDismiss() {
    this.dispatchEvent(new CustomEvent("close"));
  }

  handleSave() {
    this.dispatchEvent(
      new CustomEvent("save", {
        detail: {
          columns: cloneColumns(this.draftColumns)
        }
      })
    );
    this.dispatchEvent(new CustomEvent("close"));
  }

  handleReset() {
    const resetSource =
      this.defaultColumns?.length > 0 ? this.defaultColumns : this.columns;
    this.draftColumns = cloneColumns(resetSource);
    this.invalidateView();
  }

  handleFieldSearchChange(event) {
    this.fieldSearchTerm = event.detail.value ?? event.target.value ?? "";
  }

  handleAvailableItemClick(event) {
    const itemKey = event.currentTarget.dataset.key;
    const itemSource = event.currentTarget.dataset.source;

    if (itemSource === "hidden") {
      this.updateDraftColumns(
        showColumnAtEndOfActive(this.draftColumns, itemKey)
      );
      return;
    }

    const fieldOption = this._fieldOptionByApiName.get(itemKey);

    if (!fieldOption) {
      return;
    }

    this.updateDraftColumns(
      appendColumnDefinition(
        this.draftColumns,
        buildColumnFromFieldOption(fieldOption)
      )
    );
  }

  handleAvailableFieldKeyDown(event) {
    if (event.key !== "Enter" && event.key !== " ") {
      return;
    }

    event.preventDefault();
    this.handleAvailableItemClick(event);
  }

  handleMoveActive(event) {
    event.stopPropagation();
    const columnKey = event.currentTarget.dataset.key;
    const direction = event.currentTarget.dataset.direction;
    this.updateDraftColumns(
      moveActiveColumn(this.draftColumns, columnKey, direction)
    );
  }

  handleHideColumn(event) {
    if (this.didDrag) {
      this.didDrag = false;
      return;
    }

    const columnKey = event.currentTarget.dataset.key;
    this.updateDraftColumns(
      setColumnVisibility(this.draftColumns, columnKey, false)
    );
  }

  handleActiveKeyDown(event) {
    if (event.key !== "Enter" && event.key !== " ") {
      return;
    }

    event.preventDefault();
    this.handleHideColumn(event);
  }

  handleStopClick(event) {
    event.stopPropagation();
  }

  handleShowColumn(event) {
    const columnKey = event.currentTarget.dataset.key;
    this.updateDraftColumns(
      showColumnAtEndOfActive(this.draftColumns, columnKey)
    );
  }

  handleHiddenKeyDown(event) {
    if (event.key !== "Enter" && event.key !== " ") {
      return;
    }

    event.preventDefault();
    this.handleShowColumn(event);
  }

  handleDragStart(event) {
    event.stopPropagation();
    this.didDrag = false;
    const columnKey = event.currentTarget.dataset.key;
    this.draggedColumnKey = columnKey;
    this.clearDropIndicator();
    event.dataTransfer.effectAllowed = "move";
    event.dataTransfer.setData("text/plain", columnKey);
    window.addEventListener("dragend", this._handleWindowDragEnd, { once: true });
  }

  handleDragEnd() {
    window.removeEventListener("dragend", this._handleWindowDragEnd);
    this.didDrag = true;
    this.clearDragState();
  }

  handleDragOver(event) {
    event.preventDefault();
    event.dataTransfer.dropEffect = "move";
  }

  handleActivePanelDragHover(event) {
    event.preventDefault();
    event.dataTransfer.dropEffect = "move";

    if (!this.draggedColumnKey) {
      return;
    }

    if (this.dragOverKey !== null || this.dropPlacement !== "end") {
      this.dragOverKey = null;
      this.dropPlacement = "end";
    }
  }

  handleActiveItemDragOver(event) {
    event.preventDefault();
    event.stopPropagation();
    event.dataTransfer.dropEffect = "move";

    const targetKey = event.currentTarget.dataset.key;
    const draggedKey = this.draggedColumnKey;

    if (!draggedKey || !targetKey || draggedKey === targetKey) {
      return;
    }

    const placement = resolveDropPlacement(event);

    if (this.dragOverKey !== targetKey || this.dropPlacement !== placement) {
      this.dragOverKey = targetKey;
      this.dropPlacement = placement;
    }
  }

  handleActiveItemDragLeave(event) {
    const targetKey = event.currentTarget.dataset.key;

    if (this.dragOverKey === targetKey) {
      this.clearDropIndicator();
    }
  }

  handleActiveListDragLeave(event) {
    if (!this.draggedColumnKey) {
      return;
    }

    const list = event.currentTarget.getBoundingClientRect();
    const { clientX, clientY } = event;

    if (
      clientX < list.left ||
      clientX > list.right ||
      clientY < list.top ||
      clientY > list.bottom
    ) {
      this.clearDropIndicator();
    }
  }

  clearDropIndicator() {
    this.dragOverKey = null;
    this.dropPlacement = "before";
  }

  clearDragState() {
    this.draggedColumnKey = null;
    this.clearDropIndicator();
  }

  handleDropOnActivePanel(event) {
    event.preventDefault();
    event.stopPropagation();

    const columnKey = this.getDraggedColumnKey(event);
    this.clearDragState();

    if (!columnKey) {
      return;
    }

    this.updateDraftColumns(
      showColumnAtEndOfActive(this.draftColumns, columnKey)
    );
  }

  handleDropOnActiveItem(event) {
    event.preventDefault();
    event.stopPropagation();

    const columnKey = this.getDraggedColumnKey(event);
    const targetKey = event.currentTarget.dataset.key;
    const placement = this.dropPlacement;
    this.clearDragState();

    if (!columnKey) {
      return;
    }

    let nextColumns = this.draftColumns;

    if (!targetKey || columnKey === targetKey) {
      nextColumns = showColumnAtEndOfActive(this.draftColumns, columnKey);
    } else if (placement === "after") {
      const activeKeys = this.getActiveColumnKeys();
      const targetIndex = activeKeys.indexOf(targetKey);
      const nextKey = activeKeys[targetIndex + 1];

      nextColumns = nextKey
        ? insertColumnBefore(this.draftColumns, columnKey, nextKey)
        : showColumnAtEndOfActive(this.draftColumns, columnKey);
    } else {
      nextColumns = insertColumnBefore(
        this.draftColumns,
        columnKey,
        targetKey
      );
    }

    this.updateDraftColumns(nextColumns);
  }

  handleDropOnHiddenPanel(event) {
    event.preventDefault();
    event.stopPropagation();

    const columnKey = this.getDraggedColumnKey(event);
    this.clearDragState();

    if (!columnKey) {
      return;
    }

    this.updateDraftColumns(
      setColumnVisibility(this.draftColumns, columnKey, false)
    );
  }

  getActiveColumnKeys() {
    return this.snapshot.activeItems.map((item) => item.key);
  }

  getDraggedColumnKey(event) {
    return (
      event.dataTransfer.getData("text/plain") ||
      this.draggedColumnKey ||
      event.currentTarget.dataset.key
    );
  }
}