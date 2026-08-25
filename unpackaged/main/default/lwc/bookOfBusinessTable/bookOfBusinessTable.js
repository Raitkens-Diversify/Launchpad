/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-22
 */
import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { openRecordInNewTab } from "c/recordNavigationUtils";
import {
  SORT_ASC,
  SORT_DESC,
  getCellDisplayValue,
  getVisibleColumns
} from "c/bookOfBusinessUtils";

export default class BookOfBusinessTable extends NavigationMixin(LightningElement) {
  @api tableRows = [];
  @api columns = [];
  @api sortField = "accountName";
  @api sortDirection = SORT_ASC;

  get visibleColumns() {
    return getVisibleColumns(this.columns);
  }

  get visibleColumnCount() {
    return this.visibleColumns.length;
  }

  get headerColumns() {
    return this.visibleColumns.map((column) => {
      const isSorted = column.fieldName === this.sortField;
      const sortIcon =
        isSorted && this.sortDirection === SORT_DESC
          ? "utility:arrowdown"
          : "utility:arrowup";

      return {
        key: column.key,
        label: column.label,
        fieldName: column.fieldName,
        headerClass: column.numeric ? "div-table__cell--numeric" : "",
        sortIcon,
        sortIconClass: isSorted ? "div-table__sort-icon div-table__sort-icon--active" : "div-table__sort-icon",
        ariaSort: isSorted
          ? this.sortDirection === SORT_ASC
            ? "ascending"
            : "descending"
          : "none"
      };
    });
  }

  get decoratedRows() {
    return (this.tableRows || []).map((entry) => {
      if (entry.type === "group") {
        return {
          key: entry.key,
          isGroup: true,
          label: entry.label,
          colspan: this.visibleColumnCount
        };
      }

      const cells = this.visibleColumns.map((column) => {
        const displayValue = getCellDisplayValue(entry.row, column);
        const isNavigableLink = column.isLink && entry.row.accountId;
        const isStyledLink = column.isLink && !entry.row.accountId;

        return {
          key: `${entry.key}-${column.key}`,
          label: column.label,
          value: displayValue,
          cellClass: column.numeric ? "div-table__cell--numeric" : "",
          isNavigableLink,
          isStyledLink,
          accountId: entry.row.accountId
        };
      });

      return {
        key: entry.key,
        isGroup: false,
        cells
      };
    });
  }

  handleSort(event) {
    const fieldName = event.currentTarget.dataset.field;
    this.dispatchEvent(
      new CustomEvent("sortchange", {
        detail: {
          fieldName
        }
      })
    );
  }

  handleAccountNavigate(event) {
    const accountId = event.currentTarget.dataset.accountId;
    openRecordInNewTab(this, accountId);
  }
}