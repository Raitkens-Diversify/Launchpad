/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-28
 *
 * Shared activity type definitions for Activity Timeline and related LWCs.
 */
export const ACTIVITY_CATEGORIES = Object.freeze({
  WORK: "Work",
  INTERACTIONS: "Interactions"
});

export const CATEGORY_ORDER = Object.freeze([
  ACTIVITY_CATEGORIES.WORK,
  ACTIVITY_CATEGORIES.INTERACTIONS
]);

export const CATEGORY_CONFIG = Object.freeze({
  [ACTIVITY_CATEGORIES.WORK]: {
    label: ACTIVITY_CATEGORIES.WORK,
    statLabel: ACTIVITY_CATEGORIES.WORK,
    icon: "utility:workforce_engagement",
    iconClass: "filter-pill__icon",
    pillClass: "filter-pill filter-pill--work",
    dotClass: "timeline-dot timeline-dot--work"
  },
  [ACTIVITY_CATEGORIES.INTERACTIONS]: {
    label: ACTIVITY_CATEGORIES.INTERACTIONS,
    statLabel: ACTIVITY_CATEGORIES.INTERACTIONS,
    icon: "utility:chat",
    iconClass: "filter-pill__icon",
    pillClass: "filter-pill filter-pill--interactions",
    dotClass: "timeline-dot timeline-dot--interactions"
  }
});

export const ACTIVITY_TYPES = Object.freeze({
  CASE: Object.freeze({
    key: "Case",
    label: "Case",
    category: ACTIVITY_CATEGORIES.WORK,
    icon: "standard:case",
    badgeKey: "case",
    recordObjectApiName: "Case",
    summaryText: Object.freeze({
      default: "has a case"
    })
  }),
  TASK: Object.freeze({
    key: "Task",
    label: "Task",
    category: ACTIVITY_CATEGORIES.WORK,
    icon: "standard:task",
    badgeKey: "task",
    recordObjectApiName: "Task",
    summaryText: Object.freeze({
      upcoming: "has an upcoming task",
      default: "has a task"
    })
  }),
  MEETING: Object.freeze({
    key: "Meeting",
    label: "Meeting",
    category: ACTIVITY_CATEGORIES.INTERACTIONS,
    icon: "standard:event",
    badgeKey: "meeting",
    recordObjectApiName: "Event",
    summaryText: Object.freeze({
      upcoming: "has an upcoming event",
      default: "had an event"
    })
  }),
  PHONE_CALL: Object.freeze({
    key: "Phone call",
    label: "Phone call",
    category: ACTIVITY_CATEGORIES.INTERACTIONS,
    icon: "standard:call",
    badgeKey: "phone",
    recordObjectApiName: "Event",
    summaryText: Object.freeze({
      upcoming: "has an upcoming call",
      default: "had a call"
    })
  }),
  EMAIL: Object.freeze({
    key: "Email",
    label: "Email",
    category: ACTIVITY_CATEGORIES.INTERACTIONS,
    icon: "standard:email",
    badgeKey: "email",
    recordObjectApiName: "Event",
    summaryText: Object.freeze({
      default: "sent an email"
    })
  }),
  TEXT_SMS: Object.freeze({
    key: "Text/SMS",
    label: "Text/SMS",
    category: ACTIVITY_CATEGORIES.INTERACTIONS,
    icon: "utility:sms",
    badgeKey: "sms",
    recordObjectApiName: "Event",
    summaryText: Object.freeze({
      upcoming: "has an upcoming text",
      default: "sent a text"
    })
  }),
  CHAT: Object.freeze({
    key: "Chat",
    label: "Chat",
    category: ACTIVITY_CATEGORIES.INTERACTIONS,
    icon: "standard:live_chat",
    badgeKey: "chat",
    recordObjectApiName: "EngagementInteraction",
    summaryText: Object.freeze({
      default: "had a chat"
    })
  }),
  SIGNIFICANT_EVENT: Object.freeze({
    key: "Significant Event",
    label: "Significant Event",
    category: ACTIVITY_CATEGORIES.INTERACTIONS,
    icon: "standard:event",
    badgeKey: "significant-event",
    recordObjectApiName: "Significant_Event__c",
    summaryText: Object.freeze({
      default: "has a significant event"
    })
  })
});

export const ACTIVITY_TYPE_LIST = Object.freeze(Object.values(ACTIVITY_TYPES));

export const ACTIVITY_TYPE_BY_KEY = Object.freeze(
  ACTIVITY_TYPE_LIST.reduce((typeByKey, activityType) => {
    typeByKey[activityType.key] = activityType;
    return typeByKey;
  }, {})
);

export const EVENT_TYPE_TO_ACTIVITY_TYPE = Object.freeze({
  Call: ACTIVITY_TYPES.PHONE_CALL.key,
  Meeting: ACTIVITY_TYPES.MEETING.key,
  Event: ACTIVITY_TYPES.MEETING.key,
  Email: ACTIVITY_TYPES.EMAIL.key,
  Zoom: ACTIVITY_TYPES.MEETING.key,
  Other: ACTIVITY_TYPES.TEXT_SMS.key
});

export const CHANNEL_TO_ACTIVITY_TYPE = Object.freeze({
  "Voice Call": ACTIVITY_TYPES.PHONE_CALL.key,
  "Web Chat": ACTIVITY_TYPES.CHAT.key,
  "Video Call": ACTIVITY_TYPES.MEETING.key,
  "In Person": ACTIVITY_TYPES.MEETING.key
});

export const ICON_TO_OBJECT_API_NAME = Object.freeze(
  ACTIVITY_TYPE_LIST.reduce((objectApiNameByIcon, activityType) => {
    objectApiNameByIcon[activityType.icon] = activityType.recordObjectApiName;
    return objectApiNameByIcon;
  }, {})
);

export const DEFAULT_ACTIVITY_TYPE = ACTIVITY_TYPES.MEETING;

export const DEFAULT_ACTIVITY_ICON = DEFAULT_ACTIVITY_TYPE.icon;

export const getActivityTypeConfig = (activityType) =>
  ACTIVITY_TYPE_BY_KEY[activityType] || DEFAULT_ACTIVITY_TYPE;

export const getActivityIcon = (activityType) =>
  getActivityTypeConfig(activityType).icon;

export const getActivityBadgeKey = (activityType) =>
  getActivityTypeConfig(activityType).badgeKey;

export const getActivityRecordObjectApiName = (activityType) =>
  getActivityTypeConfig(activityType).recordObjectApiName;

export const getRecordObjectApiNameFromIcon = (icon) =>
  ICON_TO_OBJECT_API_NAME[icon] || null;

const toFirstPersonActionText = (actionText, ownerIsYou) => {
  if (!ownerIsYou || !actionText) {
    return actionText;
  }

  if (actionText.startsWith("has an ")) {
    return `have an ${actionText.slice(7)}`;
  }

  if (actionText.startsWith("has a ")) {
    return `have a ${actionText.slice(6)}`;
  }

  if (actionText.startsWith("has ")) {
    return `have ${actionText.slice(4)}`;
  }

  return actionText;
};

export const getSummaryActionText = (
  activityType,
  { category = "", isUpcoming = false, ownerIsYou = false } = {}
) => {
  const typeConfig = getActivityTypeConfig(activityType);
  const summaryText = typeConfig.summaryText || {};
  let actionText;

  if (
    category === ACTIVITY_CATEGORIES.WORK &&
    typeConfig.key === ACTIVITY_TYPES.CASE.key
  ) {
    actionText = summaryText.default;
  } else if (
    category === ACTIVITY_CATEGORIES.WORK &&
    typeConfig.key === ACTIVITY_TYPES.TASK.key
  ) {
    actionText = isUpcoming
      ? summaryText.upcoming || summaryText.default
      : summaryText.default;
  } else if (isUpcoming && summaryText.upcoming) {
    actionText = summaryText.upcoming;
  } else {
    actionText =
      summaryText.default ||
      (isUpcoming
        ? DEFAULT_ACTIVITY_TYPE.summaryText.upcoming
        : DEFAULT_ACTIVITY_TYPE.summaryText.default);
  }

  return toFirstPersonActionText(actionText, ownerIsYou);
};

export const resolveEventActivityType = (eventType) => {
  if (EVENT_TYPE_TO_ACTIVITY_TYPE[eventType]) {
    return EVENT_TYPE_TO_ACTIVITY_TYPE[eventType];
  }

  return eventType || DEFAULT_ACTIVITY_TYPE.key;
};

export const resolveEngagementActivityType = (communicationChannel) =>
  CHANNEL_TO_ACTIVITY_TYPE[communicationChannel] ||
  communicationChannel ||
  ACTIVITY_TYPES.CHAT.key;

export const ACTIVITY_QUICK_ACTION_SUFFIXES = Object.freeze({
  task: "NewStandardTask",
  call: "LogACallStandard",
  meeting: "NewEvent"
});

export const GLOBAL_ACTIVITY_ACTION_KEYS = Object.freeze(new Set(["meeting"]));

export const ACTIVITY_UTILITY_LABEL = "Activity Actions";

export const ACTIVITY_UTILITY_PANEL = Object.freeze({
  defaultLabel: ACTIVITY_UTILITY_LABEL,
  width: 480,
  height: 640
});

export const ACTIVITY_ACTION_META = Object.freeze({
  task: Object.freeze({
    label: "New Task",
    icon: "standard:task"
  }),
  call: Object.freeze({
    label: "Log a Call",
    icon: "standard:log_a_call"
  }),
  meeting: Object.freeze({
    label: "New Meeting",
    icon: "standard:event"
  })
});

export const buildActivityQuickActionApiName = (objectApiName, actionKey) => {
  if (!objectApiName || !actionKey) {
    return null;
  }

  const suffix = ACTIVITY_QUICK_ACTION_SUFFIXES[actionKey];
  if (!suffix) {
    return null;
  }

  if (GLOBAL_ACTIVITY_ACTION_KEYS.has(actionKey)) {
    return `Global.${suffix}`;
  }

  return `${objectApiName}.${suffix}`;
};

export const getActivityActionLabel = (actionKey) =>
  ACTIVITY_ACTION_META[actionKey]?.label ?? ACTIVITY_UTILITY_LABEL;

export const getActivityActionIcon = (actionKey) =>
  ACTIVITY_ACTION_META[actionKey]?.icon ?? "standard:task";

export const buildActivityQuickActionUrl = ({
  quickActionApiName,
  recordId,
  objectApiName
}) => {
  const backgroundContext = encodeURIComponent(
    `/lightning/r/${objectApiName}/${recordId}/view`
  );

  return `/lightning/action/quick/${quickActionApiName}?context=RECORD_DETAIL&recordId=${recordId}&backgroundContext=${backgroundContext}`;
};