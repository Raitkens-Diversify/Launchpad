/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-16
 */
import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import getDashboard from "@salesforce/apex/NotificationCenterController.getDashboard";
import { openRecordInNewTab } from "c/recordNavigationUtils";
import {
  DASHBOARD_KPI_ICONS,
  DASHBOARD_KPI_ICON_WRAP,
  CHANNEL,
  buildChannelPills,
  deriveAggregatedStatus,
  deriveChangeType,
  formatRelativeTime,
  getDashboardStatusStyle,
  getDeliveryBarStyle,
  groupRecentEvents,
  ICON,
  reduceError,
  sortChannels,
  dispatchNotificationCenterViewReady
} from "c/notificationCenterUtils";

export default class NotificationCenterDashboard extends NavigationMixin(
  LightningElement
) {
  icons = ICON;
  dashboardStats = {
    deliveredTodayCount: 0,
    queuedCount: 0,
    activeHouseholdCount: 0
  };
  channelDelivery = [];
  recentEvents = [];
  isLoading = true;
  errorMessage = "";
  hasDispatchedViewReady = false;

  connectedCallback() {
    this.loadDashboard();
  }

  get kpiCards() {
    const queuedCount = this.dashboardStats.queuedCount || 0;
    const nextDigestRunLabel = this.dashboardStats.nextDigestRunLabel;
    const digestTimezoneAbbreviation =
      this.dashboardStats.digestTimezoneAbbreviation || "";
    const digestTimezoneLabel = this.dashboardStats.digestTimezoneLabel || "";
    let queuedSub = "none queued";

    if (queuedCount > 0 && nextDigestRunLabel) {
      queuedSub = digestTimezoneAbbreviation
        ? `next: ${nextDigestRunLabel} ${digestTimezoneAbbreviation}`
        : `next: ${nextDigestRunLabel}`;
    } else if (queuedCount > 0) {
      queuedSub = "awaiting next digest run";
    }

    return [
      {
        id: "delivered-today",
        label: "Delivered Today",
        value: this.dashboardStats.deliveredTodayCount || 0,
        sub: "across all channels",
        subTitle: "",
        icon: DASHBOARD_KPI_ICONS.DELIVERED_TODAY,
        iconClass: DASHBOARD_KPI_ICON_WRAP.DELIVERED_TODAY
      },
      {
        id: "queued-digest",
        label: "Queued for Digest",
        value: queuedCount,
        sub: queuedSub,
        subTitle: digestTimezoneLabel
          ? `Digest delivery uses organization time (${digestTimezoneLabel}).`
          : "",
        icon: DASHBOARD_KPI_ICONS.QUEUED_DIGEST,
        iconClass: DASHBOARD_KPI_ICON_WRAP.QUEUED_DIGEST
      },
      {
        id: "active-households",
        label: "Active Households",
        value: this.dashboardStats.activeHouseholdCount || 0,
        sub: "with FA Team assigned",
        subTitle: "",
        icon: DASHBOARD_KPI_ICONS.ACTIVE_HOUSEHOLDS,
        iconClass: DASHBOARD_KPI_ICON_WRAP.ACTIVE_HOUSEHOLDS
      }
    ];
  }

  get deliveryRows() {
    const rowByChannel = new Map(
      (this.channelDelivery || []).map((row) => [row.channelKey, row])
    );

    return sortChannels([...rowByChannel.keys()]).map((channelKey) => {
      const row = rowByChannel.get(channelKey);
      const style =
        getDeliveryBarStyle(channelKey) ||
        getDeliveryBarStyle(CHANNEL.IN_APP);

      return {
        ...row,
        icon: style.icon,
        iconClass: style.iconClass,
        barClass: style.barClass,
        barStyle: `width: ${row.percent || 0}%`
      };
    });
  }

  get hasRecentEvents() {
    return this.recentEvents.length > 0;
  }

  get showInitialViewSkeleton() {
    return this.isLoading && !this.hasDispatchedViewReady;
  }

  loadDashboard = async ({ silent = false } = {}) => {
    if (!silent) {
      this.isLoading = true;
    }

    this.errorMessage = "";

    try {
      const result = await getDashboard();
      this.dashboardStats = result?.stats || this.dashboardStats;
      this.channelDelivery = result?.channelDelivery || [];
      const groupedEvents = groupRecentEvents(result?.recentEvents || []);
      this.recentEvents = groupedEvents.map((item) => this.decorateRecentEvent(item));
    } catch (error) {
      this.errorMessage = reduceError(error);
    } finally {
      if (!silent) {
        this.isLoading = false;
        this.dispatchViewReadyOnce();
      }
    }
  };

  dispatchViewReadyOnce() {
    if (this.hasDispatchedViewReady) {
      return;
    }

    this.hasDispatchedViewReady = true;
    dispatchNotificationCenterViewReady(this);
  }

  @api
  refresh() {
    return this.loadDashboard({ silent: true });
  }

  decorateRecentEvent(item) {
    const channelItems = item.channelItems || [item];
    const aggregatedStatus = deriveAggregatedStatus(channelItems);
    const statusStyle = getDashboardStatusStyle(aggregatedStatus);
    const relatedRecordId = item.targetRecordId || item.sourceRecordId;
    const hasRelatedRecordLink = Boolean(relatedRecordId);
    const changeType = deriveChangeType(item.title, item.changeContext);
    const hasHousehold = Boolean(item.householdName);
    const channelPills = buildChannelPills(item.channels || [item.channel]);
    const channelSummaryLabel = channelPills.map((pill) => pill.label).join(", ");

    return {
      ...item,
      showHouseholdContext: hasHousehold,
      contextLabel: hasHousehold ? item.householdName : "User default",
      sourceType: item.sourceType,
      changeTypeLabel: changeType,
      recipientLabel: item.recipientName || "Unknown recipient",
      channelPills,
      channelSummaryLabel,
      showChannelPills: channelPills.length > 0,
      statusIcon: statusStyle.icon,
      statusIconClass: statusStyle.iconClass,
      timeLabel: formatRelativeTime(item.eventAt),
      relatedRecordId,
      hasRecordLink: hasRelatedRecordLink,
      rowClass: hasRelatedRecordLink
        ? "activity-row activity-row--clickable"
        : "activity-row",
      rowAriaLabel: hasRelatedRecordLink
        ? `Open related ${item.sourceType || "record"} in a new workspace tab`
        : null
    };
  }

  handleRecentEventNavigate = (event) => {
    event.preventDefault();
    openRecordInNewTab(this, event.currentTarget.dataset.recordId);
  };

  handleRecentEventNavigateKeyDown = (event) => {
    if (event.key !== "Enter" && event.key !== " ") {
      return;
    }

    event.preventDefault();
    this.handleRecentEventNavigate(event);
  };
}