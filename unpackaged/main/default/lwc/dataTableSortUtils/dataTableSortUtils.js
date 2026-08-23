/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-15
 *
 * Shared sorting helpers for lightning-datatable and custom table views.
 */
export const SORT_ASC = "asc";
export const SORT_DESC = "desc";

const NUMERIC_COLUMN_TYPES = new Set([
  "number",
  "currency",
  "percent"
]);

const DATE_COLUMN_TYPES = new Set(["date", "date-local"]);

const getNestedValue = (record, fieldName) => {
  if (!record || !fieldName) {
    return null;
  }

  if (!fieldName.includes(".")) {
    return record[fieldName];
  }

  return fieldName.split(".").reduce((current, key) => current?.[key], record);
};

const resolveColumnType = (columns, fieldName) => {
  const column = (columns || []).find((entry) => entry.fieldName === fieldName);
  return column?.sortType || column?.type || "text";
};

// A column can display one field but sort by another. `sortFieldName` opts into
// that — e.g. a column that renders a formatted "Jul 17, 2026 12:31 - Name"
// string but sorts on the raw datetime. Falls back to the displayed field.
const resolveSortField = (columns, fieldName) => {
  const column = (columns || []).find((entry) => entry.fieldName === fieldName);
  return column?.sortFieldName || fieldName;
};

const isColumnSortable = (columns, fieldName) => {
  const column = (columns || []).find((entry) => entry.fieldName === fieldName);

  if (!column) {
    return true;
  }

  return column.sortable !== false;
};

const normalizeForCompare = (value, columnType) => {
  if (value === null || value === undefined || value === "") {
    return null;
  }

  if (NUMERIC_COLUMN_TYPES.has(columnType)) {
    const numericValue = Number(value);
    return Number.isNaN(numericValue) ? null : numericValue;
  }

  if (DATE_COLUMN_TYPES.has(columnType)) {
    const timestamp = new Date(value).getTime();
    return Number.isNaN(timestamp) ? null : timestamp;
  }

  if (columnType === "boolean") {
    return value === true || value === "true" ? 1 : 0;
  }

  return String(value).toLowerCase();
};

export const compareValues = (firstValue, secondValue, columnType = "text") => {
  const firstNormalized = normalizeForCompare(firstValue, columnType);
  const secondNormalized = normalizeForCompare(secondValue, columnType);

  if (firstNormalized === null && secondNormalized === null) {
    return 0;
  }

  if (firstNormalized === null) {
    return 1;
  }

  if (secondNormalized === null) {
    return -1;
  }

  if (
    typeof firstNormalized === "number" &&
    typeof secondNormalized === "number"
  ) {
    return firstNormalized - secondNormalized;
  }

  return String(firstNormalized).localeCompare(
    String(secondNormalized),
    undefined,
    { sensitivity: "base", numeric: true }
  );
};

export const sortRecords = (
  records,
  fieldName,
  sortDirection = SORT_ASC,
  columns = [],
  resolveValue
) => {
  if (!Array.isArray(records) || !fieldName) {
    return [...(records || [])];
  }

  if (!isColumnSortable(columns, fieldName)) {
    return [...records];
  }

  const column = (columns || []).find((entry) => entry.fieldName === fieldName);
  const columnType = resolveColumnType(columns, fieldName);
  const sortField = resolveSortField(columns, fieldName);
  const directionMultiplier = sortDirection === SORT_DESC ? -1 : 1;

  return [...records].sort((first, second) => {
    const firstValue = resolveValue
      ? resolveValue(first, sortField, column)
      : getNestedValue(first, sortField);
    const secondValue = resolveValue
      ? resolveValue(second, sortField, column)
      : getNestedValue(second, sortField);

    return (
      compareValues(firstValue, secondValue, columnType) * directionMultiplier
    );
  });
};

export const resolveSortDirection = (
  fieldName,
  currentField,
  currentDirection = SORT_ASC
) => {
  if (fieldName === currentField) {
    return currentDirection === SORT_ASC ? SORT_DESC : SORT_ASC;
  }

  return SORT_ASC;
};

export const createSortState = ({
  fieldName = "",
  direction = SORT_ASC,
  records = [],
  columns = []
} = {}) => {
  const sortedBy = fieldName || "";
  const sortedDirection = direction || SORT_ASC;
  const sortedData = sortedBy
    ? sortRecords(records, sortedBy, sortedDirection, columns)
    : [...(records || [])];

  return {
    sortedBy,
    sortedDirection,
    sortedData
  };
};