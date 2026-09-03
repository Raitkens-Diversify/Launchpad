import { iconPath } from 'c/rcIcons';

/**
 * nexsTopicIcons
 *
 * Help Center topic icons, keyed by Help_Topics Data Category API name. A thin
 * keying layer over the c/rcIcons library (the single source of the inlined
 * Diversify icon paths — Untitled UI line set, 24x24 viewBox, stroke-width 2,
 * rendered with currentColor), the same shape resourceTypeIcons uses. This
 * module used to carry its own copies of six of those paths; they now live
 * only in rcIcons. Consumed by nexsHome (topic grid) and nexsArticleBrowser
 * (left nav).
 */
const TOPIC_ICON_KEYS = {
    Getting_Started: 'rocket',
    Cases_and_Tasks: 'clipboard',
    Households_and_Clients: 'users',
    Wizard_and_Envelopes: 'wand',
    ISAs_and_Investments: 'chart',
    Data_Model: 'dataflow'
};

/** Path data for a Help_Topics category's icon. Unmapped categories get
    rcIcons' question-mark fallback (categories authors add later). */
export function topicIconPath(categoryName) {
    return iconPath(TOPIC_ICON_KEYS[categoryName]);
}