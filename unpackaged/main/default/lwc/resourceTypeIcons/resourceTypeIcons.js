import { iconPath } from 'c/rcIcons';

/**
 * resourceTypeIcons
 *
 * Shared JS module (no template) mapping a Resource_Type__c value to its
 * Diversify icon (inline SVG path from c/rcIcons — same brand set the Help
 * Center uses), short badge label, and primary-action verb. Mirrors the
 * nexsTopicIcons module pattern.
 *
 * 'Article' is NOT a Resource_Type__c value — it is the c/dsContentCard entry
 * for Knowledge articles (kind === 'article'), which have no resource type.
 */
const MAP = {
    PDF: { icon: 'documents', badge: 'PDF', action: 'View' },
    Form: { icon: 'edit', badge: 'Form', action: 'View' },
    Video: { icon: 'play', badge: 'Video', action: 'Watch' },
    Template: { icon: 'cube', badge: 'Template', action: 'View' },
    'External Link': { icon: 'link-out', badge: 'Link', action: 'Open' },
    // Lifecycle-specific verbs (Sign up / Watch) come from rcConstants.resourceAction.
    Webinar: { icon: 'presentation', badge: 'Webinar', action: 'View' },
    Article: { icon: 'question', badge: 'Article', action: 'Read' }
};

const FALLBACK = { icon: 'documents', badge: 'Resource', action: 'Open' };

export function typeMeta(resourceType) {
    const meta = MAP[resourceType] || FALLBACK;
    return { ...meta, iconPath: iconPath(meta.icon) };
}