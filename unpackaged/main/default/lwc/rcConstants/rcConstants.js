import { typeMeta } from 'c/resourceTypeIcons';

/**
 * rcConstants — the single client-side source for the Resource_Type__c
 * vocabulary (previously copied into four components with two divergent
 * option orders) and the ONE resource call-to-action rule (`resourceAction`),
 * plus `eventCta` — the events-surface layer over that rule for the
 * ResourceCenterService.WebinarItem shape (events list rows + the calendar
 * popover both consume it, so Sign up / Watch / "Recording coming soon" /
 * Add to calendar are decided in exactly one place).
 *
 * Server-side mirrors — change both together, and only when the picklist /
 * lifecycle changes:
 *   FILE_TYPES        ↔ ResourceAdminController.FILE_TYPES
 *   TYPE_WEBINAR and WEBINAR_STATUS_* ↔ WebinarLifecycle
 */

/**
 * The unified home's user-facing name (the Help & Resources app / the
 * unifiedLanding page) and the two crumbs every Resource Center trail starts
 * with: Help & Resources › Resource Center › … . `help` routes to the unified
 * home (resourceCenter's `helphome` → c/contextNav.goToHome), `home` to the
 * Resource Center front door (`rchome`).
 */
export const HELP_HOME_LABEL = 'Help & Resources';
export const CRUMB_HELP_HOME = 'help';
export const CRUMB_RC_HOME = 'home';
export function rcRootCrumbs() {
    return [
        { label: HELP_HOME_LABEL, key: CRUMB_HELP_HOME },
        { label: 'Resource Center', key: CRUMB_RC_HOME }
    ];
}

/** Resource_Type__c values, in the canonical display order. */
export const RESOURCE_TYPES = ['PDF', 'Form', 'Video', 'Template', 'External Link', 'Webinar'];

/** The subset backed by an uploaded file (download flows key on this). */
export const FILE_TYPES = ['PDF', 'Form', 'Template'];

export const TYPE_VIDEO = 'Video';
export const TYPE_EXTERNAL_LINK = 'External Link';
export const TYPE_WEBINAR = 'Webinar';
export const DEFAULT_TYPE = 'PDF';

/**
 * Webinar lifecycle vocabulary (server: WebinarLifecycle.UPCOMING / PAST /
 * RECORDED). Always read off a DTO's `webinarStatus` — never derived here.
 */
export const WEBINAR_STATUS_UPCOMING = 'Upcoming';
export const WEBINAR_STATUS_PAST = 'Past';
export const WEBINAR_STATUS_RECORDED = 'Recorded';

export function isFileType(resourceType) {
    return FILE_TYPES.includes(resourceType);
}

export function isWebinar(resourceType) {
    return resourceType === TYPE_WEBINAR;
}

/** ['A','B'] → combobox options; prepend entries for filter dropdowns. */
export function toOptions(values) {
    return values.map((v) => ({ label: v, value: v }));
}

/**
 * The ONE call-to-action rule for a resource. Takes any server DTO carrying
 * `resourceType` (plus `externalUrl` / `webinarStatus` / `registrationUrl`
 * where relevant — ResourceCard, ResourceHit, ResourceDetail all do) and
 * returns `{ action, href? }`:
 *   External Link with a URL       → Open, href = externalUrl
 *   Webinar, Upcoming, with a URL  → Sign up, href = registrationUrl
 *   Webinar, Recorded              → Watch (in-app detail, plays the recording)
 *   Webinar, otherwise             → View (detail says "recording coming soon")
 *   anything else                  → typeMeta(type).action
 * `href` present means the action leaves the site (hosts render an
 * <a target="_blank" rel="noopener noreferrer">); absent means open the detail
 * view in-app. Consumers: toContentItem (every card grid) and articleResources.
 */
export function resourceAction(r) {
    const type = r ? r.resourceType : undefined;
    const fallback = typeMeta(type).action;
    if (!r) {
        return { action: fallback };
    }
    if (type === TYPE_EXTERNAL_LINK && r.externalUrl) {
        return { action: fallback, href: r.externalUrl };
    }
    if (type === TYPE_WEBINAR) {
        if (r.webinarStatus === WEBINAR_STATUS_UPCOMING && r.registrationUrl) {
            return { action: 'Sign up', href: r.registrationUrl };
        }
        if (r.webinarStatus === WEBINAR_STATUS_RECORDED) {
            return { action: 'Watch' };
        }
    }
    return { action: fallback };
}

/**
 * Server resource DTO → c/dsContentCard item. Shared by every card grid
 * (resourceCategoryPage, unifiedLanding, the unified
 * search results). Accepts the ResourceCard shape (name/description) and the
 * search ResourceHit shape (title/subtitle). `href` is set only when the
 * action truly leaves the site (see resourceAction) — file-backed types keep
 * opening the detail view so download counts stay real; an External Link
 * without a URL degrades to open-in-app.
 */
export function toContentItem(r) {
    const { action, href } = resourceAction(r);
    return {
        kind: 'resource',
        id: r.id,
        title: r.name !== undefined ? r.name : r.title,
        subtitle: r.description !== undefined ? r.description : r.subtitle,
        routeKey: r.slug,
        resourceType: r.resourceType,
        action,
        href
    };
}

/**
 * The events surfaces' call-to-action for one webinar, derived from
 * resourceAction so status→verb branching lives in ONE function. Accepts the
 * events feed's WebinarItem (`status`, no `resourceType`) and, for symmetry,
 * any DTO carrying `webinarStatus`. Returns:
 *   primary          { kind: 'signup', label: 'Sign up', href }   — Upcoming with a URL
 *                    { kind: 'watch',  label: 'Watch recording' } — Recorded (in-app detail)
 *                    null                                         — nothing to do
 *   note             'Recording coming soon' for Past, else null (never a dead button)
 *   canAddToCalendar true only while Upcoming
 * Consumers: eventsPage (list rows + the calendar detail popover).
 */
export function eventCta(item) {
    if (!item) {
        return { primary: null, note: null, canAddToCalendar: false };
    }
    const status = item.status || item.webinarStatus;
    const { action, href } = resourceAction({
        resourceType: TYPE_WEBINAR,
        webinarStatus: status,
        registrationUrl: item.registrationUrl
    });
    let primary = null;
    if (action === 'Sign up') {
        primary = { kind: 'signup', label: 'Sign up', href };
    } else if (action === 'Watch') {
        primary = { kind: 'watch', label: 'Watch recording' };
    }
    return {
        primary,
        note: status === WEBINAR_STATUS_PAST ? 'Recording coming soon' : null,
        canAddToCalendar: status === WEBINAR_STATUS_UPCOMING
    };
}

/**
 * Whole minutes → "4 min" / "1 h 26 m" / "31 h 51 m". The webinar / event
 * duration formatter (agenda rows, the events page, the resource detail, and
 * the landing banner). Minutes are the grain the Apex sends; anything finer
 * would be false precision. Lives here (since 2026-09-04) so the Help Center
 * surfaces depend on no module outside their own package.
 */
export function formatDurationMinutes(minutes) {
    if (minutes === null || minutes === undefined || Number.isNaN(Number(minutes))) {
        return null;
    }
    const total = Math.max(0, Math.round(Number(minutes)));
    if (total < 60) {
        return `${total} min`;
    }
    const hours = Math.floor(total / 60);
    const rest = total % 60;
    return rest === 0 ? `${hours} h` : `${hours} h ${rest} m`;
}