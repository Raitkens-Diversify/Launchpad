import { LightningElement, api } from 'lwc';
import { localDateKey, formatDateKey } from 'c/dsDateBlock';

/**
 * dsCalendar — a month-grid calendar. Pure presentation, Apex-free, and
 * agnostic about what the events ARE: `kind` and `status` are opaque strings
 * handed back on selection and exposed as CSS hooks, never interpreted.
 *
 * @api events: [{ id, dateIso, title, kind, status }]
 *   dateIso is an instant (what an Apex Datetime serializes to). Cells are
 *   keyed by the LOCAL calendar day of that instant in the user's Salesforce
 *   timezone (c/dsDateBlock.localDateKey) — an event at 11 PM local stays on
 *   its own day even though its UTC date string already says tomorrow.
 * @api month: 'YYYY-MM'. Controlled by the host: prev / next / today emit
 *   `monthchange` and the host writes the prop back. Invalid/absent → today's
 *   month renders (nothing is ever blank).
 * @api layout: 'auto' | 'grid' | 'list'. A month grid is unusable at phone
 *   widths, so 'auto' swaps to a per-day list at ≤640px (the ui-standards §1
 *   mobile breakpoint). That swap is JS (matchMedia) rather than CSS because
 *   the two layouts have different keyboard models, not just different
 *   styling — the first width query in JS on these surfaces; keep it the only
 *   one unless another component genuinely needs a different DOM per width.
 * @api label: accessible name of the grid (default 'Calendar').
 *
 * Emits (plain, non-bubbling — the host listens on the element):
 *   monthchange { month: 'YYYY-MM', reason: 'prev' | 'next' | 'today' }
 *   eventselect { id, anchorRect: { top, left, width, height } }
 *               anchorRect is a plain copy of the chip's viewport rect so a
 *               host can anchor a popover to it (never a DOMRect — Locker).
 *   dayselect   { key: 'YYYY-MM-DD' } — a day with nothing on it was activated
 *
 * Keyboard (APG grid, roving tabindex on the day cells — the dsTabs recipe):
 *   Arrow keys move a day / a week; Home / End jump to the row's ends;
 *   PageUp / PageDown ask the host for the previous / next month and refocus
 *   the same day number there; Enter / Space on a day focuses its first event
 *   chip (or fires dayselect when it has none). Only the active day's chips
 *   are tab stops, so Tab walks that day's events and then leaves the grid.
 *   Enter on a chip is a native click → eventselect.
 *
 * Calendar arithmetic is done on civil dates via Date.UTC — never
 * `new Date(y, m, d)`, which is browser-local midnight and shifts a day when
 * formatted in the user's Salesforce zone (see c/dsDateBlock.formatDateKey).
 * Weeks start on Sunday (US convention; the org's audience is US-only).
 */
const MONTH_RE = /^(\d{4})-(0[1-9]|1[0-2])$/;
const KEY_RE = /^(\d{4})-(\d{2})-(\d{2})$/;
const CHIP_CAP = 3;
const NARROW_QUERY = '(max-width: 640px)';
/** 2026-02-01 was a Sunday — any known Sunday seeds the weekday header row. */
const KNOWN_SUNDAY = { y: 2026, m: 2, d: 1 };
const DAY_LABEL = { weekday: 'long', month: 'long', day: 'numeric', year: 'numeric' };

function pad(n) {
    return String(n).padStart(2, '0');
}
function keyOf(y, m, d) {
    return `${y}-${pad(m)}-${pad(d)}`;
}
function monthKeyOf(y, m) {
    return `${y}-${pad(m)}`;
}
function parseMonth(value) {
    const m = MONTH_RE.exec(value || '');
    return m ? { y: Number(m[1]), m: Number(m[2]) } : null;
}
function parseKey(key) {
    const m = KEY_RE.exec(key || '');
    return m ? { y: Number(m[1]), m: Number(m[2]), d: Number(m[3]) } : null;
}
function daysInMonth(y, m) {
    return new Date(Date.UTC(y, m, 0)).getUTCDate();
}
function firstWeekday(y, m) {
    return new Date(Date.UTC(y, m - 1, 1)).getUTCDay();
}
function shiftMonth(ym, delta) {
    const total = ym.y * 12 + (ym.m - 1) + delta;
    return { y: Math.floor(total / 12), m: ((total % 12) + 12) % 12 + 1 };
}
function shiftDay(key, delta) {
    const p = parseKey(key);
    if (!p) {
        return null;
    }
    const d = new Date(Date.UTC(p.y, p.m - 1, p.d + delta));
    return keyOf(d.getUTCFullYear(), d.getUTCMonth() + 1, d.getUTCDate());
}
function monthOf(key) {
    return key ? key.slice(0, 7) : null;
}
/** Opaque status → CSS modifier suffix ('Recorded' → 'recorded'). */
function statusSlug(status) {
    return String(status == null ? '' : status)
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, '-')
        .replace(/^-|-$/g, '');
}
function rectOf(el) {
    const r = el && typeof el.getBoundingClientRect === 'function'
        ? el.getBoundingClientRect() : null;
    return r
        ? { top: r.top, left: r.left, width: r.width, height: r.height }
        : { top: 0, left: 0, width: 0, height: 0 };
}

export default class DsCalendar extends LightningElement {
    @api events = [];
    @api label = 'Calendar';

    _month;
    _layout = 'auto';
    _expandedKey = null;
    _activeKey = null;
    /** A day outside the rendered grid that a key press asked for; focused
        once the host re-renders the month that contains it. */
    _pendingFocusKey = null;
    _focusAfterRender = null;
    _narrow = false;
    _mq = null;
    _mqHandler = null;

    @api
    get month() {
        return this._month;
    }
    set month(value) {
        if (value === this._month) {
            return;
        }
        this._month = value;
        this._expandedKey = null;
        if (this._pendingFocusKey && this.gridKeys.includes(this._pendingFocusKey)) {
            this._activeKey = this._pendingFocusKey;
            this._focusAfterRender = this._pendingFocusKey;
            this._pendingFocusKey = null;
        } else {
            this._activeKey = null;
        }
    }

    @api
    get layout() {
        return this._layout;
    }
    set layout(value) {
        this._layout = value === 'grid' || value === 'list' ? value : 'auto';
    }

    // ---- lifecycle -----------------------------------------------------------

    connectedCallback() {
        if (typeof window !== 'undefined' && typeof window.matchMedia === 'function') {
            this._mq = window.matchMedia(NARROW_QUERY);
            this._narrow = Boolean(this._mq && this._mq.matches);
            this._mqHandler = (e) => {
                this._narrow = Boolean(e && e.matches);
            };
            if (this._mq && typeof this._mq.addEventListener === 'function') {
                this._mq.addEventListener('change', this._mqHandler);
            } else if (this._mq && typeof this._mq.addListener === 'function') {
                this._mq.addListener(this._mqHandler);
            }
        }
    }

    disconnectedCallback() {
        if (this._mq && this._mqHandler) {
            if (typeof this._mq.removeEventListener === 'function') {
                this._mq.removeEventListener('change', this._mqHandler);
            } else if (typeof this._mq.removeListener === 'function') {
                this._mq.removeListener(this._mqHandler);
            }
        }
        this._mq = null;
        this._mqHandler = null;
    }

    renderedCallback() {
        if (this._focusAfterRender) {
            const key = this._focusAfterRender;
            this._focusAfterRender = null;
            this.focusCell(key);
        }
    }

    // ---- month / today -------------------------------------------------------

    get todayKey() {
        return localDateKey(new Date());
    }

    get resolvedMonth() {
        return parseMonth(this._month) || parseMonth(monthOf(this.todayKey));
    }

    get monthKey() {
        const { y, m } = this.resolvedMonth;
        return monthKeyOf(y, m);
    }

    get monthTitle() {
        return formatDateKey(this.monthKey, { month: 'long', year: 'numeric' });
    }

    get isList() {
        return this._layout === 'list' || (this._layout === 'auto' && this._narrow);
    }

    // ---- grid model ----------------------------------------------------------

    /** Every rendered day key, Sunday-start, leading/trailing fill included. */
    get gridKeys() {
        const { y, m } = this.resolvedMonth;
        const leading = firstWeekday(y, m);
        const days = daysInMonth(y, m);
        const trailing = (7 - ((leading + days) % 7)) % 7;
        const total = leading + days + trailing;
        const start = shiftDay(keyOf(y, m, 1), -leading);
        const keys = [];
        for (let i = 0; i < total; i++) {
            keys.push(shiftDay(start, i));
        }
        return keys;
    }

    /** Events bucketed by local calendar day. */
    get byDay() {
        const map = new Map();
        (this.events || []).forEach((ev) => {
            const key = ev ? localDateKey(ev.dateIso) : null;
            if (!key) {
                return;
            }
            if (!map.has(key)) {
                map.set(key, []);
            }
            map.get(key).push(ev);
        });
        return map;
    }

    /** The one day holding tabindex="0": the last day moved to, else today
        when it is on screen, else the 1st of the month. */
    get activeKey() {
        const keys = this.gridKeys;
        if (this._activeKey && keys.includes(this._activeKey)) {
            return this._activeKey;
        }
        const today = this.todayKey;
        return monthOf(today) === this.monthKey ? today : this.monthKey + '-01';
    }

    get weekdays() {
        const out = [];
        for (let i = 0; i < 7; i++) {
            const key = keyOf(KNOWN_SUNDAY.y, KNOWN_SUNDAY.m, KNOWN_SUNDAY.d + i);
            out.push({
                key: String(i),
                short: formatDateKey(key, { weekday: 'short' }),
                long: formatDateKey(key, { weekday: 'long' })
            });
        }
        return out;
    }

    decorateChip(ev, active) {
        const slug = statusSlug(ev.status);
        return {
            id: ev.id,
            title: ev.title,
            status: ev.status,
            ariaLabel: ev.status ? `${ev.title}, ${ev.status}` : ev.title,
            cssClass: 'ds-cal__chip' + (slug ? ` ds-cal__chip--${slug}` : ''),
            tabIndex: active ? '0' : '-1'
        };
    }

    get cells() {
        const byDay = this.byDay;
        const today = this.todayKey;
        const active = this.activeKey;
        const monthKey = this.monthKey;
        return this.gridKeys.map((key) => {
            const all = byDay.get(key) || [];
            const expanded = key === this._expandedKey;
            const shown = expanded ? all : all.slice(0, CHIP_CAP);
            const inMonth = monthOf(key) === monthKey;
            const isToday = key === today;
            const isActive = key === active;
            const hidden = all.length - shown.length;
            const cssClass = [
                'ds-cal__day',
                inMonth ? '' : 'ds-cal__day--outside',
                isToday ? 'ds-cal__day--today' : '',
                key < today ? 'ds-cal__day--past' : '',
                all.length ? 'ds-cal__day--has-events' : ''
            ].filter(Boolean).join(' ');
            const count = all.length === 1 ? '1 event' : `${all.length} events`;
            return {
                key,
                dayNumber: parseKey(key).d,
                inMonth,
                isToday,
                isActive,
                tabIndex: isActive ? '0' : '-1',
                ariaSelected: isActive ? 'true' : 'false',
                ariaCurrent: isToday ? 'date' : 'false',
                ariaLabel: `${formatDateKey(key, DAY_LABEL)}, ${all.length ? count : 'no events'}`,
                cssClass,
                events: shown.map((ev) => this.decorateChip(ev, isActive)),
                hasHidden: hidden > 0,
                moreLabel: `+${hidden} more`,
                moreAriaLabel: `Show ${hidden} more on ${formatDateKey(key, DAY_LABEL)}`
            };
        });
    }

    get rows() {
        const cells = this.cells;
        const rows = [];
        for (let i = 0; i < cells.length; i += 7) {
            rows.push({ key: String(i / 7), cells: cells.slice(i, i + 7) });
        }
        return rows;
    }

    // ---- list model (narrow layout) ------------------------------------------

    get dayGroups() {
        const byDay = this.byDay;
        const monthKey = this.monthKey;
        return [...byDay.keys()]
            .filter((key) => monthOf(key) === monthKey)
            .sort()
            .map((key) => ({
                key,
                dateIso: byDay.get(key)[0].dateIso,
                label: formatDateKey(key, DAY_LABEL),
                events: byDay.get(key).map((ev) => this.decorateChip(ev, true))
            }));
    }

    get hasDayGroups() {
        return this.dayGroups.length > 0;
    }

    // ---- month navigation ----------------------------------------------------

    get prevLabel() {
        const { y, m } = shiftMonth(this.resolvedMonth, -1);
        return `Previous month, ${formatDateKey(monthKeyOf(y, m), { month: 'long', year: 'numeric' })}`;
    }

    get nextLabel() {
        const { y, m } = shiftMonth(this.resolvedMonth, 1);
        return `Next month, ${formatDateKey(monthKeyOf(y, m), { month: 'long', year: 'numeric' })}`;
    }

    emitMonth(ym, reason) {
        const month = monthKeyOf(ym.y, ym.m);
        if (month === this.monthKey) {
            return;
        }
        this.dispatchEvent(new CustomEvent('monthchange', { detail: { month, reason } }));
    }

    handlePrev() {
        this.emitMonth(shiftMonth(this.resolvedMonth, -1), 'prev');
    }

    handleNext() {
        this.emitMonth(shiftMonth(this.resolvedMonth, 1), 'next');
    }

    handleToday() {
        const today = parseMonth(monthOf(this.todayKey));
        this.emitMonth(today, 'today');
    }

    // ---- grid interaction ----------------------------------------------------

    focusCell(key) {
        const el = this.template.querySelector(`[data-key="${key}"][role="gridcell"]`);
        if (el && typeof el.focus === 'function') {
            el.focus();
        }
    }

    /** Move the roving tab stop (and focus) to a day; days off the rendered
        grid ask the host for their month first. */
    moveTo(key) {
        if (!key) {
            return;
        }
        if (this.gridKeys.includes(key)) {
            this._activeKey = key;
            this.focusCell(key);
            return;
        }
        this._pendingFocusKey = key;
        const target = parseKey(key);
        this.emitMonth({ y: target.y, m: target.m }, key < this.monthKey ? 'prev' : 'next');
    }

    /** Enter/Space on a day: into its first chip, or dayselect when empty. */
    activateCell(key) {
        this._activeKey = key;
        const chip = this.template.querySelector(`[data-key="${key}"][role="gridcell"] .ds-cal__chip`);
        if (chip) {
            chip.focus();
            return;
        }
        this.dispatchEvent(new CustomEvent('dayselect', { detail: { key } }));
    }

    handleCellKeydown(event) {
        const key = event.currentTarget.dataset.key;
        const fromCell = event.target === event.currentTarget;
        const keys = this.gridKeys;
        const idx = keys.indexOf(key);
        let target = null;
        switch (event.key) {
            case 'ArrowLeft':
                target = shiftDay(key, -1);
                break;
            case 'ArrowRight':
                target = shiftDay(key, 1);
                break;
            case 'ArrowUp':
                target = shiftDay(key, -7);
                break;
            case 'ArrowDown':
                target = shiftDay(key, 7);
                break;
            case 'Home':
                target = keys[idx - (idx % 7)];
                break;
            case 'End':
                target = keys[idx - (idx % 7) + 6];
                break;
            case 'PageUp':
            case 'PageDown': {
                const day = parseKey(key).d;
                const ym = shiftMonth(this.resolvedMonth, event.key === 'PageUp' ? -1 : 1);
                target = keyOf(ym.y, ym.m, Math.min(day, daysInMonth(ym.y, ym.m)));
                break;
            }
            case 'Enter':
            case ' ':
                // A chip or "+N more" button handles its own Enter/Space
                // (native click); only the cell itself activates.
                if (!fromCell) {
                    return;
                }
                event.preventDefault();
                this.activateCell(key);
                return;
            default:
                return;
        }
        event.preventDefault();
        this.moveTo(target);
    }

    handleCellClick(event) {
        const key = event.currentTarget.dataset.key;
        this._activeKey = key;
        this.dispatchEvent(new CustomEvent('dayselect', { detail: { key } }));
    }

    handleChipClick(event) {
        event.stopPropagation();
        const { id, key } = event.currentTarget.dataset;
        if (key) {
            this._activeKey = key;
        }
        this.dispatchEvent(new CustomEvent('eventselect', {
            detail: { id, anchorRect: rectOf(event.currentTarget) }
        }));
    }

    handleMoreClick(event) {
        event.stopPropagation();
        const key = event.currentTarget.dataset.key;
        this._activeKey = key;
        this._expandedKey = this._expandedKey === key ? null : key;
    }
}