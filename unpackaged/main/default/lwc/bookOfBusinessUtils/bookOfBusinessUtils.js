/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-22
 *
 * Shared constants, formatters, and view-state helpers for Book of Business.
 */
import { SORT_ASC, SORT_DESC, sortRecords } from "c/dataTableSortUtils";

export const VIEW_MODE_TABLE = "table";
export const VIEW_MODE_CHART = "chart";
export const CHART_TYPE_BAR = "bar";
export const CHART_TYPE_PIE = "pie";
export const GROUP_BY_NONE = "none";
export const APPLICATION_NAME = "bookOfBusinessTab";

export const TAB_DETAILS = "details";
export const TAB_RELATED = "related";
export const TAB_FILES = "files";
export const TAB_BOOK_OF_BUSINESS = "book-of-business";
export const TAB_ACTIVITY = "activity";
export const TAB_CHATTER = "chatter";
export const DEFAULT_RECORD_TAB = TAB_BOOK_OF_BUSINESS;

export const RECORD_TABS = Object.freeze([
  { label: "Details", value: TAB_DETAILS },
  { label: "Related", value: TAB_RELATED },
  { label: "Files", value: TAB_FILES },
  { label: "Book of Business", value: TAB_BOOK_OF_BUSINESS },
  { label: "Activity", value: TAB_ACTIVITY },
  { label: "Chatter", value: TAB_CHATTER }
]);

export const getRecordTabLabel = (tabValue) => {
  const tab = RECORD_TABS.find((entry) => entry.value === tabValue);
  return tab?.label || tabValue || "";
};

export const isBookOfBusinessTab = (tabValue) => tabValue === TAB_BOOK_OF_BUSINESS;

export const MOCK_BOOK_OF_BUSINESS_PAYLOAD = Object.freeze({
  title: "Book of Business",
  subtitle: "Related client accounts for Harrison Family Household",
  summary: {
    accountCount: 4,
    totalAumLabel: "$19.99M",
    totalAumValue: 19990000
  },
  kpis: [
    {
      id: "total-aum",
      label: "TOTAL AUM",
      value: "$19.99M",
      subtext: "4 accounts",
      trendLabel: "+8.4% YTD",
      trendDirection: "positive"
    },
    {
      id: "revenue-t12",
      label: "REVENUE T12",
      value: "$292K",
      subtext: "vs $271K prior year",
      trendLabel: "+7.7% YoY",
      trendDirection: "positive"
    },
    {
      id: "client-since",
      label: "CLIENT SINCE",
      value: "2009",
      subtext: "15-year relationship",
      trendLabel: null,
      trendDirection: null
    },
    {
      id: "next-review",
      label: "NEXT REVIEW",
      value: "Aug 14",
      subtext: "2025 · 43 days away",
      trendLabel: null,
      trendDirection: null
    }
  ],
  accounts: [
    {
      id: "row-1",
      accountName: "Harrison Family Trust",
      role: "Trustee",
      recordType: "Trust",
      association: "Member",
      totalAum: 8200000,
      totalAumLabel: "$8,200,000",
      revenueT12: 124000,
      revenueT12Label: "$124,000",
      state: "CA",
      wealthSegment: "Ultra HNW"
    },
    {
      id: "row-2",
      accountName: "John Harrison",
      role: "Primary",
      recordType: "Individual",
      association: "Primary",
      totalAum: 6100000,
      totalAumLabel: "$6,100,000",
      revenueT12: 89000,
      revenueT12Label: "$89,000",
      state: "CA",
      wealthSegment: "HNW"
    },
    {
      id: "row-3",
      accountName: "Sarah Harrison",
      role: "Spouse",
      recordType: "Individual",
      association: "Member",
      totalAum: 3400000,
      totalAumLabel: "$3,400,000",
      revenueT12: 48000,
      revenueT12Label: "$48,000",
      state: "CA",
      wealthSegment: "Affluent"
    },
    {
      id: "row-4",
      accountName: "Harrison LLC",
      role: "Authorized",
      recordType: "Business",
      association: "Member",
      totalAum: 2290000,
      totalAumLabel: "$2,290,000",
      revenueT12: 31000,
      revenueT12Label: "$31,000",
      state: "NV",
      wealthSegment: "Mass Affluent"
    }
  ]
});

export const GROUP_BY_OPTIONS = Object.freeze([
  { label: "None", value: GROUP_BY_NONE },
  { label: "Role", value: "role" },
  { label: "Record Type", value: "recordType" },
  { label: "Association", value: "association" },
  { label: "State", value: "state" }
]);

export const DEFAULT_COLUMNS = Object.freeze([
  {
    key: "accountName",
    label: "Account Name",
    fieldName: "accountName",
    type: "text",
    sortable: true,
    visible: true,
    isLink: true
  },
  {
    key: "role",
    label: "Role",
    fieldName: "role",
    type: "text",
    sortable: true,
    visible: true
  },
  {
    key: "recordType",
    label: "Record Type",
    fieldName: "recordType",
    type: "text",
    sortable: true,
    visible: true
  },
  {
    key: "association",
    label: "Association",
    fieldName: "association",
    type: "text",
    sortable: true,
    visible: true
  },
  {
    key: "totalAum",
    label: "Total AUM",
    fieldName: "totalAum",
    type: "currency",
    sortable: true,
    visible: true,
    numeric: true,
    displayField: "totalAumLabel"
  },
  {
    key: "revenueT12",
    label: "Revenue T12",
    fieldName: "revenueT12",
    type: "currency",
    sortable: true,
    visible: true,
    numeric: true,
    displayField: "revenueT12Label"
  },
  {
    key: "state",
    label: "State",
    fieldName: "state",
    type: "text",
    sortable: true,
    visible: true
  }
]);

export const FILTER_FIELDS = Object.freeze([
  { key: "role", label: "Role", fieldName: "role" },
  { key: "recordType", label: "Record Type", fieldName: "recordType" },
  { key: "association", label: "Association", fieldName: "association" },
  { key: "state", label: "State", fieldName: "state" }
]);

export const createDefaultViewState = () => ({
  viewMode: VIEW_MODE_TABLE,
  groupBy: GROUP_BY_NONE,
  sortField: "accountName",
  sortDirection: SORT_ASC,
  chartType: CHART_TYPE_PIE,
  columns: cloneColumns(DEFAULT_COLUMNS),
  filters: createEmptyFilters()
});

export const cloneColumns = (columns = DEFAULT_COLUMNS) =>
  (columns || []).map((column) => ({ ...column }));

export const createEmptyFilters = () =>
  FILTER_FIELDS.reduce((accumulator, field) => {
    accumulator[field.key] = [];
    return accumulator;
  }, {});

export const normalizeAccountRows = (accounts = []) =>
  (accounts || []).map((row) => ({
    ...row,
    ...(row.extraFields || {}),
    id: row.id || row.accountId || row.accountName
  }));

export const getVisibleColumns = (columns = DEFAULT_COLUMNS) =>
  (columns || []).filter((column) => column.visible !== false);

export const getUniqueFilterValues = (rows = [], fieldName) => {
  const values = new Set();

  (rows || []).forEach((row) => {
    const value = row[fieldName];
    if (value !== null && value !== undefined && value !== "") {
      values.add(String(value));
    }
  });

  return [...values].sort((first, second) =>
    first.localeCompare(second, undefined, { sensitivity: "base" })
  );
};

export const applyFilters = (rows = [], filters = {}) => {
  const activeFilterKeys = Object.keys(filters || {}).filter(
    (key) => Array.isArray(filters[key]) && filters[key].length > 0
  );

  if (activeFilterKeys.length === 0) {
    return [...(rows || [])];
  }

  return (rows || []).filter((row) =>
    activeFilterKeys.every((key) => {
      const fieldName = FILTER_FIELDS.find((field) => field.key === key)?.fieldName || key;
      return filters[key].includes(String(row[fieldName] ?? ""));
    })
  );
};

export const applySort = (rows = [], sortField, sortDirection, columns = DEFAULT_COLUMNS) =>
  sortRecords(rows, sortField, sortDirection, columns);

export const buildGroupedTableRows = (rows = [], groupBy = GROUP_BY_NONE) => {
  if (!groupBy || groupBy === GROUP_BY_NONE) {
    return (rows || []).map((row) => ({
      key: row.id,
      type: "data",
      row
    }));
  }

  const fieldName =
    GROUP_BY_OPTIONS.find((option) => option.value === groupBy)?.value || groupBy;
  const grouped = new Map();

  (rows || []).forEach((row) => {
    const groupValue = String(row[fieldName] ?? "—");
    if (!grouped.has(groupValue)) {
      grouped.set(groupValue, []);
    }
    grouped.get(groupValue).push(row);
  });

  const tableRows = [];

  [...grouped.keys()]
    .sort((first, second) =>
      first.localeCompare(second, undefined, { sensitivity: "base" })
    )
    .forEach((groupValue) => {
      tableRows.push({
        key: `group-${fieldName}-${groupValue}`,
        type: "group",
        label: groupValue,
        colspan: 1
      });

      grouped.get(groupValue).forEach((row) => {
        tableRows.push({
          key: row.id,
          type: "data",
          row
        });
      });
    });

  return tableRows;
};

export const buildChartRows = (rows = []) => {
  const maxAum = Math.max(...(rows || []).map((row) => Number(row.totalAum) || 0), 1);

  return (rows || []).map((row) => {
    const aumValue = Number(row.totalAum) || 0;
    const widthPercent = Math.max(4, Math.round((aumValue / maxAum) * 100));

    return {
      key: row.id,
      label: row.accountName,
      valueLabel: row.totalAumLabel || formatCompactCurrency(aumValue),
      barStyle: `width: ${widthPercent}%`
    };
  });
};

const SEGMENT_CHART_COLORS = Object.freeze({
  "Ultra HNW": "#7f5af0",
  HNW: "#1b96ff",
  Affluent: "#f38303",
  "Mass Affluent": "#6b7280"
});

const SEGMENT_SORT_ORDER = Object.freeze([
  "Ultra HNW",
  "HNW",
  "Affluent",
  "Mass Affluent"
]);

const buildSegmentGroups = (rows = [], groupField = "wealthSegment") => {
  const groups = new Map();

  (rows || []).forEach((row) => {
    const segmentKey = row[groupField] || row.recordType || "Other";
    const current = groups.get(segmentKey) || {
      segmentKey,
      totalAum: 0,
      revenueT12: 0,
      count: 0
    };

    current.totalAum += Number(row.totalAum) || 0;
    current.revenueT12 += Number(row.revenueT12) || 0;
    current.count += 1;
    groups.set(segmentKey, current);
  });

  return groups;
};

const mapSegmentGroupsToChart = (groups) => {
  const totalAum = [...groups.values()].reduce((sum, group) => sum + group.totalAum, 0);

  const segments = [...groups.entries()]
    .sort(([firstKey], [secondKey]) => {
      const firstIndex = SEGMENT_SORT_ORDER.indexOf(firstKey);
      const secondIndex = SEGMENT_SORT_ORDER.indexOf(secondKey);
      const normalizedFirst = firstIndex === -1 ? Number.MAX_SAFE_INTEGER : firstIndex;
      const normalizedSecond = secondIndex === -1 ? Number.MAX_SAFE_INTEGER : secondIndex;
      return normalizedFirst - normalizedSecond;
    })
    .map(([segmentKey, group]) => {
      const percent = totalAum > 0 ? Math.round((group.totalAum / totalAum) * 100) : 0;

      return {
        key: segmentKey,
        label: segmentKey,
        value: group.totalAum,
        valueLabel: formatCompactCurrency(group.totalAum),
        percent,
        percentLabel: `${percent}%`,
        shareLabel: `${percent}% of total AUM`,
        revenueT12: group.revenueT12,
        revenueT12Label: formatCompactCurrency(group.revenueT12),
        count: group.count,
        countLabel: `${group.count} record${group.count === 1 ? "" : "s"}`,
        color: SEGMENT_CHART_COLORS[segmentKey] || "#6b7280",
        barStyle: `width: ${percent}%; background-color: ${SEGMENT_CHART_COLORS[segmentKey] || "#6b7280"}`
      };
    });

  return {
    segments,
    totalAum,
    totalAumLabel: formatCompactCurrency(totalAum)
  };
};

export const buildSegmentChartData = (rows = []) =>
  mapSegmentGroupsToChart(buildSegmentGroups(rows, "wealthSegment"));

export const buildRecordTypeChartData = (rows = []) =>
  mapSegmentGroupsToChart(buildSegmentGroups(rows, "recordType"));

export const buildChartSummary = (chartData, selectedSegmentKey) => {
  const segments = chartData?.segments || [];

  if (!segments.length) {
    return null;
  }

  const selectedSegment =
    segments.find((segment) => segment.key === selectedSegmentKey) || segments[0];

  const totalAum = chartData.totalAum || 0;
  const sharePercent =
    totalAum > 0 ? Math.round((selectedSegment.value / totalAum) * 100) : 0;

  return {
    key: selectedSegment.key,
    title: "FILTERED RESULT",
    valueLabel: selectedSegment.valueLabel,
    subtitle: `${selectedSegment.label} accounts · ${selectedSegment.countLabel}`,
    filterLabel: selectedSegment.label,
    sharePercentLabel: `${sharePercent}%`,
    shareLabel: "Share of AUM",
    revenueT12Label: selectedSegment.revenueT12Label,
    revenueLabel: "Revenue T12"
  };
};

export const buildFilterPills = (filters = {}) =>
  FILTER_FIELDS.flatMap((field) => {
    const values = filters?.[field.key] || [];

    if (!Array.isArray(values) || values.length === 0) {
      return [];
    }

    return values.map((value) => ({
      key: `${field.key}-${value}`,
      fieldKey: field.key,
      value,
      label: value
    }));
  });

export const resolveSelectedChartSegment = (chartData, selectedSegmentKey, filters = {}) => {
  const segments = chartData?.segments || [];

  if (!segments.length) {
    return null;
  }

  if (selectedSegmentKey && segments.some((segment) => segment.key === selectedSegmentKey)) {
    return selectedSegmentKey;
  }

  const recordTypeFilters = filters?.recordType || [];

  if (recordTypeFilters.length === 1) {
    const matchedSegment = segments.find((segment) => segment.key === recordTypeFilters[0]);
    if (matchedSegment) {
      return matchedSegment.key;
    }
  }

  return segments[0].key;
};

export const formatCompactCurrency = (value) => {
  const numericValue = Number(value) || 0;
  const absoluteValue = Math.abs(numericValue);

  if (absoluteValue >= 1000000) {
    return `$${(numericValue / 1000000).toFixed(2)}M`;
  }

  if (absoluteValue >= 1000) {
    return `$${Math.round(numericValue / 1000)}K`;
  }

  return `$${Math.round(numericValue)}`;
};

export const getCellDisplayValue = (row, column) => {
  if (!row || !column) {
    return "";
  }

  if (column.displayField && row[column.displayField]) {
    return row[column.displayField];
  }

  const value = row[column.fieldName] ?? row.extraFields?.[column.fieldName];
  if (column.type === "currency") {
    return formatCompactCurrency(value);
  }

  return value ?? "";
};

export const buildCsvContent = (rows = [], columns = DEFAULT_COLUMNS) => {
  const visibleColumns = getVisibleColumns(columns);
  const headerLine = visibleColumns.map((column) => escapeCsvValue(column.label)).join(",");
  const dataLines = (rows || []).map((row) =>
    visibleColumns
      .map((column) => escapeCsvValue(getCellDisplayValue(row, column)))
      .join(",")
  );

  return [headerLine, ...dataLines].join("\n");
};

export const downloadCsv = (filename, content) => {
  if (typeof document === "undefined") {
    return;
  }

  const blob = new Blob([content], { type: "text/csv;charset=utf-8;" });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  anchor.style.visibility = "hidden";
  document.body.appendChild(anchor);
  anchor.click();
  document.body.removeChild(anchor);
  URL.revokeObjectURL(url);
};

export const getSavedViewsStorageKey = (recordId, userId) =>
  `div-saved-views:${userId || "anonymous"}:${recordId || "global"}`;

export const loadSavedViews = (recordId, userId) =>
  loadSavedViewsPreference(recordId, userId).views;

export const loadSavedViewsPreference = (recordId, userId) => {
  if (typeof window === "undefined" || !window.localStorage) {
    return { views: [], lastSelectedViewId: "" };
  }

  try {
    const raw = window.localStorage.getItem(getSavedViewsStorageKey(recordId, userId));
    const parsed = raw ? JSON.parse(raw) : [];

    if (Array.isArray(parsed)) {
      return {
        views: expandSavedViewsFromStorage(parsed),
        lastSelectedViewId: ""
      };
    }

    if (parsed && Array.isArray(parsed.views)) {
      return {
        views: expandSavedViewsFromStorage(parsed.views),
        lastSelectedViewId: parsed.lastSelectedViewId || ""
      };
    }

    return { views: [], lastSelectedViewId: "" };
  } catch (error) {
    return { views: [], lastSelectedViewId: "" };
  }
};

export const persistSavedViews = (
  recordId,
  userId,
  views = [],
  lastSelectedViewId = ""
) => {
  if (typeof window === "undefined" || !window.localStorage) {
    return;
  }

  window.localStorage.setItem(
    getSavedViewsStorageKey(recordId, userId),
    JSON.stringify({
      views: compactSavedViewsForStorage(views),
      lastSelectedViewId: lastSelectedViewId || ""
    })
  );
};

export const createSavedView = (name, viewState) => ({
  id: `view-${Date.now()}`,
  name,
  createdAt: new Date().toISOString(),
  state: buildSavedViewState(viewState)
});

export const buildSavedViewState = (viewState = {}) => ({
  viewMode: viewState.viewMode,
  groupBy: viewState.groupBy,
  sortField: viewState.sortField,
  sortDirection: viewState.sortDirection,
  chartType: viewState.chartType || CHART_TYPE_PIE,
  columns: cloneColumns(viewState.columns),
  filters: { ...(viewState.filters || {}) }
});

export const updateSavedViewFromState = (savedView, viewState) => ({
  ...savedView,
  state: buildSavedViewState(viewState)
});

export const hasSavedViewStateChanged = (savedView, viewState) => {
  if (!savedView) {
    return false;
  }

  const savedSnapshot = JSON.stringify(
    compactViewStateForStorage(savedView.state || savedView.s || {})
  );
  const currentSnapshot = JSON.stringify(compactViewStateForStorage(viewState));

  return savedSnapshot !== currentSnapshot;
};

const DEFAULT_COLUMN_KEYS = DEFAULT_COLUMNS.map((column) => column.key);
const DEFAULT_COLUMN_BY_KEY = Object.fromEntries(
  DEFAULT_COLUMNS.map((column) => [column.key, column])
);

const isLegacyColumnState = (columns) =>
  Array.isArray(columns) &&
  columns.length > 0 &&
  typeof columns[0] === "object" &&
  columns[0].fieldName;

const compactFilters = (filters = {}) => {
  const compact = {};

  Object.entries(filters).forEach(([fieldKey, values]) => {
    if (Array.isArray(values) && values.length > 0) {
      compact[fieldKey] = values;
    }
  });

  return compact;
};

const expandFilters = (filters = {}) => ({
  ...createEmptyFilters(),
  ...filters
});

const expandCustomColumn = (entry = {}) => {
  const key = entry.k || entry.key;
  const column = {
    key,
    label: entry.l || entry.label || key,
    fieldName: key,
    type: entry.t || entry.type || "text",
    sortable: true,
    visible: true
  };

  if (entry.n || entry.numeric) {
    column.numeric = true;
  }

  if (entry.lk || entry.isLink) {
    column.isLink = true;
  }

  if (entry.d || entry.displayField) {
    column.displayField = entry.d || entry.displayField;
  }

  return column;
};

const serializeColumnsForStorage = (columns = []) => {
  const columnKeys = columns.map((column) => column.key);
  const hiddenKeys = columns
    .filter((column) => column.visible === false)
    .map((column) => column.key);
  const customColumns = columns.filter(
    (column) => !DEFAULT_COLUMN_BY_KEY[column.key]
  );

  const matchesDefaultLayout =
    customColumns.length === 0 &&
    columnKeys.length === DEFAULT_COLUMN_KEYS.length &&
    columnKeys.every((key, index) => key === DEFAULT_COLUMN_KEYS[index]) &&
    hiddenKeys.length === 0;

  if (matchesDefaultLayout) {
    return null;
  }

  const payload = { o: columnKeys };

  if (hiddenKeys.length > 0) {
    payload.h = hiddenKeys;
  }

  if (customColumns.length > 0) {
    payload.x = customColumns.map((column) => {
      const entry = { k: column.key };

      if (column.label && column.label !== column.key) {
        entry.l = column.label;
      }

      if (column.type && column.type !== "text") {
        entry.t = column.type;
      }

      if (column.numeric) {
        entry.n = 1;
      }

      if (column.isLink) {
        entry.lk = 1;
      }

      if (column.displayField) {
        entry.d = column.displayField;
      }

      return entry;
    });
  }

  return payload;
};

const deserializeColumnsFromStorage = (columns) => {
  if (!columns) {
    return cloneColumns(DEFAULT_COLUMNS);
  }

  if (isLegacyColumnState(columns)) {
    return cloneColumns(columns);
  }

  const order = columns.o || [];
  const hiddenKeys = new Set(columns.h || []);
  const customByKey = Object.fromEntries(
    (columns.x || []).map((entry) => {
      const expanded = expandCustomColumn(entry);
      return [expanded.key, expanded];
    })
  );

  if (order.length === 0) {
    return cloneColumns(DEFAULT_COLUMNS);
  }

  return order.map((key) => {
    const base = DEFAULT_COLUMN_BY_KEY[key] || customByKey[key] || expandCustomColumn({ k: key });
    return {
      ...base,
      visible: !hiddenKeys.has(key)
    };
  });
};

export const compactViewStateForStorage = (viewState = {}) => {
  const payload = {};

  if (viewState.viewMode && viewState.viewMode !== VIEW_MODE_TABLE) {
    payload.vm = viewState.viewMode;
  }

  if (viewState.groupBy && viewState.groupBy !== GROUP_BY_NONE) {
    payload.gb = viewState.groupBy;
  }

  if (viewState.sortField && viewState.sortField !== "accountName") {
    payload.sf = viewState.sortField;
  }

  if (viewState.sortDirection && viewState.sortDirection !== SORT_ASC) {
    payload.sd = viewState.sortDirection;
  }

  if (viewState.chartType && viewState.chartType !== CHART_TYPE_PIE) {
    payload.ct = viewState.chartType;
  }

  const columns = serializeColumnsForStorage(viewState.columns);

  if (columns) {
    payload.cols = columns;
  }

  const filters = compactFilters(viewState.filters);

  if (Object.keys(filters).length > 0) {
    payload.f = filters;
  }

  return payload;
};

export const expandViewStateFromStorage = (storedState = {}) => {
  if (!storedState || typeof storedState !== "object") {
    return createDefaultViewState();
  }

  if (storedState.viewMode || storedState.columns?.[0]?.fieldName) {
    return {
      viewMode: storedState.viewMode || VIEW_MODE_TABLE,
      groupBy: storedState.groupBy || GROUP_BY_NONE,
      sortField: storedState.sortField || "accountName",
      sortDirection: storedState.sortDirection || SORT_ASC,
      chartType: storedState.chartType || CHART_TYPE_PIE,
      columns: deserializeColumnsFromStorage(storedState.columns),
      filters: expandFilters(storedState.filters)
    };
  }

  return {
    viewMode: storedState.vm || VIEW_MODE_TABLE,
    groupBy: storedState.gb || GROUP_BY_NONE,
    sortField: storedState.sf || "accountName",
    sortDirection: storedState.sd || SORT_ASC,
    chartType: storedState.ct || CHART_TYPE_PIE,
    columns: deserializeColumnsFromStorage(storedState.cols),
    filters: expandFilters(storedState.f)
  };
};

export const compactSavedViewForStorage = (view = {}) => ({
  id: view.id,
  name: view.name,
  c: view.createdAt || view.c,
  s: compactViewStateForStorage(view.state || view.s)
});

export const expandSavedViewFromStorage = (view = {}) => ({
  id: view.id,
  name: view.name,
  createdAt: view.c || view.createdAt,
  state: expandViewStateFromStorage(view.s || view.state)
});

export const compactSavedViewsForStorage = (views = []) =>
  (views || []).map(compactSavedViewForStorage);

export const expandSavedViewsFromStorage = (views = []) =>
  (views || []).map(expandSavedViewFromStorage);

export const parseSavedViewsResponse = (viewsJson) => {
  if (!viewsJson) {
    return [];
  }

  try {
    const parsed = JSON.parse(viewsJson);
    return Array.isArray(parsed) ? expandSavedViewsFromStorage(parsed) : [];
  } catch (error) {
    return [];
  }
};

export const resolveSavedViewById = (savedViews = [], viewId = "") => {
  if (!viewId) {
    return null;
  }

  return (savedViews || []).find((view) => view.id === viewId) || null;
};

export const applySavedViewState = (savedView) => {
  if (!savedView?.state && !savedView?.s) {
    return createDefaultViewState();
  }

  return expandViewStateFromStorage(savedView.state || savedView.s);
};

export const buildColumnFromFieldOption = (fieldOption) => {
  const apiName = fieldOption.apiName;
  const fieldType = (fieldOption.type || "STRING").toUpperCase();
  const isNumeric =
    fieldType.includes("CURRENCY") ||
    fieldType.includes("DOUBLE") ||
    fieldType.includes("INTEGER") ||
    fieldType.includes("PERCENT");

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

export const deriveProcessedRows = ({
  sourceRows = [],
  filters = {},
  sortField = "accountName",
  sortDirection = SORT_ASC,
  columns = DEFAULT_COLUMNS,
  groupBy = GROUP_BY_NONE
} = {}) => {
  const filteredRows = applyFilters(sourceRows, filters);
  const sortedRows = applySort(filteredRows, sortField, sortDirection, columns);
  const tableRows = buildGroupedTableRows(sortedRows, groupBy);

  return {
    filteredRows: sortedRows,
    tableRows,
    chartRows: buildChartRows(sortedRows),
    chartData: buildSegmentChartData(sortedRows),
    filterPills: buildFilterPills(filters)
  };
};

export const resolveSortDirection = (fieldName, currentField, currentDirection = SORT_ASC) => {
  if (fieldName === currentField) {
    return currentDirection === SORT_ASC ? SORT_DESC : SORT_ASC;
  }

  return SORT_ASC;
};

export { SORT_ASC, SORT_DESC } from "c/dataTableSortUtils";

export const hasActiveFilters = (filters = {}) =>
  Object.values(filters || {}).some(
    (values) => Array.isArray(values) && values.length > 0
  );

const escapeCsvValue = (value) => {
  const stringValue = value === null || value === undefined ? "" : String(value);

  if (/[",\n]/.test(stringValue)) {
    return `"${stringValue.replace(/"/g, '""')}"`;
  }

  return stringValue;
};