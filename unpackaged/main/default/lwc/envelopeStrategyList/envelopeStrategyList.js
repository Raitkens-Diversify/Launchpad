import { LightningElement, api } from 'lwc';
import {
    basisForOption,
    COMMIT_IDLE_MS,
    normalizeStrategyRows,
    strategyRowsEqual,
    STRATEGY_BASIS
} from 'c/envelopeFormSchema';

const UNIT_OPTIONS = [
    { label: '$', value: STRATEGY_BASIS.DOLLAR },
    { label: '%', value: STRATEGY_BASIS.PERCENT }
];

// Stated once as plain text under the header rather than as a per-row tooltip. The popover component
// that carried this before (lightning-helptext) has no precedent anywhere else in this codebase and
// is a live suspect in the action page hanging, so the explanation is ordinary markup.
const UNIT_HINT =
    'Sleeves marked $ are recorded in dollars, so the position does not drift as the account grows. ' +
    'Sleeves marked % are traded to that target weight of the modeled pool.';

/**
 * envelopeStrategyList — the Allocations table. One list holds every sleeve; whether a row is a
 * fixed-dollar carve-out or a percentage model allocation is a per-row attribute, not a section.
 * The unit is decided by the selected strategy's configured Allowed Funding Basis: locked (shown as
 * a static badge) for Dollar Only / Percent Only strategies, an actual $/% toggle only where the
 * rule allows either. The advisor never chooses a unit the rule has already decided.
 *
 * Any change that flips a row's unit — picking a strategy funded the other way, or toggling an
 * Either row — clears the typed value and refocuses the input: a number must never silently change
 * meaning between dollars and percent.
 *
 * Controlled: the parent owns the committed rows and every edit re-emits the full set. Typed amounts
 * are buffered locally and committed on blur (or a short idle window) — while a row's input is being
 * edited, the value bound to it is exactly what that input last reported, which is what stops a
 * controlled input from echoing itself into a loop. See the invariants documented on
 * envelopeTradeInstructions; the same two hold here. Neither amount input carries a currency
 * formatter for the same reason: the formatted figure is the row's read-only Est. dollars cell.
 */
export default class EnvelopeStrategyList extends LightningElement {
    /**
     * All allocation rows: [{ id, strategy, type, fundingAmount, fundingPercent }].
     *
     * Accessors rather than a plain field so an emit can be remembered until the parent acknowledges it.
     * An edit reaches the parent synchronously but comes back as a prop write on a later render, so two
     * edits in the same turn would both build on the same stale array and the second would revert the
     * first. `_emittedRows` closes that window; the setter drops it the moment the parent answers, so the
     * parent stays the source of truth.
     */
    @api
    get strategies() {
        return this._strategies;
    }

    set strategies(next) {
        this._strategies = next;
        this._emittedRows = null;
    }

    _strategies = [];
    _emittedRows = null;

    // Strategy dropdown options: [{ label, value, allowedBasis }] with the Strategy__c Id as value.
    @api options = [];

    // Whether each percentage row may show its dollar equivalent. False where the entry point has
    // no funded amount — nothing may be calculated from a value we don't have.
    @api showDerived = false;

    // Dollars left for the percentage rows after the fixed-dollar carve-outs, supplied by the
    // parent. Null until the Expected Account Value is known, which renders the equivalents as '—'
    // rather than a fictional $0.
    @api remainder;

    // New-row id suffix, so rapidly added rows get distinct keys.
    _seq = 0;

    // Amounts typed but not yet committed, keyed by row id. Reactive on purpose — each row's Est.
    // dollars read-out has to move as the advisor types. Holds exactly what the input reported.
    _pending = {};

    // Commit timers per row id, in a plain object mutated in place so arming one never re-renders.
    _timers = { byId: {} };



    disconnectedCallback() {
        this._clearAllTimers();
    }

    get unitOptions() {
        return UNIT_OPTIONS;
    }

    get unitHint() {
        return UNIT_HINT;
    }

    get hasRows() {
        return this._rows.length > 0;
    }

    get tableClass() {
        return this.showDerived ? 'strategy strategy_derived' : 'strategy';
    }

    // Rows shaped for render. The remove control is hidden while only one row remains.
    get rows() {
        const rows = this._rows;
        const showRemove = rows.length > 1;
        return rows.map((row) => {
            const resolved = this._effectiveUnit(row);
            const isDollar = resolved.unit === STRATEGY_BASIS.DOLLAR;
            // The buffered figure wins while this row is being edited, so the input is handed back
            // exactly what it reported and its read-outs still track the keystrokes. The committed
            // value renders back as a string for the same reason (I2 at the commit boundary, see
            // envelopeTradeInstructions): falling back to the NUMBER once the buffer empties would
            // flip the bound type and reassign the input — which a base input answers with another
            // change event, once per idle window.
            const committed = isDollar ? row.fundingAmount : row.fundingPercent;
            const value =
                row.id in this._pending
                    ? this._pending[row.id]
                    : committed === null || committed === undefined
                      ? null
                      : String(committed);
            const flag = this._flagFor(row, resolved, value);
            return {
                id: row.id,
                strategy: row.strategy,
                value,
                isDollar,
                unitLabel: isDollar ? '$' : '%',
                unitAria: isDollar ? 'Unit: dollars' : 'Unit: percent',
                unitValue: row.type,
                showToggle: resolved.toggle,
                flag: flag.text,
                flagClass: flag.isError ? 'strategy__flag strategy__flag_error' : 'strategy__flag',
                derived: this._derivedFor(row, isDollar, value),
                showRemove
            };
        });
    }

    handleAdd() {
        this._emit([...this._rows, this._blankRow()]);
    }

    handleRemove(event) {
        const rows = this._rows;
        if (rows.length <= 1) {
            return;
        }
        const { id } = event.currentTarget.dataset;
        this._dropPending(id);
        this._emit(rows.filter((row) => String(row.id) !== String(id)));
    }

    handleStrategyChange(event) {
        const { id } = event.currentTarget.dataset;
        const strategy = event.detail.value;
        const rows = this._rows;
        const next = rows.map((row) => {
            if (String(row.id) !== String(id) || row.strategy === strategy) {
                return row;
            }
            const rule = basisForOption(this._optionFor(strategy));
            const unit = rule.locked ? rule.unit : row.type;
            if (unit === row.type) {
                return { ...row, strategy };
            }
            // The new strategy is funded the other way: the typed number would silently change
            // meaning, so it is cleared and the advisor re-enters it in the right unit. Any buffered
            // amount goes with it — otherwise the buffer would put the cleared number straight back.
            this._dropPending(row.id);
            return { ...row, strategy, type: unit, fundingAmount: null, fundingPercent: null };
        });
        this._emitIfChanged(rows, next);
    }

    // Only Either rows render the toggle, so this only ever fires where the rule allows the choice.
    handleUnitChange(event) {
        const { id } = event.currentTarget.dataset;
        const type = event.detail.value;
        const rows = this._rows;
        const next = rows.map((row) => {
            if (String(row.id) !== String(id) || row.type === type) {
                return row;
            }
            // Same as above: the cleared value must not survive in the buffer.
            this._dropPending(row.id);
            return { ...row, type, fundingAmount: null, fundingPercent: null };
        });
        this._emitIfChanged(rows, next);
    }

    // Typing buffers and arms a commit; it does not propagate. The reported string goes into the
    // buffer verbatim and the template hands that same string back to this same input, so the row is
    // never given a value it did not itself produce.
    handleValueChange(event) {
        const { id } = event.currentTarget.dataset;
        const reported = event.detail.value;
        // I1 at the buffer hop, mirroring envelopeTradeInstructions._buffer: an echo of the value
        // already bound to this row's input must not reassign the reactive buffer (a render per
        // echo) nor postpone the armed commit.
        if (this._reportedIsBound(id, reported)) {
            return;
        }
        this._pending = { ...this._pending, [id]: reported };
        clearTimeout(this._timers.byId[id]);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._timers.byId[id] = setTimeout(() => this._commitRow(id), COMMIT_IDLE_MS);
    }

    // The value currently bound to a row's input: the buffered figure while one is pending,
    // otherwise the committed value in the string form the template binds (see `rows`).
    _reportedIsBound(id, reported) {
        if (id in this._pending) {
            return this._pending[id] === reported;
        }
        const row = this._rows.find((r) => String(r.id) === String(id));
        if (!row) {
            return false;
        }
        const isDollar = this._effectiveUnit(row).unit === STRATEGY_BASIS.DOLLAR;
        const committed = isDollar ? row.fundingAmount : row.fundingPercent;
        const bound = committed === null || committed === undefined ? null : String(committed);
        return reported === bound;
    }

    handleValueBlur(event) {
        this._commitRow(event.currentTarget.dataset.id);
    }

    /**
     * Commit every buffered amount, completing the flush chain the shell starts before a save. Safe to
     * call when nothing is buffered.
     */
    @api
    flushPendingEdits() {
        // One emit for the whole buffer, not one per row: every buffered amount is applied to the same
        // snapshot, so nothing is built on a set that another commit in this turn has already superseded.
        this._commitRows(Object.keys(this._pending));
    }

    _commitRow(id) {
        this._commitRows([id]);
    }

    _commitRows(ids) {
        const reported = {};
        ids.forEach((id) => {
            clearTimeout(this._timers.byId[id]);
            delete this._timers.byId[id];
            if (id in this._pending) {
                reported[id] = this._pending[id];
            }
        });
        const committing = Object.keys(reported);
        if (!committing.length) {
            return;
        }
        // Emptied before anything is emitted, so a commit that travels back around into another flush
        // finds nothing left to do — which is what makes the chain re-entrant.
        const rest = { ...this._pending };
        committing.forEach((id) => delete rest[id]);
        this._pending = rest;

        const rows = this._rows;
        const next = rows.map((row) => {
            const key = String(row.id);
            return key in reported ? this._withReportedValue(row, reported[key]) : row;
        });
        this._emitIfChanged(rows, next);
    }

    // Writes the field the row's effective unit owns, and settles `type` onto that unit — which is
    // also what migrates a stale draft row whose strategy was reclassified after it was saved.
    _withReportedValue(row, valueReported) {
        const value = this._toNumber(valueReported);
        const isDollar = this._effectiveUnit(row).unit === STRATEGY_BASIS.DOLLAR;
        const type = isDollar ? STRATEGY_BASIS.DOLLAR : STRATEGY_BASIS.PERCENT;
        const fundingAmount = isDollar ? value : null;
        const fundingPercent = isDollar ? null : value;
        if (
            row.type === type &&
            row.fundingAmount === fundingAmount &&
            row.fundingPercent === fundingPercent
        ) {
            return row;
        }
        return { ...row, type, fundingAmount, fundingPercent };
    }

    get _rows() {
        return normalizeStrategyRows(this._emittedRows || this._strategies);
    }

    /**
     * The unit this row is funded in right now. The strategy's rule wins where it locks a unit; an
     * Either strategy keeps whatever the row carries and gets the toggle; a row with no strategy
     * yet (or one whose strategy is no longer offered) keeps its own unit provisionally — picking
     * the strategy is what decides.
     */
    _effectiveUnit(row) {
        const option = this._optionFor(row.strategy);
        if (!row.strategy || !option) {
            return { unit: row.type, locked: false, toggle: false };
        }
        const rule = basisForOption(option);
        return rule.locked
            ? { unit: rule.unit, locked: true, toggle: false }
            : { unit: row.type, locked: false, toggle: true };
    }

    // The row's inline note: what it still needs, or — for a stale draft whose strategy was
    // reclassified since it was saved — that its value has to be re-entered in the rule's unit.
    // A fully blank row carries no flag; the section alert names it at submit.
    _flagFor(row, resolved, value) {
        const numeric = Number(value);
        const hasValue = Number.isFinite(numeric) && numeric > 0;
        if (resolved.locked && resolved.unit !== row.type) {
            const stale = row.type === STRATEGY_BASIS.DOLLAR ? row.fundingAmount : row.fundingPercent;
            if (Number.isFinite(Number(stale)) && stale !== null && stale !== '') {
                return {
                    text:
                        resolved.unit === STRATEGY_BASIS.DOLLAR
                            ? 'This strategy is now recorded in dollars — re-enter the amount.'
                            : 'This strategy is now traded to a target weight — re-enter as a percentage.',
                    isError: true
                };
            }
        }
        if (row.strategy && !hasValue) {
            return {
                text:
                    resolved.unit === STRATEGY_BASIS.DOLLAR
                        ? 'Enter an amount.'
                        : 'Enter a target weight.',
                isError: false
            };
        }
        if (!row.strategy && hasValue) {
            return { text: 'Select a strategy.', isError: false };
        }
        return { text: '', isError: false };
    }

    // The row's dollar read-out. A percentage row shows its equivalent share of the modeled pool —
    // '—' until the pool is known, never a fictional $0. A dollar row shows the amount it holds,
    // formatted: that read-out is what replaced the currency formatter the input used to carry.
    _derivedFor(row, isDollar, value) {
        if (!this.showDerived) {
            return '';
        }
        if (isDollar) {
            const amount = Number(value);
            return Number.isFinite(amount) && amount > 0 ? this._currency(amount) : '';
        }
        const remainder = Number(this.remainder);
        const hasRemainder =
            this.remainder !== null &&
            this.remainder !== undefined &&
            Number.isFinite(remainder) &&
            remainder >= 0;
        const percent = Number(value);
        if (!hasRemainder || !Number.isFinite(percent) || percent <= 0) {
            return '—';
        }
        return this._currency((remainder * percent) / 100);
    }

    _optionFor(strategy) {
        return (this.options || []).find((option) => option.value === strategy);
    }

    _blankRow() {
        this._seq += 1;
        return {
            id: `s-${Date.now()}-${this._seq}`,
            strategy: '',
            type: STRATEGY_BASIS.PERCENT,
            fundingAmount: null,
            fundingPercent: null
        };
    }

    /**
     * Emit only when an edit actually changed a row.
     *
     * This is load-bearing, not a micro-optimization. The rows are controlled: an edit is emitted,
     * the parent writes it to the draft, and the new value is handed straight back down into the same
     * inputs. A base input re-fires `change` when its value is set programmatically — a currency
     * input also reformats what it was given — so emitting unconditionally makes that echo a
     * self-sustaining loop that locks the browser. Each unchanged row keeps its identity through the
     * handlers' `map`, so an echo produces an identical set and stops here.
     *
     * The same reason envelopeFieldControl writes back exactly the value its input reported.
     */
    _emitIfChanged(previous, next) {
        if (strategyRowsEqual(previous, next)) {
            return;
        }
        this._emit(next);
    }

    // Forget a row's buffered amount and its pending commit. Called wherever a value stops being the
    // right answer for that row: the unit flipped, the strategy was reclassified, or the row is gone.
    _dropPending(id) {
        clearTimeout(this._timers.byId[id]);
        delete this._timers.byId[id];
        if (!(id in this._pending)) {
            return;
        }
        const { [id]: _dropped, ...rest } = this._pending;
        this._pending = rest;
    }

    _clearAllTimers() {
        Object.keys(this._timers.byId).forEach((id) =>
            clearTimeout(this._timers.byId[id])
        );
        this._timers.byId = {};
    }

    // Uniquely named (not 'change') so it isn't confused with the bubbling, composed 'change' events
    // that the inner base inputs/comboboxes fire.
    _emit(strategies) {
        // Held so a second edit in the same turn builds on this rather than on the prop the parent has
        // not written back yet. Dropped by the `strategies` setter as soon as the parent answers.
        this._emittedRows = strategies;
        this.dispatchEvent(new CustomEvent('strategieschange', { detail: { strategies } }));
    }

    _toNumber(value) {
        if (value === '' || value === null || value === undefined) {
            return null;
        }
        const parsed = Number(value);
        return Number.isFinite(parsed) ? parsed : null;
    }

    // Whole dollars: the equivalents are read-outs, and cents would only add noise.
    _currency(value) {
        const amount = Number.isFinite(value) ? Math.round(value) : 0;
        return amount < 0
            ? `−$${Math.abs(amount).toLocaleString('en-US')}`
            : `$${amount.toLocaleString('en-US')}`;
    }
}