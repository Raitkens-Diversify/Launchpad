// Author: Hoang Long Vu To | Date: 2026-08-28
import { LightningElement, api, track, wire } from "lwc";
import { NavigationMixin, CurrentPageReference } from "lightning/navigation";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import { refreshApex } from "@salesforce/apex";
import {
  registerRefreshHandler,
  unregisterRefreshHandler
} from "lightning/refresh";
import USER_NAME_FIELD from "@salesforce/schema/User.Name";
import USER_ID from "@salesforce/user/Id";
import getTimelineData from "@salesforce/apex/ActivityTimelineController.getTimelineData";
import getTimelineDataPage from "@salesforce/apex/ActivityTimelineController.getTimelineDataPage";
import {
  ACTIVITY_CATEGORIES,
  CATEGORY_CONFIG,
  CATEGORY_ORDER,
  getActivityBadgeKey,
  getActivityIcon,
  getRecordObjectApiNameFromIcon,
  getSummaryActionText,
  buildActivityQuickActionApiName
} from "c/activityTimelineConstants";
import { isValidSalesforceRecordId } from "c/recordNavigationUtils";

// ── Constants ────────────────────────────────────────────────────────────────

const getCurrentMonthKey = () => {
  const now = new Date();
  const month = String(now.getMonth() + 1).padStart(2, "0");
  return `${now.getFullYear()}-${month}`;
};

const getActivityMonthKey = (activityDateTime) => {
  if (!activityDateTime) {
    return null;
  }

  const date = new Date(activityDateTime);
  const month = String(date.getMonth() + 1).padStart(2, "0");
  return `${date.getFullYear()}-${month}`;
};

const CATEGORY_ORDER_VALUES = [...CATEGORY_ORDER];

const WORK_ACTION_ICON = CATEGORY_CONFIG[ACTIVITY_CATEGORIES.WORK].icon;
const INTERACTION_ACTION_ICON =
  CATEGORY_CONFIG[ACTIVITY_CATEGORIES.INTERACTIONS].icon;

const ACTIVITY_CREATE_OBJECT_API_NAMES = Object.freeze([
  "Advisor_Group__c",
  "Account"
]);

const TYPE_ICON_CLASS = "timeline-icon";
const BRANCH_OBJECT_API_NAME = "Advisor_Group__c";

const STATUS_BADGE_KEY = {
  "In Progress": "progress",
  Completed: "completed",
  Pending: "pending"
};

const SORT_OPTIONS = [
  { label: "Newest first", value: "newest" },
  { label: "Oldest first", value: "oldest" }
];

const EXTERNAL_TOGGLE_LABEL = "Customer Only";

const ACTIVE_USER_FILTER = Object.freeze({
  criteria: [
    {
      fieldPath: "IsActive",
      operator: "eq",
      value: true
    }
  ]
});

const DEFAULT_SELECTED_TYPES = Object.freeze({
  Case: true,
  Task: true,
  Email: true,
  "Phone call": true,
  Meeting: true,
  "Significant Event": true
});

const WORK_TYPE_FILTERS = Object.freeze([
  { value: "Case", label: "Case" },
  { value: "Task", label: "Task" }
]);

const INTERACTIONS_TYPE_FILTERS = Object.freeze([
  { value: "Email", label: "Email" },
  { value: "Phone call", label: "Call" },
  { value: "Meeting", label: "Meeting" },
  { value: "Significant Event", label: "Significant Event" }
]);

const FILTERABLE_TYPE_KEYS = Object.freeze([
  ...WORK_TYPE_FILTERS.map((typeFilter) => typeFilter.value),
  ...INTERACTIONS_TYPE_FILTERS.map((typeFilter) => typeFilter.value)
]);

const MAX_AUTO_LOADED_ACTIVITIES = 250;
const MAX_AUTO_ACTIVITY_PAGES = 6;

const ACTIVITY_TYPE_FILTER_ALIASES = Object.freeze({
  Event: "Meeting"
});

const resolveFilterActivityType = (activityType) =>
  ACTIVITY_TYPE_FILTER_ALIASES[activityType] || activityType;

const EMPTY_FILTERS = {
  ownerUsers: [],
  ownerPickerResetToken: 0,
  dueDateFrom: "",
  dueDateTo: "",
  status: "",
  selectedTypes: { ...DEFAULT_SELECTED_TYPES }
};

const buildActiveUserFilter = (excludedUserIds = []) => {
  const criteria = [...ACTIVE_USER_FILTER.criteria];

  if (excludedUserIds.length) {
    criteria.push({
      fieldPath: "Id",
      operator: "nin",
      value: excludedUserIds
    });
  }

  return { criteria };
};

const cloneEmptyFilters = () => JSON.parse(JSON.stringify(EMPTY_FILTERS));

const mergeActivitiesById = (existingActivities, incomingActivities) => {
  const activityById = new Map();

  (existingActivities || []).forEach((activity) => {
    if (activity?.id) {
      activityById.set(activity.id, activity);
    }
  });

  (incomingActivities || []).forEach((activity) => {
    if (activity?.id) {
      activityById.set(activity.id, activity);
    }
  });

  return [...activityById.values()];
};

const buildClientCategoryCounts = (activities) => {
  const counts = {};

  CATEGORY_ORDER_VALUES.forEach((category) => {
    counts[category] = 0;
  });

  (activities || []).forEach((activity) => {
    if (activity?.category && counts[activity.category] != null) {
      counts[activity.category] += 1;
    }
  });

  return counts;
};

const isCurrentYear = (activityDateTime) => {
  if (!activityDateTime) {
    return true;
  }

  return (
    new Date(activityDateTime).getFullYear() === new Date().getFullYear()
  );
};

const formatTime = (activityDateTime) => {
  if (!activityDateTime) {
    return "";
  }

  return new Date(activityDateTime).toLocaleTimeString("en-US", {
    hour: "numeric",
    minute: "2-digit"
  });
};

const formatActivityDatePart = (activityDateTime) => {
  if (!activityDateTime) {
    return "";
  }

  const activityDate = new Date(activityDateTime);
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  activityDate.setHours(0, 0, 0, 0);

  if (activityDate.getTime() === today.getTime()) {
    return "Today";
  }

  const options = isCurrentYear(activityDateTime)
    ? { month: "short", day: "numeric" }
    : { month: "short", day: "numeric", year: "numeric" };

  return new Date(activityDateTime).toLocaleDateString("en-US", options);
};

const formatDateTimeDisplay = (activityDateTime) => {
  const timePart = formatTime(activityDateTime);
  const datePart = formatActivityDatePart(activityDateTime);

  if (!timePart && !datePart) {
    return "";
  }

  if (!datePart) {
    return timePart;
  }

  if (!timePart) {
    return datePart;
  }

  return `${timePart} | ${datePart}`;
};

const NO_DATE_GROUP_ID = "__no_date__";
const NO_DATE_GROUP_LABEL = "No due date";
const UPCOMING_GROUP_LABEL = "Upcoming";

const hasActivitySchedule = (activity) =>
  !!activity?.activityDateTime && activity.activityDateTime > 0;

const resolveActivityMonthGroupKey = (activity) => {
  if (!hasActivitySchedule(activity)) {
    return NO_DATE_GROUP_ID;
  }

  return getActivityMonthKey(activity.activityDateTime) || NO_DATE_GROUP_ID;
};

const formatMonthGroupPrimaryLabel = (monthKey) => {
  if (monthKey === NO_DATE_GROUP_ID) {
    return UPCOMING_GROUP_LABEL;
  }

  const [year, month] = monthKey.split("-");
  const monthDate = new Date(Number(year), Number(month) - 1, 1);
  const monthName = monthDate.toLocaleDateString("en-US", { month: "long" });
  const yearNumber = Number(year);

  if (yearNumber === new Date().getFullYear()) {
    return monthName;
  }

  return `${monthName} • ${yearNumber}`;
};

const getMonthOffsetFromCurrent = (monthKey) => {
  if (monthKey === NO_DATE_GROUP_ID) {
    return null;
  }

  const [year, month] = monthKey.split("-").map(Number);
  const now = new Date();
  const currentMonthIndex = now.getFullYear() * 12 + now.getMonth();
  const targetMonthIndex = year * 12 + (month - 1);

  return targetMonthIndex - currentMonthIndex;
};

const formatMonthRelativeLabel = (monthKey) => {
  const monthOffset = getMonthOffsetFromCurrent(monthKey);

  if (monthOffset === null) {
    return "";
  }

  if (monthOffset === 0) {
    return "This Month";
  }

  if (monthOffset === -1) {
    return "Last Month";
  }

  if (monthOffset === 1) {
    return "Next Month";
  }

  return "";
};

const sortMonthGroupKeys = (firstKey, secondKey, sortOrder) => {
  if (firstKey === NO_DATE_GROUP_ID) {
    return -1;
  }

  if (secondKey === NO_DATE_GROUP_ID) {
    return 1;
  }

  return sortOrder === "newest"
    ? secondKey.localeCompare(firstKey)
    : firstKey.localeCompare(secondKey);
};

const getActivitySortTimestamp = (activity) => {
  const timestamp = Number(activity?.activityDateTime);
  return Number.isFinite(timestamp) && timestamp > 0 ? timestamp : 0;
};

const compareActivitiesBySortOrder = (first, second, sortOrder) => {
  const firstTimestamp = getActivitySortTimestamp(first);
  const secondTimestamp = getActivitySortTimestamp(second);
  const dateDiff =
    sortOrder === "newest"
      ? secondTimestamp - firstTimestamp
      : firstTimestamp - secondTimestamp;

  if (dateDiff !== 0) {
    return dateDiff;
  }

  const firstTitle = first?.title || "";
  const secondTitle = second?.title || "";

  return sortOrder === "newest"
    ? secondTitle.localeCompare(firstTitle)
    : firstTitle.localeCompare(secondTitle);
};

const formatActivityTimeDisplay = (activity) => {
  if (activity?.hasDueDate === false || !hasActivitySchedule(activity)) {
    return NO_DATE_GROUP_LABEL;
  }

  const datePart = formatActivityDatePart(activity.activityDateTime);

  if (activity?.approximateDate === true && datePart) {
    return `${datePart} (Approx.)`;
  }

  return formatDateTimeDisplay(activity.activityDateTime);
};

const getParticipantName = (participant) =>
  typeof participant === "string" ? participant : participant?.name || "";

const normalizeSearchTerm = (searchTerm) =>
  (searchTerm || "").trim().toLowerCase();

const appendParticipantSearchText = (searchParts, participant) => {
  const name = getParticipantName(participant);

  if (name) {
    searchParts.push(name);
  }

  if (participant?.objectApiName) {
    searchParts.push(participant.objectApiName);
  }
};

const buildActivitySearchText = (activity) => {
  const searchParts = [
    activity.title,
    activity.description,
    activity.status,
    activity.activityType,
    activity.category,
    activity.linkedRecord,
    activity.associatedAccountName,
    activity.contextBranchName,
    activity.ownerName,
    activity.fromAddress
  ];

  if (activity.approximateDate === true) {
    searchParts.push("Approximate");
    searchParts.push("Approx.");
  }

  (activity.participants || []).forEach((participant) =>
    appendParticipantSearchText(searchParts, participant)
  );
  (activity.relatedParticipants || []).forEach((participant) =>
    appendParticipantSearchText(searchParts, participant)
  );

  return searchParts
    .filter((value) => value != null && value !== "")
    .join(" ")
    .toLowerCase();
};

const matchesSearchTerm = (activity, searchTerm) => {
  const normalizedSearch = normalizeSearchTerm(searchTerm);

  if (!normalizedSearch) {
    return true;
  }

  return buildActivitySearchText(activity).includes(normalizedSearch);
};

const buildRecordHref = (recordId, objectApiName) => {
  if (!recordId || !objectApiName) {
    return null;
  }

  return `/lightning/r/${objectApiName}/${recordId}/view`;
};

const buildNavigableParticipant = (participant, key) => {
  const recordId = participant?.id;
  const objectApiName = participant?.objectApiName;

  return {
    key,
    recordId,
    name: participant?.name || "",
    objectApiName,
    href: buildRecordHref(recordId, objectApiName),
    isNavigable: !!(recordId && objectApiName)
  };
};

const buildSignificantEventActivitySummary = (
  activity,
  { isHouseholdRecordContext = false } = {}
) => {
  const relatedParticipants = activity.relatedParticipants || [];
  const participantsToShow = isHouseholdRecordContext
    ? relatedParticipants
    : relatedParticipants.slice(0, 1);
  const participantLinks = participantsToShow
    .map((participant, index) =>
      buildNavigableParticipant(
        participant,
        `${activity.id}-significant-event-participant-${index}`
      )
    )
    .filter((participant) => participant.name)
    .map((participant, index, participants) => ({
      ...participant,
      showSeparator: index < participants.length - 1
    }));

  if (participantLinks.length === 0) {
    return { hasSummary: false };
  }

  return {
    hasSummary: true,
    isSignificantEventLed: true,
    participantLinks,
    actionText: getSummaryActionText(activity.activityType, {
      category: activity.category
    })
  };
};

const buildEmailActivitySummary = (activity) => {
  const fromAddress = activity.fromAddress || activity.ownerName || "";
  const relatedParticipants = activity.relatedParticipants || [];
  const recipientLink =
    relatedParticipants.length > 0
      ? buildNavigableParticipant(
          relatedParticipants[0],
          `${activity.id}-email-recipient-0`
        )
      : null;

  if (!fromAddress && !recipientLink?.name) {
    return { hasSummary: false };
  }

  return {
    hasSummary: true,
    isEmail: true,
    fromAddress,
    actionText: "sent an email to",
    recipientLink,
    hasRelated: relatedParticipants.length > 1,
    extraRelatedCount:
      relatedParticipants.length > 1 ? relatedParticipants.length - 1 : 0
  };
};

const buildActivitySummary = (activity, currentUserId, options = {}) => {
  if (activity.activityType === "Significant Event") {
    return buildSignificantEventActivitySummary(activity, options);
  }

  if (activity.activityType === "Email") {
    return buildEmailActivitySummary(activity);
  }

  const ownerId = activity.ownerId;
  const ownerName = activity.ownerName || "";
  const relatedParticipants = activity.relatedParticipants || [];
  const isUpcoming =
    activity.hasDueDate !== false &&
    (activity.activityDateTime || 0) > Date.now();
  const ownerIsYou = ownerId === currentUserId;
  const actionText = getSummaryActionText(activity.activityType, {
    category: activity.category,
    isUpcoming,
    ownerIsYou
  });

  if (!ownerId && relatedParticipants.length > 0) {
    const firstRelated = buildNavigableParticipant(
      relatedParticipants[0],
      `${activity.id}-related-0`
    );

    return {
      hasSummary: true,
      isContactLed: true,
      contactLink: firstRelated,
      actionText,
      hasRelated: relatedParticipants.length > 1,
      extraRelatedCount:
        relatedParticipants.length > 1 ? relatedParticipants.length - 1 : 0
    };
  }

  if (!ownerId && !ownerName) {
    return { hasSummary: false };
  }

  const firstRelated =
    relatedParticipants.length > 0
      ? buildNavigableParticipant(
          relatedParticipants[0],
          `${activity.id}-related-0`
        )
      : null;

  return {
    hasSummary: true,
    isContactLed: false,
    ownerIsYou,
    ownerLabel: ownerIsYou ? "You" : ownerName,
    ownerLink: ownerId
      ? buildNavigableParticipant(
          { id: ownerId, name: ownerName, objectApiName: "User" },
          `${activity.id}-owner`
        )
      : null,
    actionText,
    hasRelated: relatedParticipants.length > 0,
    firstRelated,
    extraRelatedCount:
      relatedParticipants.length > 1 ? relatedParticipants.length - 1 : 0
  };
};

const hasDisplayText = (value) =>
  typeof value === "string" && value.trim().length > 0;

const formatEndDateDisplay = (endDateValue) => {
  if (!hasDisplayText(endDateValue)) {
    return null;
  }

  const [year, month, day] = endDateValue.split("-").map(Number);

  if (!year || !month || !day) {
    return null;
  }

  return new Date(year, month - 1, day).toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric"
  });
};

const TASK_EVENT_OBJECT_API_NAMES = new Set(["Task", "Event"]);

const isTaskOrEventActivity = (activity) =>
  TASK_EVENT_OBJECT_API_NAMES.has(activity.recordObjectApiName);

const buildRelatedToLink = (activity) => {
  const linkedRecord = hasDisplayText(activity.linkedRecord)
    ? activity.linkedRecord.trim()
    : null;

  if (
    !linkedRecord ||
    !activity.linkedRecordId ||
    !activity.linkedRecordObjectApiName
  ) {
    return null;
  }

  return buildNavigableParticipant(
    {
      id: activity.linkedRecordId,
      name: linkedRecord,
      objectApiName: activity.linkedRecordObjectApiName
    },
    `${activity.id}-linked-record`
  );
};

const supportsAssociatedAccountLink = (activity) =>
  isTaskOrEventActivity(activity) ||
  activity.activityType === "Case" ||
  activity.activityType === "Significant Event";

const buildAssociatedAccountLink = (activity) => {
  if (!supportsAssociatedAccountLink(activity)) {
    return null;
  }

  const linkedAccountId =
    activity.linkedRecordObjectApiName === "Account"
      ? activity.linkedRecordId
      : null;
  const linkedAccountName =
    activity.linkedRecordObjectApiName === "Account" && hasDisplayText(activity.linkedRecord)
      ? activity.linkedRecord.trim()
      : null;
  const accountId = activity.associatedAccountId || linkedAccountId;
  const accountName = hasDisplayText(activity.associatedAccountName)
    ? activity.associatedAccountName.trim()
    : linkedAccountName;

  if (!accountId || !accountName) {
    return null;
  }

  return buildNavigableParticipant(
    {
      id: accountId,
      name: accountName,
      objectApiName: "Account"
    },
    `${activity.id}-associated-account`
  );
};

const supportsAssociatedBranchLink = (activity) =>
  isTaskOrEventActivity(activity) ||
  activity.activityType === "Significant Event";

const buildAssociatedBranchLink = (activity, contextBranch) => {
  if (!supportsAssociatedBranchLink(activity)) {
    return null;
  }

  if (
    activity.linkedRecordObjectApiName === BRANCH_OBJECT_API_NAME &&
    activity.linkedRecordId &&
    hasDisplayText(activity.linkedRecord)
  ) {
    return buildNavigableParticipant(
      {
        id: activity.linkedRecordId,
        name: activity.linkedRecord.trim(),
        objectApiName: BRANCH_OBJECT_API_NAME
      },
      `${activity.id}-associated-branch`
    );
  }

  if (
    contextBranch?.id &&
    contextBranch?.name &&
    activity.linkedRecordObjectApiName !== BRANCH_OBJECT_API_NAME
  ) {
    return buildNavigableParticipant(
      {
        id: contextBranch.id,
        name: contextBranch.name,
        objectApiName: BRANCH_OBJECT_API_NAME
      },
      `${activity.id}-context-branch`
    );
  }

  return null;
};

const buildActivityDetails = (activity, options = {}) => {
  const includeLinkedRecordInDetails = options.includeLinkedRecordInDetails !== false;
  const description = hasDisplayText(activity.description)
    ? activity.description.trim()
    : null;
  const linkedRecordLink = buildRelatedToLink(activity);
  const detailsLinkedRecordLink = includeLinkedRecordInDetails
    ? linkedRecordLink
    : null;
  const status = hasDisplayText(activity.status) ? activity.status.trim() : null;
  const endDateDisplay = formatEndDateDisplay(activity.endDateValue);
  const participantLinks = (activity.relatedParticipants || [])
    .map((participant, index) =>
      buildNavigableParticipant(
        participant,
        `${activity.id}-detail-participant-${index}`
      )
    )
    .filter((participant) => participant.name)
    .map((participant, index, participants) => ({
      ...participant,
      showSeparator: index < participants.length - 1
    }));
  const hasDetails = !!(
    description ||
    detailsLinkedRecordLink ||
    status ||
    endDateDisplay ||
    participantLinks.length
  );

  return {
    hasDetails,
    description,
    showDescriptionAtTop: !!description,
    endDateDisplay,
    linkedRecord: linkedRecordLink?.name || null,
    linkedRecordLink: detailsLinkedRecordLink,
    status,
    statusLabel:
      activity.activityType === "Significant Event" ? "Type" : "Status",
    participantLinks,
    showParticipants:
      participantLinks.length > 0 && activity.activityType !== "Email"
  };
};

// ── Component ────────────────────────────────────────────────────────────────

export default class ActivityTimeline extends NavigationMixin(
  LightningElement
) {
  @api recordId;

  @track activeFilters = {
    Work: true,
    Interactions: true
  };

  @track searchTerm = "";
  @track sortOrder = "newest";
  @track activeFilterTab = "Work";
  @track isFilterPanelExpanded = false;
  @track filterValues = cloneEmptyFilters();
  @track pendingUserPickerRecordId = null;
  @track allActivities = [];
  @track categoryCounts = {};
  @track visibleMonthKeys = [getCurrentMonthKey()];
  @track collapsedGroupKeyList = [];
  @track expandedActivityIds = {};
  @track customerOnlyMode = false;
  @track hasMoreActivities = false;
  @track isLoadingMore = false;

  recordObjectApiName;
  showExternalToggle = false;
  supportsExternalToggle = false;
  isHouseholdRecordContext = false;
  isDrpRecordContext = false;
  contextBranchId = null;
  contextBranchName = null;
  previousRecordId;
  paginationRecordId;
  workMenuOpen = false;
  interactionMenuOpen = false;
  documentClickListenerActive = false;
  pendingOwnerPicker = false;
  isLoading = true;
  loadError;
  wiredTimelineResult;
  refreshHandlerId;
  pendingActivityActionRefresh = false;
  activityActionRefreshTimeoutId;
  nextActivityPage = 1;
  activityLoadGeneration = 0;

  sortOptions = SORT_OPTIONS;

  connectedCallback() {
    this.refreshHandlerId = registerRefreshHandler(
      this.template.host,
      this.handleRefreshView
    );
  }

  disconnectedCallback() {
    this.removeDocumentClickListener();
    this.clearActivityActionRefreshTimeout();

    if (this.refreshHandlerId) {
      unregisterRefreshHandler(this.refreshHandlerId);
      this.refreshHandlerId = null;
    }
  }

  @api
  refresh() {
    return this.refreshTimelineData();
  }

  handleRefreshView = () => {
    if (!this.pendingActivityActionRefresh) {
      return Promise.resolve(true);
    }

    this.pendingActivityActionRefresh = false;
    this.clearActivityActionRefreshTimeout();

    return this.refreshTimelineData().then((refreshed) =>
      refreshed === false ? false : true
    );
  };

  markPendingActivityActionRefresh() {
    this.pendingActivityActionRefresh = true;
    this.clearActivityActionRefreshTimeout();
    this.activityActionRefreshTimeoutId = setTimeout(() => {
      this.pendingActivityActionRefresh = false;
      this.activityActionRefreshTimeoutId = null;
    }, 300000);
  }

  clearActivityActionRefreshTimeout() {
    if (!this.activityActionRefreshTimeoutId) {
      return;
    }

    clearTimeout(this.activityActionRefreshTimeoutId);
    this.activityActionRefreshTimeoutId = null;
  }

  refreshTimelineData() {
    if (!this.recordId || !this.wiredTimelineResult) {
      return Promise.resolve(false);
    }

    this.isLoading = true;
    this.loadError = undefined;
    this.resetActivityPaging();

    return refreshApex(this.wiredTimelineResult)
      .then(() => true)
      .catch((error) => {
        this.loadError = error;
        this.isLoading = false;
        return false;
      });
  }

  resetActivityPaging() {
    this.activityLoadGeneration += 1;
    this.hasMoreActivities = false;
    this.nextActivityPage = 1;
    this.isLoadingMore = false;
  }

  prefetchActivityPages(generation) {
    if (
      !this.includeExternalActivitiesForQuery ||
      !this.hasMoreActivities ||
      this.allActivities.length >= MAX_AUTO_LOADED_ACTIVITIES
    ) {
      return;
    }

    let autoPagesLoaded = 0;

    const loadNextPage = () => {
      if (
        generation !== this.activityLoadGeneration ||
        !this.hasMoreActivities ||
        !this.includeExternalActivitiesForQuery ||
        this.allActivities.length >= MAX_AUTO_LOADED_ACTIVITIES ||
        autoPagesLoaded >= MAX_AUTO_ACTIVITY_PAGES
      ) {
        return Promise.resolve();
      }

      return this.fetchNextActivityPage(generation).then((didLoad) => {
        if (!didLoad) {
          return undefined;
        }

        autoPagesLoaded += 1;
        return loadNextPage();
      });
    };

    Promise.resolve()
      .then(loadNextPage)
      .catch(() => undefined);
  }

  fetchNextActivityPage(generation) {
    if (
      this.isLoadingMore ||
      !this.hasMoreActivities ||
      !this.wiredContextRecordId
    ) {
      return Promise.resolve(false);
    }

    const requestedGeneration = generation;
    this.isLoadingMore = true;

    return getTimelineDataPage({
      recordId: this.wiredContextRecordId,
      includeExternalActivities: true,
      pageNumber: this.nextActivityPage
    })
      .then((data) => {
        if (requestedGeneration !== this.activityLoadGeneration) {
          return false;
        }

        const incomingActivities = data?.activities || [];
        this.allActivities = mergeActivitiesById(
          this.allActivities,
          incomingActivities
        );
        this.categoryCounts = buildClientCategoryCounts(this.allActivities);
        this.hasMoreActivities = data?.hasMoreActivities === true;
        this.nextActivityPage =
          data?.nextPageNumber != null
            ? data.nextPageNumber
            : this.nextActivityPage + 1;
        this.resetPagination();
        return incomingActivities.length > 0;
      })
      .catch(() => {
        if (requestedGeneration === this.activityLoadGeneration) {
          this.hasMoreActivities = true;
        }

        return false;
      })
      .finally(() => {
        if (requestedGeneration === this.activityLoadGeneration) {
          this.isLoadingMore = false;
        }
      });
  }

  @wire(CurrentPageReference)
  wiredPageReference(pageRef) {
    const objectApiName = pageRef?.attributes?.objectApiName;
    if (objectApiName) {
      this.recordObjectApiName = objectApiName;
    }
  }

  get wiredContextRecordId() {
    return isValidSalesforceRecordId(this.recordId) ? this.recordId : undefined;
  }

  @wire(getRecord, { recordId: "$wiredContextRecordId" })
  wiredContextRecord({ data }) {
    if (data?.apiName) {
      this.recordObjectApiName = data.apiName;
    }
  }

  @wire(getTimelineData, {
    recordId: "$wiredContextRecordId",
    includeExternalActivities: "$includeExternalActivitiesForQuery"
  })
  wiredTimelineData(result) {
    this.wiredTimelineResult = result;
    const { data, error } = result;

    if (!this.wiredContextRecordId) {
      this.isLoading = false;
      this.allActivities = [];
      this.categoryCounts = {};
      this.showExternalToggle = false;
      this.supportsExternalToggle = false;
      this.isHouseholdRecordContext = false;
      this.isDrpRecordContext = false;
      this.contextBranchId = null;
      this.contextBranchName = null;
      this.paginationRecordId = null;
      this.resetActivityPaging();
      return;
    }

    if (this.recordId !== this.previousRecordId) {
      this.customerOnlyMode = false;
      this.supportsExternalToggle = false;
      this.previousRecordId = this.recordId;
      this.resetActivityPaging();
    }

    if (data) {
      if (data.showExternalToggle === true) {
        this.supportsExternalToggle = true;
      }
      this.showExternalToggle =
        data.showExternalToggle === true || this.supportsExternalToggle;
      this.isHouseholdRecordContext = data.isHouseholdRecordContext === true;
      this.isDrpRecordContext = data.isDrpRecordContext === true;
      this.contextBranchId = data.contextBranchId || null;
      this.contextBranchName = data.contextBranchName || null;
      this.allActivities = data.activities || [];
      this.categoryCounts = data.categoryCounts || {};
      this.hasMoreActivities = data.hasMoreActivities === true;
      this.nextActivityPage = data.nextPageNumber || 1;
      this.isLoading = false;
      this.loadError = undefined;

      if (this.recordId !== this.paginationRecordId) {
        this.resetPagination();
        this.collapsedGroupKeyList = [];
        this.paginationRecordId = this.recordId;
      }

      this.prefetchActivityPages(this.activityLoadGeneration);
      return;
    }

    if (error) {
      this.isLoading = false;
      this.loadError = error;
      this.allActivities = [];
      this.categoryCounts = {};
      this.showExternalToggle = this.supportsExternalToggle;
      this.hasMoreActivities = false;
    }
  }

  get includeExternalActivitiesForQuery() {
    return !this.customerOnlyMode;
  }

  get showExternalToggleControl() {
    return this.showExternalToggle || this.supportsExternalToggle;
  }

  get externalToggleLabel() {
    return EXTERNAL_TOGGLE_LABEL;
  }

  get externalToggleAriaLabel() {
    return `${EXTERNAL_TOGGLE_LABEL} activities`;
  }

  get showAssociatedAccountContext() {
    return (
      this.isHouseholdRecordContext ||
      (this.showExternalToggleControl && !this.customerOnlyMode)
    );
  }

  get userPickerRecordId() {
    return this.pendingUserPickerRecordId;
  }

  @wire(getRecord, {
    recordId: "$userPickerRecordId",
    fields: [USER_NAME_FIELD]
  })
  wiredUserPickerRecord({ data, error }) {
    if (!this.pendingOwnerPicker || !this.pendingUserPickerRecordId) {
      return;
    }

    const recordId = this.pendingUserPickerRecordId;
    const selectedUsers = this.filterValues.ownerUsers || [];

    if (data) {
      const displayName = getFieldValue(data, USER_NAME_FIELD) || recordId;

      if (!selectedUsers.some((user) => user.id === recordId)) {
        this.filterValues = {
          ...this.filterValues,
          ownerUsers: [...selectedUsers, { id: recordId, name: displayName }]
        };
        this.resetPagination();
      }
    }

    if (data || error) {
      this.pendingUserPickerRecordId = null;
      this.pendingOwnerPicker = false;
    }
  }

  get filterButtons() {
    return CATEGORY_ORDER_VALUES.map((category) => {
      const config = CATEGORY_CONFIG[category];
      const isActive = !!this.activeFilters[category];
      const count =
        this.categoryCounts[category] ??
        this.allActivities.filter((activity) => activity.category === category)
          .length;

      return {
        label: config.label,
        value: category,
        count,
        icon: config.icon,
        iconClass: config.iconClass,
        isActive,
        ariaPressed: isActive ? "true" : "false",
        ariaLabel: `${config.label}, ${count} activities`,
        cssClass: isActive
          ? `${config.pillClass} filter-pill_active`
          : `${config.pillClass} filter-pill_inactive`
      };
    });
  }

  get ownerPickerInstances() {
    return [
      { id: `owner-picker-${this.filterValues.ownerPickerResetToken || 0}` }
    ];
  }

  get ownerUserFilter() {
    return buildActiveUserFilter(
      (this.filterValues.ownerUsers || []).map((user) => user.id)
    );
  }

  get ownerUserPills() {
    return (this.filterValues.ownerUsers || []).map((user) => ({
      id: user.id,
      name: user.name,
      removeLabel: `Remove ${user.name}`
    }));
  }

  get hasOwnerUserPills() {
    return this.ownerUserPills.length > 0;
  }

  buildTypeOptions(typeFilters) {
    const selectedTypes = this.filterValues.selectedTypes || DEFAULT_SELECTED_TYPES;

    return typeFilters.map((typeFilter) => ({
      ...typeFilter,
      checked: selectedTypes[typeFilter.value] !== false
    }));
  }

  get workTypeOptions() {
    return this.buildTypeOptions(WORK_TYPE_FILTERS);
  }

  get interactionTypeOptions() {
    return this.buildTypeOptions(INTERACTIONS_TYPE_FILTERS);
  }

  get filterPanelAriaExpanded() {
    return this.isFilterPanelExpanded ? "true" : "false";
  }

  get filterPanelToggleIcon() {
    return this.isFilterPanelExpanded
      ? "utility:chevrondown"
      : "utility:chevronright";
  }

  get filterPanelToggleLabel() {
    return this.isFilterPanelExpanded
      ? "Collapse filters"
      : "Expand filters";
  }

  get workActionIcon() {
    return WORK_ACTION_ICON;
  }

  get interactionActionIcon() {
    return INTERACTION_ACTION_ICON;
  }

  get showActivityActions() {
    return (
      !!this.recordId &&
      ACTIVITY_CREATE_OBJECT_API_NAMES.includes(this.recordObjectApiName)
    );
  }

  get filteredActivities() {
    return this.allActivities
      .filter((activity) => {
        if (!this.activeFilters[activity.category]) {
          return false;
        }
        if (!this.matchesFilters(activity)) {
          return false;
        }
        if (!matchesSearchTerm(activity, this.searchTerm)) {
          return false;
        }

        return true;
      })
      .sort((first, second) =>
        compareActivitiesBySortOrder(first, second, this.sortOrder)
      )
      .map((activity) => {
        const objectApiName =
          activity.recordObjectApiName ||
          getRecordObjectApiNameFromIcon(activity.icon) ||
          null;

        const summary = buildActivitySummary(activity, USER_ID, {
          isHouseholdRecordContext: this.showAssociatedAccountContext
        });
        const linkedRecordLink = buildRelatedToLink(activity);
        const contextBranch =
          this.showExternalToggleControl &&
          !this.customerOnlyMode &&
          this.isDrpRecordContext &&
          this.contextBranchId &&
          this.contextBranchName
            ? {
                id: this.contextBranchId,
                name: this.contextBranchName
              }
            : null;
        const associatedBranchLink = buildAssociatedBranchLink(
          activity,
          contextBranch
        );
        const showDrpBranchSubline =
          this.showExternalToggleControl &&
          this.isDrpRecordContext &&
          !this.customerOnlyMode &&
          associatedBranchLink !== null;
        const excludeBranchFromDetails =
          showDrpBranchSubline &&
          linkedRecordLink?.objectApiName === BRANCH_OBJECT_API_NAME;
        let details = buildActivityDetails(activity, {
          includeLinkedRecordInDetails: !excludeBranchFromDetails
        });

        if (associatedBranchLink && !showDrpBranchSubline && !details.linkedRecordLink) {
          details = {
            ...details,
            linkedRecordLink: associatedBranchLink,
            linkedRecord: associatedBranchLink.name,
            hasDetails: !!(
              details.description ||
              details.endDateDisplay ||
              associatedBranchLink ||
              details.status ||
              details.participantLinks?.length
            )
          };
        }

        const associatedAccountLink = buildAssociatedAccountLink(activity);
        const isSignificantEvent = activity.activityType === "Significant Event";
        details.showParticipants =
          details.participantLinks.length > 0 &&
          activity.activityType !== "Email" &&
          ((isSignificantEvent && this.showAssociatedAccountContext) ||
            (!isSignificantEvent &&
              (details.participantLinks.length > 1 || !summary.hasRelated)));
        const isDetailsExpanded = !!this.expandedActivityIds[activity.id];

        return {
          ...activity,
          date: activity.dateValue,
          monthGroupKey: resolveActivityMonthGroupKey(activity),
          time: formatTime(activity.activityDateTime),
          dateTime: formatActivityTimeDisplay(activity),
          timeDisplay: formatActivityTimeDisplay(activity),
          summary,
          details,
          showAssociatedAccount:
            associatedAccountLink !== null && this.showAssociatedAccountContext,
          associatedAccountLink,
          showDrpBranchSubline,
          drpBranchSublineLink: showDrpBranchSubline
            ? associatedBranchLink
            : null,
          hasExpandableDetails: details.hasDetails,
          isDetailsExpanded,
          detailsPanelId: `activity-details-${activity.id}`,
          detailsToggleIcon: isDetailsExpanded
            ? "utility:chevrondown"
            : "utility:chevronright",
          detailsToggleLabel: isDetailsExpanded
            ? "Hide details"
            : "Show details",
          detailsAriaExpanded: isDetailsExpanded ? "true" : "false",
          typeBadgeKey: getActivityBadgeKey(activity.activityType),
          statusBadgeKey: STATUS_BADGE_KEY[activity.status] || "default",
          icon: getActivityIcon(activity.activityType),
          iconClass: TYPE_ICON_CLASS,
          objectApiName,
          recordHref: buildRecordHref(activity.id, objectApiName)
        };
      });
  }

  get visibleActivities() {
    const visibleMonths = new Set(this.visibleMonthKeys);

    return this.filteredActivities.filter((activity) => {
      if (!hasActivitySchedule(activity)) {
        return true;
      }

      const monthKey = getActivityMonthKey(activity.activityDateTime);
      return visibleMonths.has(monthKey);
    });
  }

  get hiddenMonthKeys() {
    const visibleMonths = new Set(this.visibleMonthKeys);

    return [
      ...new Set(
        this.filteredActivities
          .filter(hasActivitySchedule)
          .map((activity) => getActivityMonthKey(activity.activityDateTime))
          .filter((monthKey) => !visibleMonths.has(monthKey))
      )
    ].sort((first, second) =>
      this.sortOrder === "newest"
        ? second.localeCompare(first)
        : first.localeCompare(second)
    );
  }

  get hasMoreToLoad() {
    return this.hiddenMonthKeys.length > 0 || this.hasMoreActivities;
  }

  get loadMoreLabel() {
    if (this.isLoadingMore) {
      return "Loading more";
    }

    if (!this.hiddenMonthKeys.length) {
      return "Load More";
    }

    const [nextMonthKey] = this.hiddenMonthKeys;
    const [year, month] = nextMonthKey.split("-");
    const monthDate = new Date(Number(year), Number(month) - 1, 1);
    const monthOptions =
      Number(year) === new Date().getFullYear()
        ? { month: "long" }
        : { month: "long", year: "numeric" };
    const monthLabel = monthDate.toLocaleDateString("en-US", monthOptions);

    return `Load ${monthLabel}`;
  }

  get groupedActivities() {
    const groupMap = new Map();
    const groups = [];

    this.visibleActivities.forEach((activity) => {
      const groupKey = activity.monthGroupKey || resolveActivityMonthGroupKey(activity);

      if (groupMap.has(groupKey)) {
        groupMap.get(groupKey).items.push(activity);
        return;
      }

      const group = {
        id: groupKey,
        panelId: `timeline-group-${groupKey}`,
        primaryLabel: formatMonthGroupPrimaryLabel(groupKey),
        relativeLabel: formatMonthRelativeLabel(groupKey),
        items: [activity]
      };
      groups.push(group);
      groupMap.set(groupKey, group);
    });

    return groups
      .map((group) => {
        const isCollapsed = this.collapsedGroupKeyList.includes(group.id);
        const sortedItems = [...group.items].sort((first, second) =>
          compareActivitiesBySortOrder(first, second, this.sortOrder)
        );

        return {
          ...group,
          items: sortedItems,
          isCollapsed,
          isExpanded: !isCollapsed,
          groupClass: isCollapsed
            ? "timeline-group timeline-group_collapsed"
            : "timeline-group",
          itemsClass: isCollapsed
            ? "timeline-group__items timeline-group__items_collapsed"
            : "timeline-group__items",
          ariaExpanded: isCollapsed ? "false" : "true",
          itemsAriaHidden: isCollapsed ? "true" : "false",
          toggleIcon: isCollapsed
            ? "utility:chevronright"
            : "utility:chevrondown",
          toggleLabel: `Toggle ${group.primaryLabel} activities`
        };
      })
      .sort((first, second) =>
        sortMonthGroupKeys(first.id, second.id, this.sortOrder)
      );
  }

  get hasFilteredEmptyState() {
    return (
      !this.isLoading &&
      !this.loadError &&
      this.allActivities.length > 0 &&
      this.filteredActivities.length === 0
    );
  }

  get hasTrueEmptyState() {
    return (
      !this.isLoading &&
      !this.loadError &&
      this.allActivities.length === 0
    );
  }

  get hasNoResults() {
    return this.hasFilteredEmptyState || this.hasTrueEmptyState;
  }

  get hasNoVisibleResults() {
    return (
      !this.isLoading &&
      !this.loadError &&
      this.filteredActivities.length > 0 &&
      this.visibleActivities.length === 0
    );
  }

  get timelineOuterClass() {
    return this.hasNoResults || this.hasNoVisibleResults
      ? "timeline-outer timeline-outer_empty"
      : "timeline-outer";
  }

  resetPagination() {
    const currentMonthKey = getCurrentMonthKey();
    const monthKeys = [
      ...new Set(
        this.filteredActivities
          .filter(hasActivitySchedule)
          .map((activity) => getActivityMonthKey(activity.activityDateTime))
          .filter(Boolean)
      )
    ];

    if (this.sortOrder === "oldest") {
      const currentAndPastMonths = monthKeys.filter(
        (monthKey) => monthKey.localeCompare(currentMonthKey) <= 0
      );
      const oldestMonth = monthKeys.length
        ? [...monthKeys].sort((first, second) => first.localeCompare(second))[0]
        : null;
      const visibleSet = new Set(currentAndPastMonths);

      if (oldestMonth) {
        visibleSet.add(oldestMonth);
      }

      this.visibleMonthKeys = visibleSet.size
        ? [...visibleSet].sort((first, second) => first.localeCompare(second))
        : [currentMonthKey];
      return;
    }

    const currentAndFutureMonths = monthKeys.filter(
      (monthKey) => monthKey.localeCompare(currentMonthKey) >= 0
    );
    const newestMonth = monthKeys.length
      ? [...monthKeys].sort((first, second) => second.localeCompare(first))[0]
      : null;
    const visibleSet = new Set(currentAndFutureMonths);

    if (newestMonth) {
      visibleSet.add(newestMonth);
    }

    this.visibleMonthKeys = visibleSet.size
      ? [...visibleSet].sort((first, second) => second.localeCompare(first))
      : [currentMonthKey];
  }

  handleSearch(event) {
    this.searchTerm = event.target.value;
    this.resetPagination();
  }

  closeActivityMenus() {
    this.workMenuOpen = false;
    this.interactionMenuOpen = false;
    this.removeDocumentClickListener();
  }

  syncDocumentClickListener() {
    if (this.workMenuOpen || this.interactionMenuOpen) {
      if (!this.documentClickListenerActive) {
        document.addEventListener("click", this.handleDocumentClick);
        this.documentClickListenerActive = true;
      }
      return;
    }

    this.removeDocumentClickListener();
  }

  removeDocumentClickListener() {
    if (!this.documentClickListenerActive) {
      return;
    }

    document.removeEventListener("click", this.handleDocumentClick);
    this.documentClickListenerActive = false;
  }

  handleDocumentClick = (event) => {
    const openMenuSelector = this.workMenuOpen
      ? ".timeline-split-button--work"
      : this.interactionMenuOpen
        ? ".timeline-split-button--interactions"
        : null;

    if (!openMenuSelector) {
      this.removeDocumentClickListener();
      return;
    }

    const openMenuRoot = this.template.querySelector(openMenuSelector);
    if (openMenuRoot?.contains(event.target)) {
      return;
    }

    this.closeActivityMenus();
  };

  handleWorkMenuToggle(event) {
    event.stopPropagation();
    this.workMenuOpen = !this.workMenuOpen;
    this.interactionMenuOpen = false;
    this.syncDocumentClickListener();
  }

  handleInteractionMenuToggle(event) {
    event.stopPropagation();
    this.interactionMenuOpen = !this.interactionMenuOpen;
    this.workMenuOpen = false;
    this.syncDocumentClickListener();
  }

  handleExternalToggle(event) {
    this.resetActivityPaging();
    this.customerOnlyMode = event.target.checked;
    this.isLoading = true;
    this.loadError = undefined;
    this.resetPagination();
  }

  handleNewTask() {
    this.closeActivityMenus();
    this.invokeActivityQuickAction("task");
  }

  handleLogACall() {
    this.closeActivityMenus();
    this.invokeActivityQuickAction("call");
  }

  handleNewMeeting() {
    this.closeActivityMenus();
    this.invokeActivityQuickAction("meeting");
  }

  invokeActivityQuickAction(actionKey) {
    if (!this.recordId || !this.recordObjectApiName) {
      return;
    }

    const quickActionApiName = buildActivityQuickActionApiName(
      this.recordObjectApiName,
      actionKey
    );

    if (!quickActionApiName) {
      return;
    }

    this.markPendingActivityActionRefresh();

    this[NavigationMixin.Navigate]({
      type: "standard__quickAction",
      attributes: {
        apiName: quickActionApiName
      },
      state: {
        recordId: this.recordId
      }
    });
  }

  handleFilterToggle(event) {
    const filterValue = event.currentTarget.dataset.filter;
    this.activeFilters = {
      ...this.activeFilters,
      [filterValue]: !this.activeFilters[filterValue]
    };
    this.resetPagination();
  }

  handleSortChange(event) {
    this.sortOrder = event.detail.value;
    this.resetPagination();
  }

  handleLoadMore() {
    if (this.hiddenMonthKeys.length) {
      this.visibleMonthKeys = [
        ...this.visibleMonthKeys,
        this.hiddenMonthKeys[0]
      ];
      return;
    }

    if (this.hasMoreActivities) {
      this.fetchNextActivityPage(this.activityLoadGeneration);
    }
  }

  handleToggleDateGroup(event) {
    event.stopPropagation();

    const groupId = event.currentTarget.getAttribute("data-group-id");
    if (!groupId) {
      return;
    }

    if (this.collapsedGroupKeyList.includes(groupId)) {
      this.collapsedGroupKeyList = this.collapsedGroupKeyList.filter(
        (collapsedGroupId) => collapsedGroupId !== groupId
      );
      return;
    }

    this.collapsedGroupKeyList = [...this.collapsedGroupKeyList, groupId];
  }

  handleToggleActivityDetails(event) {
    const activityId = event.currentTarget.dataset.activityId;
    if (!activityId) {
      return;
    }

    const isExpanded = !!this.expandedActivityIds[activityId];
    this.expandedActivityIds = {
      ...this.expandedActivityIds,
      [activityId]: !isExpanded
    };
  }

  handleRecordNavigate(event) {
    const isModifiedClick =
      event.metaKey || event.ctrlKey || event.shiftKey || event.button === 1;

    if (isModifiedClick) {
      return;
    }

    event.preventDefault();

    const recordId = event.currentTarget.dataset.recordId;
    const objectApiName = event.currentTarget.dataset.objectApiName;

    if (!recordId || !objectApiName) {
      return;
    }

    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId,
        objectApiName,
        actionName: "view"
      }
    });
  }

  handleRecordKeyDown(event) {
    if (event.key !== "Enter" && event.key !== " ") {
      return;
    }

    event.preventDefault();
    this.handleRecordNavigate(event);
  }

  handleFilterChange(event) {
    const field = event.target.dataset.field;
    const value = event.detail?.value ?? event.target.value;

    this.filterValues = {
      ...this.filterValues,
      [field]: value
    };
    this.resetPagination();
  }

  resetOwnerPicker() {
    this.filterValues = {
      ...this.filterValues,
      ownerPickerResetToken: (this.filterValues.ownerPickerResetToken || 0) + 1
    };
  }

  handleOwnerPickerChange(event) {
    const recordId = event.detail.recordId || "";

    if (!recordId) {
      this.resetOwnerPicker();
      return;
    }

    const selectedUsers = this.filterValues.ownerUsers || [];

    if (selectedUsers.some((user) => user.id === recordId)) {
      this.resetOwnerPicker();
      return;
    }

    this.pendingOwnerPicker = true;
    this.pendingUserPickerRecordId = recordId;
    this.resetOwnerPicker();
    this.resetPagination();
  }

  handleRemoveOwnerPill(event) {
    const userId = event.currentTarget.dataset.userId;

    this.filterValues = {
      ...this.filterValues,
      ownerUsers: (this.filterValues.ownerUsers || []).filter(
        (user) => user.id !== userId
      ),
      ownerPickerResetToken: (this.filterValues.ownerPickerResetToken || 0) + 1
    };
    this.resetPagination();
  }

  handleClearFilters() {
    this.filterValues = cloneEmptyFilters();
    this.activeFilterTab = "Work";
    this.resetPagination();
  }

  handleFilterTabChange(event) {
    this.activeFilterTab = event.target.value;
  }

  handleToggleFilterPanel() {
    this.isFilterPanelExpanded = !this.isFilterPanelExpanded;
  }

  handleTypeFilterChange(event) {
    const typeKey = event.target.dataset.type;
    const isChecked = event.target.checked;

    this.filterValues = {
      ...this.filterValues,
      selectedTypes: {
        ...this.filterValues.selectedTypes,
        [typeKey]: isChecked
      }
    };
    this.resetPagination();
  }

  matchesFilters(activity) {
    const filters = this.filterValues;

    if (
      filters.status &&
      !(activity.status || "")
        .toLowerCase()
        .includes(filters.status.toLowerCase())
    ) {
      return false;
    }

    if (
      !this.isWithinDateRange(
        activity.dateValue,
        filters.dueDateFrom,
        filters.dueDateTo
      )
    ) {
      return false;
    }

    if (!this.matchesSelectedOwners(activity, filters.ownerUsers)) {
      return false;
    }

    if (!this.matchesSelectedTypes(activity, filters.selectedTypes)) {
      return false;
    }

    return true;
  }

  matchesSelectedTypes(activity, selectedTypes = DEFAULT_SELECTED_TYPES) {
    const activityType = resolveFilterActivityType(activity.activityType);

    if (!FILTERABLE_TYPE_KEYS.includes(activityType)) {
      return true;
    }

    return selectedTypes[activityType] !== false;
  }

  matchesSelectedOwners(activity, selectedUsers) {
    if (!selectedUsers?.length) {
      return true;
    }

    const selectedIds = new Set(selectedUsers.map((user) => user.id));

    if (activity.ownerId && selectedIds.has(activity.ownerId)) {
      return true;
    }

    const ownerName = (activity.ownerName || "").toLowerCase();
    return selectedUsers.some((user) => {
      const selectedName = user.name.toLowerCase();
      return (
        ownerName.includes(selectedName) || selectedName.includes(ownerName)
      );
    });
  }

  isWithinDateRange(activityDate, fromDate, toDate) {
    if (!fromDate && !toDate) {
      return true;
    }

    if (!activityDate) {
      return false;
    }

    const dateValue = new Date(activityDate).getTime();

    if (fromDate && dateValue < new Date(fromDate).getTime()) {
      return false;
    }

    if (toDate && dateValue > new Date(toDate).getTime()) {
      return false;
    }

    return true;
  }
}