/**
 * uatCardUtil — shared card/date presentation helpers for the UAT tester
 * views (uatDashboard, uatQueue, uatPool). Pure module, no template — the
 * envelopeFormSchema pattern: one owner for anything two components would
 * otherwise copy. Extracted from uatDashboard's module-privates when the
 * queue/pool redesign became the second consumer.
 */

/** Salesforce Date fields arrive as 'YYYY-MM-DD'; new Date(iso) would parse
 *  them as UTC midnight and show the previous day in western timezones.
 *  Datetime fields arrive as full ISO instants — those go through new Date(),
 *  whose parse is correct for them. Either way an unparseable value returns
 *  null, never an Invalid Date: Invalid Date is truthy, and it once sailed
 *  through formatDateLong's null-check into the report as the literal string
 *  "Invalid Date". */
export function parseLocalDate(iso) {
    if (!iso) {
        return null;
    }
    if (String(iso).includes('T')) {
        const parsed = new Date(iso);
        return Number.isNaN(parsed.getTime()) ? null : parsed;
    }
    const [y, m, d] = String(iso).split('-').map(Number);
    const date = new Date(y, m - 1, d);
    return Number.isNaN(date.getTime()) ? null : date;
}

/** Day-granular relative label — the finest Last_Tested_Date__c supports. */
export function relativeDays(iso) {
    const date = parseLocalDate(iso);
    if (!date) {
        return null;
    }
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const days = Math.round((today - date) / 86400000);
    if (days <= 0) {
        return 'today';
    }
    if (days === 1) {
        return 'yesterday';
    }
    return `${days}d ago`;
}

/** Hour/minute-granular relative label for real Datetimes. */
export function relativeTime(iso) {
    if (!iso) {
        return null;
    }
    const mins = Math.round((Date.now() - new Date(iso).getTime()) / 60000);
    if (mins < 1) {
        return 'just now';
    }
    if (mins < 60) {
        return `${mins}m ago`;
    }
    const hours = Math.round(mins / 60);
    if (hours < 24) {
        return `${hours}h ago`;
    }
    return `${Math.round(hours / 24)}d ago`;
}

export function formatDateLong(iso) {
    const date = parseLocalDate(iso);
    return date
        ? date.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' })
        : null;
}

/** "Aug 12, 2026, 2:30 PM" — the tooltip form for Datetime cells whose
 *  visible text is date-only (formatDateLong). */
export function formatDateTimeLong(value) {
    const date = parseLocalDate(value);
    return date
        ? date.toLocaleString(undefined, {
              month: 'short', day: 'numeric', year: 'numeric',
              hour: 'numeric', minute: '2-digit'
          })
        : null;
}

/** Whole minutes → "4 min" / "1 h 26 m" / "31 h 51 m". Minutes are the
 *  grain the Apex sends; anything finer would be false precision. */
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

/** "14:32" — entries are minute-granular; seconds are noise in a log. Was a
 *  private in uatSessionWorkspace until the shared finding view model became
 *  its second caller. */
export function formatTime(value) {
    return new Date(value).toLocaleTimeString(undefined, {
        hour: '2-digit', minute: '2-digit'
    });
}

export function joinMeta(parts) {
    return parts.filter(Boolean).join(' · ');
}

/** Icon-led metadata items; entries without a label drop out. */
export function metaItems(entries) {
    return entries
        .filter((e) => Boolean(e.label))
        .map((e, i) => ({ ...e, key: `${i}:${e.icon}` }));
}

/** A card's functional area: the System when the taxonomy is populated,
 *  else the Module (queue cards before the systemName backfill, orphans). */
export function areaOf(card) {
    return card.systemName || card.moduleName;
}

/** Distinct functional areas across a card list, as filter-combobox options
 *  with a leading catch-all. */
export function areaOptionsFrom(cards, allLabel = 'All areas') {
    const seen = new Set();
    cards.forEach((c) => {
        const area = areaOf(c);
        if (area) {
            seen.add(area);
        }
    });
    return [
        { label: allLabel, value: 'all' },
        ...[...seen].sort().map((name) => ({ label: name, value: name }))
    ];
}

/** Case-insensitive substring match over the given haystack parts (falsy
 *  parts drop out). Empty/blank terms match everything. */
export function matchesSearch(term, parts) {
    const needle = (term || '').trim().toLowerCase();
    if (!needle) {
        return true;
    }
    return parts.filter(Boolean).join(' ').toLowerCase().includes(needle);
}