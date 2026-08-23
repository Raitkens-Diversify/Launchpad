/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-08
 *
 * Canonical metadata order:
 * 1. Source type (icon + label)
 * 2. Change type (optional)
 * 3. Delivery mode (icon + label)
 * 4. Digest frequency (optional, digest rules)
 * 5. Quiet hours (optional)
 * 6. Household (icon + label)
 */
import { LightningElement, api } from "lwc";
import {
  buildSourceTypeDisplay,
  getDigestFrequencyDisplayLabel,
  getFrequencyLabel,
  getModeIcon,
  getModeIconClass,
  getModeLabelClass,
  getChannelBadge,
  ICON,
  isDigestFrequency,
  MODE_ICON
} from "c/notificationCenterUtils";

export default class NotificationCenterMetaStrip extends LightningElement {
  @api sourceType;
  @api changeTypeLabel;
  @api showChangeType = false;
  @api frequency;
  @api digestFrequency;
  @api digestFrequencyHour;
  @api quietHoursLabel;
  @api showQuietHours = false;
  @api quietHoursClass = "div-meta-strip__quiet-hours";
  @api householdLabel;
  @api showHousehold = false;
  @api suppressSourceType = false;
  @api variant = "default";
  @api channel;
  @api showChannel = false;

  homeIcon = ICON.HOME;
  modeIcons = MODE_ICON;

  get isTableVariant() {
    return this.variant === "table";
  }

  get metaStripClass() {
    return this.isTableVariant
      ? "div-meta-strip div-meta-strip--table"
      : "div-meta-strip";
  }

  get sourceTypeDisplay() {
    return buildSourceTypeDisplay(this.sourceType);
  }

  get sourceTypeIcon() {
    return this.sourceTypeDisplay.icon;
  }

  get sourceTypeIconClass() {
    return this.sourceTypeDisplay.iconClass;
  }

  get sourceTypeLabel() {
    return this.sourceTypeDisplay.label;
  }

  get showSourceTypeSegment() {
    return !this.suppressSourceType && Boolean(this.sourceType);
  }

  get showChangeTypeSegment() {
    return this.showChangeType && Boolean(this.changeTypeLabel);
  }

  get showModeSegment() {
    return Boolean(this.frequency);
  }

  get showDigestFrequencySegment() {
    return this.isDigestMode && Boolean(this.digestFrequencyLabel);
  }

  get showQuietHoursSegment() {
    return this.showQuietHours && Boolean(this.quietHoursLabel);
  }

  get showHouseholdSegment() {
    return this.showHousehold && Boolean(this.householdLabel);
  }

  get showChannelSegment() {
    return (
      this.isTableVariant &&
      this.showChannel &&
      Boolean(this.channel)
    );
  }

  get changeTypeItemClass() {
    return this.isTableVariant
      ? "div-meta-strip__item div-meta-strip__label"
      : "div-meta-strip__item div-meta-strip__muted";
  }

  get showChangeTypeDivider() {
    return this.showSourceTypeSegment;
  }

  get showModeDivider() {
    return this.showSourceTypeSegment || this.showChangeTypeSegment;
  }

  get showQuietHoursDivider() {
    return (
      this.showSourceTypeSegment ||
      this.showChangeTypeSegment ||
      this.showModeSegment ||
      this.showDigestFrequencySegment
    );
  }

  get showDigestFrequencyDivider() {
    return (
      this.showSourceTypeSegment ||
      this.showChangeTypeSegment ||
      this.showModeSegment
    );
  }

  get showHouseholdDivider() {
    return (
      this.showSourceTypeSegment ||
      this.showChangeTypeSegment ||
      this.showModeSegment ||
      this.showDigestFrequencySegment ||
      this.showQuietHoursSegment
    );
  }

  get showChannelDivider() {
    return this.showModeSegment;
  }

  get frequencyLabel() {
    return getFrequencyLabel(this.frequency);
  }

  get digestFrequencyLabel() {
    return getDigestFrequencyDisplayLabel(
      this.digestFrequency,
      this.digestFrequencyHour
    );
  }

  get modeLabelClassComputed() {
    return this.isTableVariant
      ? "div-mode-label div-mode-label--table"
      : getModeLabelClass(this.frequency);
  }

  get modeIconClassComputed() {
    return this.isTableVariant
      ? "div-mode-label__icon div-mode-label__icon--table"
      : getModeIconClass(this.frequency);
  }

  get modeIcon() {
    return getModeIcon(this.frequency);
  }

  get isDigestMode() {
    return isDigestFrequency(this.frequency);
  }

  get channelLabelText() {
    const badgeLabel = getChannelBadge(this.channel).label;
    const displayLabels = {
      APP: "In-App",
      EMAIL: "Email",
      SMS: "SMS"
    };

    return displayLabels[badgeLabel] || badgeLabel;
  }
}