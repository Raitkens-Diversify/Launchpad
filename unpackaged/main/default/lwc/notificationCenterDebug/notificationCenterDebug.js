/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 */
import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getDigestPreview from "@salesforce/apex/NotificationCenterDebugController.getDigestPreview";
import triggerDigest from "@salesforce/apex/NotificationCenterDebugController.triggerDigest";
import {
  formatRelativeTime,
  getChannelBadge,
  getLogStatusStyle,
  getModeLabelClass,
  ICON,
  isVisibleChannel,
  OBJECT_TYPE,
  reduceError
} from "c/notificationCenterUtils";

const OBJECT_SECTIONS = Object.freeze([
  { objectType: OBJECT_TYPE.CASE, label: "Case" },
  { objectType: OBJECT_TYPE.TASK, label: "Task" },
  { objectType: OBJECT_TYPE.EVENT, label: "Event" }
]);
const DIGEST_SOURCE_RECORD_LIMIT = 10;

export default class NotificationCenterDebug extends LightningElement {
  icons = ICON;
  errorMessage = "";
  previewByObjectType = {};
  loadingByObjectType = {};
  triggeringObjectType = null;

  connectedCallback() {
    OBJECT_SECTIONS.forEach((section) => {
      this.loadPreview(section.objectType);
    });
  }

  @api
  refresh() {
    return Promise.all(
      OBJECT_SECTIONS.map((section) => this.loadPreview(section.objectType))
    );
  }

  get objectSections() {
    return OBJECT_SECTIONS.map((section) => {
      const rawItems = this.previewByObjectType[section.objectType] || [];
      const isGroupedView = this.isGroupedObjectType(section.objectType);
      const items = isGroupedView
        ? this.buildGroupedItems(rawItems)
        : rawItems.map((item) => this.decorateItem(item));
      const isLoading = this.loadingByObjectType[section.objectType] === true;
      const isTriggering = this.triggeringObjectType === section.objectType;
      const emailCount = rawItems.filter((item) => item.channel === "Email").length;
      const inAppCount = rawItems.filter((item) => item.channel === "In_App").length;
      const sourceRecordCount = new Set(
        rawItems.map((item) => item.sourceRecordId).filter(Boolean)
      ).size;

      return {
        ...section,
        items,
        isGroupedView,
        hasItems: items.length > 0,
        isLoading,
        isTriggering,
        isTriggerDisabled: isLoading || isTriggering,
        triggerLabel: `Trigger ${section.label} digest`,
        tableLabel: `${section.label} digest preview`,
        summaryLabel: this.buildSummaryLabel(
          section.objectType,
          rawItems.length,
          sourceRecordCount,
          emailCount,
          inAppCount
        )
      };
    });
  }

  isGroupedObjectType(objectType) {
    return objectType === OBJECT_TYPE.CASE || objectType === OBJECT_TYPE.TASK;
  }

  buildGroupedItems(rawItems) {
    const groupsBySourceRecord = new Map();

    rawItems.forEach((item) => {
      const sourceRecordId = item.sourceRecordId || item.id;
      const existingGroup = groupsBySourceRecord.get(sourceRecordId);

      if (!existingGroup) {
        groupsBySourceRecord.set(sourceRecordId, {
          id: sourceRecordId,
          sourceRecordId,
          title: item.title,
          body: item.body,
          frequency: item.frequency,
          createdAt: item.createdAt,
          channelLogs: []
        });
      }

      if (isVisibleChannel(item.channel)) {
        groupsBySourceRecord.get(sourceRecordId).channelLogs.push(this.decorateItem(item));
      }
    });

    return Array.from(groupsBySourceRecord.values()).map((group) =>
      this.decorateGroupItem(group)
    );
  }

  decorateGroupItem(group) {
    const frequencyClass = getModeLabelClass(group.frequency);
    const sortedChannelLogs = [...group.channelLogs].sort((left, right) =>
      left.channelLabel.localeCompare(right.channelLabel)
    );

    return {
      id: group.id,
      isGroup: true,
      titleLabel: group.title || "Untitled notification",
      bodyLabel: group.body || "No body",
      sourceRecordLabel: this.formatSourceRecordLabel(group.sourceRecordId),
      frequencyLabel: group.frequency || "Unknown",
      frequencyClass,
      createdLabel: formatRelativeTime(group.createdAt),
      channelLogs: sortedChannelLogs,
      channelSummaryLabel: sortedChannelLogs.map((entry) => entry.channelLabel).join(", ")
    };
  }

  formatSourceRecordLabel(sourceRecordId) {
    if (!sourceRecordId) {
      return "Unknown record";
    }

    if (sourceRecordId.length <= 15) {
      return sourceRecordId;
    }

    return `${sourceRecordId.slice(0, 8)}...${sourceRecordId.slice(-4)}`;
  }

  buildSummaryLabel(objectType, logCount, sourceRecordCount, emailCount, inAppCount) {
    const assignmentSuffix =
      objectType === OBJECT_TYPE.CASE || objectType === OBJECT_TYPE.TASK
        ? " assigned to you"
        : "";
    const channelSummary = [];

    if (emailCount > 0) {
      channelSummary.push(`${emailCount} Email`);
    }

    if (inAppCount > 0) {
      channelSummary.push(`${inAppCount} In App`);
    }

    const channelLabel =
      channelSummary.length > 0 ? ` (${channelSummary.join(", ")})` : "";

    if (sourceRecordCount > 0) {
      return `${logCount} digest log(s) from ${sourceRecordCount} of ${DIGEST_SOURCE_RECORD_LIMIT} most recent ${objectType} records${assignmentSuffix}${channelLabel}`;
    }

    return `${logCount} of ${DIGEST_SOURCE_RECORD_LIMIT} most recent digest logs for ${objectType}${assignmentSuffix}${channelLabel}`;
  }

  handleTriggerDigest = async (event) => {
    const objectType = event.currentTarget.dataset.objectType;
    this.triggeringObjectType = objectType;
    this.errorMessage = "";

    try {
      const result = await triggerDigest({ objectType });
      this.previewByObjectType = {
        ...this.previewByObjectType,
        [objectType]: result.items || []
      };

      this.dispatchEvent(
        new ShowToastEvent({
          title: "Digest delivery started",
          message: `Published ${result.publishedEventCount} individual notification log(s) for ${objectType} email and in-app delivery. Refresh the preview after delivery completes.`,
          variant: "success"
        })
      );

      await this.loadPreview(objectType);
    } catch (error) {
      this.errorMessage = reduceError(error);
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Unable to trigger digest",
          message: this.errorMessage,
          variant: "error"
        })
      );
    } finally {
      this.triggeringObjectType = null;
    }
  };

  async loadPreview(objectType) {
    this.loadingByObjectType = {
      ...this.loadingByObjectType,
      [objectType]: true
    };

    try {
      const items = await getDigestPreview({ objectType });
      this.previewByObjectType = {
        ...this.previewByObjectType,
        [objectType]: items || []
      };
    } catch (error) {
      this.errorMessage = reduceError(error);
    } finally {
      this.loadingByObjectType = {
        ...this.loadingByObjectType,
        [objectType]: false
      };
    }
  }

  decorateItem(item) {
    const statusStyle = getLogStatusStyle(item.status);
    const frequencyClass = getModeLabelClass(item.frequency);
    const showChannelPill = isVisibleChannel(item.channel);
    const channelBadge = showChannelPill ? getChannelBadge(item.channel) : null;

    return {
      id: item.id,
      isGroup: false,
      sourceRecordId: item.sourceRecordId,
      titleLabel: item.title || "Untitled notification",
      bodyLabel: item.body || "No body",
      channelKey: item.channel,
      showChannelPill,
      channelLabel: channelBadge?.label || "",
      channelClass: channelBadge?.cssClass || "",
      frequencyLabel: item.frequency || "Unknown",
      frequencyClass,
      statusLabel: statusStyle.label,
      statusClass: statusStyle.cssClass,
      createdLabel: formatRelativeTime(item.createdAt)
    };
  }
}