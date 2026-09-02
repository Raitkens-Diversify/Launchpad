/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-16
 *
 * Shared constants and helpers for Notification Center LWCs.
 * Values align with NotificationConstants.cls where applicable.
 */

export const FREQUENCY = Object.freeze({
  IMMEDIATE: "Immediate",
  DIGEST: "Digest"
});

export const DIGEST_FREQUENCY = Object.freeze({
  DAILY: "Daily",
  WEEKLY: "Weekly",
  HOURLY: "Hourly"
});

export const DIGEST_FREQUENCY_OPTIONS = Object.freeze([
  { label: DIGEST_FREQUENCY.HOURLY, value: DIGEST_FREQUENCY.HOURLY },
  { label: DIGEST_FREQUENCY.DAILY, value: DIGEST_FREQUENCY.DAILY },
  { label: DIGEST_FREQUENCY.WEEKLY, value: DIGEST_FREQUENCY.WEEKLY }
]);

const formatDigestFrequencyHourLabel = (hourValue) => {
  const hour = Number(hourValue);

  if (Number.isNaN(hour)) {
    return hourValue;
  }

  if (hour === 0) {
    return "12:00 AM";
  }

  if (hour < 12) {
    return `${hour}:00 AM`;
  }

  if (hour === 12) {
    return "12:00 PM";
  }

  return `${hour - 12}:00 PM`;
};

export const BUSINESS_HOUR_START = 6;
export const BUSINESS_HOUR_END = 18;

/** Aligns with NotificationConstants.DISPLAY_NOT_APPLICABLE */
export const DISPLAY_NOT_APPLICABLE = "(n/a)";

export const formatDisplayValue = (value) => {
  if (value === null || value === undefined || value === "") {
    return DISPLAY_NOT_APPLICABLE;
  }

  if (typeof value === "boolean") {
    return value ? "true" : "false";
  }

  if (typeof value === "object") {
    return JSON.stringify(value);
  }

  return String(value);
};

const buildHourOption = (hour) => ({
  label: formatDigestFrequencyHourLabel(hour),
  value: String(hour)
});

export const DIGEST_FREQUENCY_HOUR_OPTIONS = Object.freeze(
  Array.from(
    { length: BUSINESS_HOUR_END - BUSINESS_HOUR_START + 1 },
    (_, index) => buildHourOption(BUSINESS_HOUR_START + index)
  )
);

export const buildDigestFrequencyHourOptions = (includeHour = null) => {
  const hourValues = new Set(
    DIGEST_FREQUENCY_HOUR_OPTIONS.map((option) => option.value)
  );

  if (includeHour !== null && includeHour !== undefined && includeHour !== "") {
    hourValues.add(String(includeHour));
  }

  return Array.from(hourValues)
    .map((value) => Number(value))
    .sort((left, right) => left - right)
    .map((hour) => buildHourOption(hour));
};

export const CATEGORY = Object.freeze({
  URGENT: "Urgent",
  SERVICE: "Service",
  INFO: "Info"
});

export const OBJECT_TYPE = Object.freeze({
  CASE: "Case",
  TASK: "Task",
  EVENT: "Event"
});

export const CHANNEL = Object.freeze({
  IN_APP: "In_App",
  EMAIL: "Email",
  SMS: "SMS"
});

export const STATUS = Object.freeze({
  SENT: "Sent",
  SUPPRESSED: "Suppressed",
  QUEUED: "Queued",
  PENDING: "Pending",
  FAILED: "Failed"
});

export const LOG_STATUS_FILTER = Object.freeze({
  ALL: "ALL",
  DELIVERED: "DELIVERED",
  SUPPRESSED: "SUPPRESSED",
  QUEUED: "QUEUED",
  PENDING: "PENDING",
  FAILED: "FAILED"
});

export const LOG_CATEGORY_FILTER = Object.freeze({
  ALL: "ALL",
  URGENT: "URGENT",
  SERVICE: "SERVICE",
  INFO: "INFO"
});

export const ICON = Object.freeze({
  ADD: "utility:add",
  APPS: "utility:apps",
  BAN: "utility:ban",
  BUG: "utility:bug",
  FALLBACK: "utility:fallback",
  CASE: "standard:case",
  CHEVRON_DOWN: "utility:chevrondown",
  CHECK: "utility:check",
  CLOCK: "utility:clock",
  CLOSE: "utility:close",
  COPY: "utility:copy",
  DATE_TIME: "utility:date_time",
  DELETE: "utility:delete",
  DOWNLOAD: "utility:download",
  EDIT: "utility:edit",
  EMAIL: "utility:email",
  EVENT: "standard:event",
  FILE: "utility:file",
  FILTER_LIST: "utility:filterList",
  GROUPS: "utility:groups",
  HOME: "utility:home",
  INFO: "utility:info",
  LOCK: "utility:lock",
  NOTIFICATION: "utility:notification",
  SAVE: "utility:save",
  SETTINGS: "utility:settings",
  SHIELD: "utility:shield",
  SMS: "utility:sms",
  SUCCESS: "utility:success",
  TASK: "standard:task",
  VIDEO: "utility:video"
});

export const MODE_ICON = Object.freeze({
  IMMEDIATE: ICON.FALLBACK,
  DIGEST: ICON.CLOCK
});

export const NAV_VIEW_ICONS = Object.freeze({
  dashboard: ICON.APPS,
  "notification-rules": ICON.NOTIFICATION,
  "channel-preferences": ICON.SETTINGS,
  "schedules-quiet-hours": ICON.DATE_TIME,
  "notification-log": ICON.FILE,
  "fa-team-households": ICON.GROUPS,
  "admin-settings": ICON.SETTINGS,
  "admin-log": ICON.FILTER_LIST,
  debug: ICON.BUG
});

export const LOG_SUMMARY_ICONS = Object.freeze({
  DELIVERED: ICON.SUCCESS,
  SUPPRESSED: ICON.BAN,
  QUEUED: ICON.CLOCK,
  PENDING: ICON.CLOCK,
  FAILED: ICON.CLOSE
});

export const METRIC_ICON_WRAP = Object.freeze({
  GREEN: "div-metric-icon div-metric-icon--green",
  ORANGE: "div-metric-icon div-metric-icon--orange",
  BLUE: "div-metric-icon div-metric-icon--blue",
  PURPLE: "div-metric-icon div-metric-icon--purple"
});

export const LOG_SUMMARY_ICON_WRAP = Object.freeze({
  DELIVERED: METRIC_ICON_WRAP.GREEN,
  SUPPRESSED: METRIC_ICON_WRAP.ORANGE,
  QUEUED: METRIC_ICON_WRAP.BLUE,
  PENDING: METRIC_ICON_WRAP.PURPLE,
  FAILED: METRIC_ICON_WRAP.ORANGE
});

export const DASHBOARD_KPI_ICON_WRAP = Object.freeze({
  DELIVERED_TODAY: METRIC_ICON_WRAP.GREEN,
  SUPPRESSED_TODAY: METRIC_ICON_WRAP.ORANGE,
  QUEUED_DIGEST: METRIC_ICON_WRAP.BLUE,
  ACTIVE_HOUSEHOLDS: METRIC_ICON_WRAP.PURPLE
});

export const DASHBOARD_KPI_ICONS = Object.freeze({
  DELIVERED_TODAY: ICON.SUCCESS,
  SUPPRESSED_TODAY: ICON.CLOSE,
  QUEUED_DIGEST: ICON.CLOCK,
  ACTIVE_HOUSEHOLDS: ICON.HOME
});

export const CATEGORY_OPTIONS = Object.freeze([
  { label: CATEGORY.URGENT, value: CATEGORY.URGENT },
  { label: CATEGORY.SERVICE, value: CATEGORY.SERVICE },
  { label: CATEGORY.INFO, value: CATEGORY.INFO }
]);

export const OBJECT_TYPE_OPTIONS = Object.freeze([
  { label: OBJECT_TYPE.CASE, value: OBJECT_TYPE.CASE },
  { label: OBJECT_TYPE.TASK, value: OBJECT_TYPE.TASK },
  { label: OBJECT_TYPE.EVENT, value: OBJECT_TYPE.EVENT }
]);

export const FREQUENCY_OPTIONS = Object.freeze([
  { label: FREQUENCY.IMMEDIATE, value: FREQUENCY.IMMEDIATE },
  { label: "Email Digest", value: FREQUENCY.DIGEST }
]);

export const CATEGORY_FILTER_OPTIONS = Object.freeze([
  { label: "All", value: "ALL" },
  { label: CATEGORY.URGENT, value: CATEGORY.URGENT },
  { label: CATEGORY.SERVICE, value: CATEGORY.SERVICE },
  { label: CATEGORY.INFO, value: CATEGORY.INFO }
]);

export const LOG_CATEGORY_FILTER_OPTIONS = Object.freeze([
  { label: "All Categories", value: LOG_CATEGORY_FILTER.ALL },
  { label: CATEGORY.URGENT, value: LOG_CATEGORY_FILTER.URGENT },
  { label: CATEGORY.SERVICE, value: LOG_CATEGORY_FILTER.SERVICE },
  { label: CATEGORY.INFO, value: LOG_CATEGORY_FILTER.INFO }
]);

export const STATUS_FILTER_OPTIONS = Object.freeze([
  { label: "All", value: LOG_STATUS_FILTER.ALL },
  { label: "Delivered", value: LOG_STATUS_FILTER.DELIVERED },
  { label: "Pending", value: LOG_STATUS_FILTER.PENDING },
  { label: "Failed", value: LOG_STATUS_FILTER.FAILED },
  { label: "Queued", value: LOG_STATUS_FILTER.QUEUED }
]);

export const LOG_BRANCH_FILTER = Object.freeze({
  ALL: "ALL",
  DAS: "DAS",
  DWM: "DWM"
});

export const LOG_BRANCH_FILTER_OPTIONS = Object.freeze([
  { label: "All Branches", value: LOG_BRANCH_FILTER.ALL },
  { label: "DAS", value: LOG_BRANCH_FILTER.DAS },
  { label: "DWM", value: LOG_BRANCH_FILTER.DWM }
]);

export const LOG_RECORD_TYPE_FILTER_OPTIONS = Object.freeze([
  { label: "All", value: "ALL" },
  { label: OBJECT_TYPE.CASE, value: OBJECT_TYPE.CASE },
  { label: OBJECT_TYPE.TASK, value: OBJECT_TYPE.TASK },
  { label: OBJECT_TYPE.EVENT, value: OBJECT_TYPE.EVENT }
]);

export const CATEGORY_CARD_META = Object.freeze({
  [CATEGORY.URGENT]: { footnote: "Overrides quiet hours" },
  [CATEGORY.SERVICE]: { footnote: null },
  [CATEGORY.INFO]: { footnote: "Digest-only recommended" }
});

export const DEFAULT_RULE_FORM = Object.freeze({
  id: null,
  ruleName: "",
  category: CATEGORY.SERVICE,
  objectType: OBJECT_TYPE.CASE,
  frequency: FREQUENCY.IMMEDIATE,
  digestFrequency: DIGEST_FREQUENCY.DAILY,
  digestFrequencyHour: null,
  channels: [CHANNEL.IN_APP],
  isActive: true,
  householdId: null,
  clonedFromSystemDefaultId: null
});

export const buildDefaultRuleName = (objectType, frequency) =>
  `${objectType || OBJECT_TYPE.CASE} ${frequency || FREQUENCY.IMMEDIATE}`;

export const HOUSEHOLD_RECORD_TYPE_DEVELOPER_NAMES = Object.freeze([
  "Household",
  "IndustriesHousehold"
]);

export const isHouseholdRecordType = (recordTypeDeveloperName) => {
  const developerName = String(recordTypeDeveloperName || "").trim();

  if (!developerName) {
    return false;
  }

  if (HOUSEHOLD_RECORD_TYPE_DEVELOPER_NAMES.includes(developerName)) {
    return true;
  }

  return developerName.toLowerCase().includes("household");
};

export const HOUSEHOLD_MATCHING_INFO = Object.freeze({
  primaryField: { fieldPath: "Name" }
});

export const resolveHouseholdRecordTypeIds = (recordTypeInfos = {}) =>
  Object.entries(recordTypeInfos)
    .filter(([, info]) => isHouseholdRecordType(info?.name || info?.developerName))
    .map(([recordTypeId]) => recordTypeId);

export const buildHouseholdFilter = (recordTypeIds = []) => {
  const availableRecordTypeIds = (recordTypeIds || []).filter(Boolean);

  if (!availableRecordTypeIds.length) {
    return undefined;
  }

  return {
    criteria: [
      {
        fieldPath: "RecordTypeId",
        operator: "in",
        value: availableRecordTypeIds
      }
    ]
  };
};

const CHANNEL_CONFIG = Object.freeze({
  [CHANNEL.IN_APP]: {
    badgeLabel: "APP",
    icon: ICON.NOTIFICATION,
    iconWrapClass: "div-channel-icon div-channel-icon--in-app",
    badgeClass: "div-channel-badge div-channel-badge--in-app",
    deliveryIconClass: "div-channel-icon div-channel-icon--in-app",
    deliveryBarClass: "delivery-row__bar-fill delivery-row__bar-fill--in-app"
  },
  [CHANNEL.EMAIL]: {
    badgeLabel: "EMAIL",
    icon: ICON.EMAIL,
    iconWrapClass: "div-channel-icon div-channel-icon--email",
    badgeClass: "div-channel-badge div-channel-badge--email",
    deliveryIconClass: "div-channel-icon div-channel-icon--email",
    deliveryBarClass: "delivery-row__bar-fill delivery-row__bar-fill--email"
  },
  [CHANNEL.SMS]: {
    badgeLabel: "SMS",
    icon: ICON.SMS,
    iconWrapClass: "div-channel-icon div-channel-icon--sms",
    badgeClass: "div-channel-badge div-channel-badge--sms",
    deliveryIconClass: null,
    deliveryBarClass: null
  }
});

const CATEGORY_DOT_CLASSES = Object.freeze({
  [CATEGORY.URGENT]: "div-category-dot div-category-dot--urgent",
  [CATEGORY.SERVICE]: "div-category-dot div-category-dot--service",
  [CATEGORY.INFO]: "div-category-dot div-category-dot--info"
});

const CATEGORY_BADGE_CLASSES = Object.freeze({
  [CATEGORY.URGENT]: "category-badge category-badge--urgent",
  [CATEGORY.SERVICE]: "category-badge category-badge--service",
  [CATEGORY.INFO]: "category-badge category-badge--info"
});

const SOURCE_ICONS = Object.freeze({
  [OBJECT_TYPE.CASE]: ICON.CASE,
  [OBJECT_TYPE.TASK]: ICON.TASK,
  [OBJECT_TYPE.EVENT]: ICON.EVENT
});

const SOURCE_ICON_WRAP_CLASSES = Object.freeze({
  [OBJECT_TYPE.CASE]: "div-source-icon div-source-icon--case",
  [OBJECT_TYPE.TASK]: "div-source-icon div-source-icon--task",
  [OBJECT_TYPE.EVENT]: "div-source-icon div-source-icon--event"
});

const LOG_STATUS_STYLES = Object.freeze({
  [STATUS.SENT]: {
    label: "Delivered",
    cssClass: "div-status-pill div-status-pill--delivered",
    icon: ICON.SUCCESS,
    iconClass: "div-log-status__icon div-log-status__icon--delivered"
  },
  [STATUS.SUPPRESSED]: {
    label: "Suppressed",
    cssClass: "div-status-pill div-status-pill--suppressed",
    icon: ICON.BAN,
    iconClass: "div-log-status__icon div-log-status__icon--suppressed"
  },
  [STATUS.QUEUED]: {
    label: "Queued",
    cssClass: "div-status-pill div-status-pill--queued",
    icon: MODE_ICON.DIGEST,
    iconClass: "div-log-status__icon div-log-status__icon--queued"
  },
  [STATUS.PENDING]: {
    label: "Pending",
    cssClass: "div-status-pill div-status-pill--pending",
    icon: ICON.CLOCK,
    iconClass: "div-log-status__icon div-log-status__icon--pending"
  },
  [STATUS.FAILED]: {
    label: "Failed",
    cssClass: "div-status-pill div-status-pill--failed",
    icon: ICON.CLOSE,
    iconClass: "div-log-status__icon div-log-status__icon--failed"
  }
});

const DASHBOARD_STATUS_STYLES = Object.freeze({
  [STATUS.SENT]: {
    icon: ICON.SUCCESS,
    iconClass: "activity-row__status-icon activity-row__status-icon--delivered"
  },
  [STATUS.SUPPRESSED]: {
    icon: ICON.CLOSE,
    iconClass: "activity-row__status-icon activity-row__status-icon--suppressed"
  },
  [STATUS.QUEUED]: {
    icon: MODE_ICON.DIGEST,
    iconClass: "activity-row__status-icon activity-row__status-icon--queued"
  }
});

const getChannelConfig = (channel) =>
  CHANNEL_CONFIG[channel] || CHANNEL_CONFIG[CHANNEL.IN_APP];

export const isDigestFrequency = (frequency) => frequency === FREQUENCY.DIGEST;

const normalizeDigestFrequencyHour = (digestFrequency, digestFrequencyHour) => {
  if (!isDailyDigestFrequency(digestFrequency)) {
    return "";
  }

  if (
    digestFrequencyHour === null ||
    digestFrequencyHour === undefined ||
    digestFrequencyHour === ""
  ) {
    return "";
  }

  return String(digestFrequencyHour);
};

export const buildRuleDuplicateKey = (rule) => {
  const objectType = rule?.objectType || "";
  const category = rule?.category || "";
  const frequency = rule?.frequency || FREQUENCY.IMMEDIATE;

  if (!isDigestFrequency(frequency)) {
    return [objectType, category, frequency].join("|");
  }

  const digestFrequency = rule?.digestFrequency || DIGEST_FREQUENCY.DAILY;
  const digestFrequencyHour = normalizeDigestFrequencyHour(
    digestFrequency,
    rule?.digestFrequencyHour
  );

  return [objectType, category, frequency, digestFrequency, digestFrequencyHour].join(
    "|"
  );
};

export const isSameHouseholdScope = (leftHouseholdId, rightHouseholdId) =>
  (leftHouseholdId || null) === (rightHouseholdId || null);

export const normalizeSearchTerm = (value) => (value || "").trim().toLowerCase();

export const matchesRuleSearch = (rule, searchTerm) => {
  const term = normalizeSearchTerm(searchTerm);

  if (!term) {
    return true;
  }

  const candidates = [rule?.name, rule?.ruleName, rule?.householdName]
    .filter(Boolean)
    .map((value) => String(value).toLowerCase());

  return candidates.some((value) => value.includes(term));
};

export const findDuplicateRules = (existingRules, candidate, options = {}) => {
  const { excludeRuleId, excludeSystemDefaults = true } = options;
  const candidateKey = buildRuleDuplicateKey(candidate);
  const candidateHouseholdId = candidate?.householdId || null;

  return (existingRules || []).filter((rule) => {
    if (excludeRuleId && rule.id === excludeRuleId) {
      return false;
    }

    if (excludeSystemDefaults && rule.isSystemDefault === true) {
      return false;
    }

    if (!isSameHouseholdScope(candidateHouseholdId, rule.householdId)) {
      return false;
    }

    return buildRuleDuplicateKey(rule) === candidateKey;
  });
};

export const DUPLICATE_RULE_CONFIRM = Object.freeze({
  title: "Similar rule found",
  message:
    "A rule with these settings already exists. You can still save if you intend to create another one.",
  listLabel: "Existing rules",
  confirmLabel: "Save anyway",
  cancelLabel: "Cancel"
});

export const getDuplicateRuleNames = (rules) =>
  [...new Set((rules || []).map((rule) => rule?.name).filter(Boolean))];

export const getDigestFrequencyDisplayLabel = (
  digestFrequency,
  digestFrequencyHour = null
) => {
  if (!digestFrequency) {
    return "";
  }

  if (isDailyDigestFrequency(digestFrequency)) {
    if (
      digestFrequencyHour !== null &&
      digestFrequencyHour !== undefined &&
      digestFrequencyHour !== ""
    ) {
      return `${digestFrequency} · ${formatDigestFrequencyHourLabel(digestFrequencyHour)}`;
    }

    return digestFrequency;
  }

  return digestFrequency;
};

export const isDailyDigestFrequency = (digestFrequency) =>
  digestFrequency === DIGEST_FREQUENCY.DAILY;

export const isHourlyDigestFrequency = (digestFrequency) =>
  digestFrequency === DIGEST_FREQUENCY.HOURLY;

export const resolveImmediateDefaultChannels = () => [CHANNEL.IN_APP];

export const resolveDigestDefaultChannels = () => [CHANNEL.EMAIL];

export const sanitizeChannelsForDeliveryMode = (frequency, channels) => {
  if (isDigestFrequency(frequency)) {
    return resolveDigestDefaultChannels();
  }

  const selectedChannels = (channels || []).filter(Boolean);

  if (selectedChannels.length === 0) {
    return resolveImmediateDefaultChannels();
  }

  return selectedChannels;
};

export const isChannelSelectableForDeliveryMode = (frequency, channel) => {
  if (isDigestFrequency(frequency)) {
    return channel === CHANNEL.EMAIL;
  }

  return Boolean(channel);
};

export const getFrequencyLabel = (frequency) =>
  frequency || FREQUENCY.IMMEDIATE;

export const getModeLabelClass = (frequency) =>
  isDigestFrequency(frequency)
    ? "div-mode-label div-mode-label--digest"
    : "div-mode-label div-mode-label--immediate";

export const getModeIcon = (frequency) =>
  isDigestFrequency(frequency) ? MODE_ICON.DIGEST : MODE_ICON.IMMEDIATE;

export const getModeIconClass = (frequency) =>
  isDigestFrequency(frequency)
    ? "div-mode-label__icon div-mode-label__icon--digest"
    : "div-mode-label__icon div-mode-label__icon--immediate";

export const getCategoryDotClass = (category, size = "md") => {
  const baseClass =
    CATEGORY_DOT_CLASSES[category] || CATEGORY_DOT_CLASSES[CATEGORY.INFO];

  return size === "sm" ? `${baseClass} div-category-dot--sm` : baseClass;
};

export const getCategoryBadgeClass = (category) =>
  CATEGORY_BADGE_CLASSES[category] || CATEGORY_BADGE_CLASSES[CATEGORY.INFO];

export const getCategoryLabel = (category) => category || CATEGORY.INFO;

export const getChannelBadge = (channel) => {
  const config = getChannelConfig(channel);

  return {
    label: config.badgeLabel,
    cssClass: config.badgeClass
  };
};

export const getChannelIcon = (channel) => getChannelConfig(channel).icon;

export const getChannelIconWrapClass = (channel, isSelected = true) => {
  const config = getChannelConfig(channel);
  const baseClass = config.iconWrapClass || "div-channel-icon div-channel-icon--in-app";

  return isSelected ? baseClass : `${baseClass} div-channel-icon--muted`;
};

export const getOptionSelectedClass = (isSelected) =>
  isSelected ? "div-option--selected" : "";

export const buildDivFilterOptionClass = (isActive) => {
  const classes = ["div-filter__option"];

  if (isActive) {
    classes.push("div-option--selected");
  }

  return classes.join(" ");
};

export const getSelectTileClass = (isSelected, isDisabled = false) => {
  const classes = ["div-select-tile"];

  if (isSelected) {
    classes.push("div-option--selected");
  }

  if (isDisabled) {
    classes.push("div-select-tile--disabled");
  }

  return classes.join(" ");
};

export const CHANNEL_ORDER = Object.freeze([
  CHANNEL.IN_APP,
  CHANNEL.EMAIL,
  CHANNEL.SMS
]);

const getChannelSortIndex = (channel) => {
  const index = CHANNEL_ORDER.indexOf(channel);

  return index === -1 ? CHANNEL_ORDER.length : index;
};

/** @deprecated Use CHANNEL_ORDER */
export const MODAL_CHANNEL_ORDER = CHANNEL_ORDER;

export const getChannelDisplayLabel = (channel) => {
  const labels = {
    [CHANNEL.EMAIL]: "Email",
    [CHANNEL.SMS]: "SMS",
    [CHANNEL.IN_APP]: "In App"
  };

  return labels[channel] || channel;
};

export const sortChannelOptions = (options) =>
  [...options].sort(
    (left, right) =>
      getChannelSortIndex(left.value) - getChannelSortIndex(right.value)
  );

export const getDeliveryBarStyle = (channel) => {
  const config = getChannelConfig(channel);

  if (!config.deliveryIconClass) {
    return null;
  }

  return {
    icon: config.icon,
    iconClass: config.deliveryIconClass,
    barClass: config.deliveryBarClass
  };
};

export const getLogStatusStyle = (status) =>
  LOG_STATUS_STYLES[status] || LOG_STATUS_STYLES[STATUS.SENT];

export const getDashboardStatusStyle = (status) =>
  DASHBOARD_STATUS_STYLES[status] || DASHBOARD_STATUS_STYLES[STATUS.SENT];

export const getSourceIcon = (sourceType) =>
  SOURCE_ICONS[sourceType] || ICON.NOTIFICATION;

export const getSourceIconWrapClass = (sourceType) =>
  SOURCE_ICON_WRAP_CLASSES[sourceType] || "div-source-icon";

export const buildSourceTypeDisplay = (sourceType) => ({
  label: sourceType || "Record",
  icon: getSourceIcon(sourceType),
  iconClass: getSourceIconWrapClass(sourceType)
});

const TRIGGER_TYPE_LABELS = Object.freeze({
  insert: "Created",
  create: "Created",
  created: "Created",
  update: "Updated",
  updated: "Updated",
  delete: "Deleted",
  deleted: "Deleted"
});

const parseChangeContextJson = (changeContextJson) => {
  if (!changeContextJson?.trim()) {
    return null;
  }

  try {
    return JSON.parse(changeContextJson);
  } catch {
    return null;
  }
};

export const deriveChangeTypeFromTriggerType = (triggerType) => {
  const normalizedTriggerType = String(triggerType || "")
    .trim()
    .toLowerCase();

  return TRIGGER_TYPE_LABELS[normalizedTriggerType] || null;
};

export const deriveChangeType = (title, changeContextJson) => {
  const changeContext = parseChangeContextJson(changeContextJson);
  const changeTypeFromContext = deriveChangeTypeFromTriggerType(
    changeContext?.triggerType
  );

  if (changeTypeFromContext) {
    return changeTypeFromContext;
  }

  const normalizedTitle = (title || "").toLowerCase();

  if (normalizedTitle.includes("closed")) {
    return "Closed";
  }

  if (normalizedTitle.includes("updated")) {
    return "Updated";
  }

  if (normalizedTitle.includes("deleted")) {
    return "Deleted";
  }

  if (normalizedTitle.includes("created")) {
    return "Created";
  }

  return "Created";
};

export const parseSalesforceDatetime = (value) => {
  if (value === null || value === undefined || value === "") {
    return null;
  }

  if (typeof value === "number") {
    return Number.isNaN(value) ? null : value;
  }

  let normalized = String(value).trim().replace(/\+0000$/, "Z");

  if (!/[zZ]$|[+-]\d{2}:?\d{2}$/.test(normalized)) {
    normalized = normalized.includes("T")
      ? `${normalized}Z`
      : `${normalized.replace(" ", "T")}Z`;
  }

  const timestamp = Date.parse(normalized);
  return Number.isNaN(timestamp) ? null : timestamp;
};

const buildLocalDayKeyFromTimestamp = (timestamp) => {
  if (timestamp === null || timestamp === undefined) {
    return "unknown";
  }

  const eventDate = new Date(timestamp);
  const year = eventDate.getFullYear();
  const month = String(eventDate.getMonth() + 1).padStart(2, "0");
  const day = String(eventDate.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
};

const formatLogDayKey = (value) => {
  const timestamp = parseSalesforceDatetime(value);
  return buildLocalDayKeyFromTimestamp(timestamp);
};

export const formatLogDayLabelFromTimestamp = (timestamp) => {
  if (timestamp === null || timestamp === undefined) {
    return "Unknown date";
  }

  const eventDate = new Date(timestamp);
  const now = new Date();
  const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const startOfEventDay = new Date(
    eventDate.getFullYear(),
    eventDate.getMonth(),
    eventDate.getDate()
  );
  const dayDiff = Math.round(
    (startOfToday.getTime() - startOfEventDay.getTime()) / 86400000
  );

  if (dayDiff === 0) {
    return "Today";
  }

  if (dayDiff === 1) {
    return "Yesterday";
  }

  return eventDate.toLocaleDateString([], {
    weekday: "long",
    month: "long",
    day: "numeric",
    year: "numeric"
  });
};

export const formatLogDayLabel = (value) => {
  if (!value) {
    return "Unknown date";
  }

  const timestamp = parseSalesforceDatetime(value);

  if (timestamp === null) {
    return "Unknown date";
  }

  return formatLogDayLabelFromTimestamp(timestamp);
};

export const groupLogRowsByDay = (rows) => {
  const groupsByDay = new Map();

  rows.forEach((row) => {
    const dayKey = row.changeDayKey || "unknown";

    if (!groupsByDay.has(dayKey)) {
      groupsByDay.set(dayKey, {
        id: dayKey,
        dayKey,
        dayLabel:
          row.changeDayLabel ||
          formatLogDayLabelFromTimestamp(row.changeTimestamp) ||
          "Unknown date",
        rows: []
      });
    }

    groupsByDay.get(dayKey).rows.push(row);
  });

  return Array.from(groupsByDay.values()).sort((left, right) =>
    left.dayKey.localeCompare(right.dayKey)
  );
};

const AGGREGATED_STATUS_PRIORITY = Object.freeze([
  STATUS.FAILED,
  STATUS.SUPPRESSED,
  STATUS.QUEUED,
  STATUS.PENDING,
  STATUS.SENT
]);

export const buildRecentEventGroupKey = (item) =>
  [
    item?.sourceRecordId || item?.id || "",
    item?.title || "",
    item?.category || "",
    item?.frequency || "",
    item?.householdId || item?.householdName || "",
    item?.recipientId || ""
  ].join("|");

export const sortChannels = (channels) =>
  [...new Set((channels || []).filter(Boolean))].sort(
    (left, right) => getChannelSortIndex(left) - getChannelSortIndex(right)
  );

export const buildChannelPills = (channels) =>
  sortChannels(channels).map((channel) => {
    const badge = getChannelBadge(channel);

    return {
      id: channel,
      label: badge.label,
      cssClass: badge.cssClass
    };
  });

export const deriveAggregatedStatus = (items) => {
  const statuses = new Set((items || []).map((item) => item?.status).filter(Boolean));

  const resolvedStatus =
    AGGREGATED_STATUS_PRIORITY.find((status) => statuses.has(status)) || STATUS.SENT;

  return resolvedStatus;
};

export const groupRecentEvents = (events) => {
  const groups = [];
  const groupIndexByKey = new Map();

  (events || []).forEach((event) => {
    const groupKey = buildRecentEventGroupKey(event);
    const existingIndex = groupIndexByKey.get(groupKey);

    if (existingIndex === undefined) {
      groupIndexByKey.set(groupKey, groups.length);
      groups.push({
        ...event,
        id: groupKey,
        channels: event?.channel ? [event.channel] : [],
        channelItems: [event]
      });
      return;
    }

    const group = groups[existingIndex];

    if (event?.channel && !group.channels.includes(event.channel)) {
      group.channels.push(event.channel);
    }

    group.channelItems.push(event);
    group.channels = sortChannels(group.channels);

    const nextEventAt = event?.eventAt ? new Date(event.eventAt).getTime() : 0;
    const currentEventAt = group.eventAt ? new Date(group.eventAt).getTime() : 0;

    if (nextEventAt > currentEventAt) {
      group.eventAt = event.eventAt;
    }
  });

  return groups;
};

export const formatRelativeTime = (value) => {
  if (!value) {
    return "";
  }

  const eventDate = new Date(value);
  const diffMs = Date.now() - eventDate.getTime();
  const diffMinutes = Math.floor(diffMs / 60000);

  if (diffMinutes < 1) {
    return "just now";
  }

  if (diffMinutes < 60) {
    return `${diffMinutes} min ago`;
  }

  const diffHours = diffMs / 3600000;

  if (diffHours < 24) {
    const roundedHours = Math.round(diffHours * 10) / 10;
    return roundedHours === 1 ? "1 hr ago" : `${roundedHours} hrs ago`;
  }

  const diffDays = Math.floor(diffHours / 24);
  return diffDays === 1 ? "1 day ago" : `${diffDays} days ago`;
};

export const reduceError = (error) => {
  if (Array.isArray(error?.body)) {
    return error.body.map((entry) => entry.message).join(", ");
  }

  return error?.body?.message || error?.message || "Unknown error";
};

export const dispatchNotificationCenterViewReady = (component) => {
  component.dispatchEvent(
    new CustomEvent("notificationcenterviewready", {
      bubbles: true,
      composed: true
    })
  );
};