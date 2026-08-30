import { LightningElement, api } from 'lwc';
import {
    ALLOWED_BASIS,
    basisForOption,
    COMMIT_IDLE_MS,
    dollarsForPercentRow,
    formatMoney,
    normalizeStrategyRows,
    percentForDollarRow,
    roundCurrency,
    strategyRowsEqual,
    STRATEGY_BASIS
} from 'c/envelopeFormSchema';

// The two value cells a row carries. Buffers, timers and every handler key on `${rowId}|${cell}`,
// because a row now has two independently editable numbers rather than one.
const CELL = { PERCENT: 'pct', DOLLAR: 'amt' };

// A row whose strategy is not picked yet (or is no longer offered) has no rule to obey, so both
// cells stay live and picking the strategy is what decides. Shaped like basisForOption's result.
const NO_RULE = { unit: null, locked: false, allowed: ALLOWED_BASIS.EITHER };

// Why a cell is greyed. There is deliberately no table-level sentence above the rows: the columns
// are labelled, both boxes are live wherever the rule allows, and the only cell that needs
// explaining carries its own icon — a paragraph saying so would restate the screen.
//
// On that icon: an earlier comment here called lightning-helptext unprecedented in this codebase and
// a suspect in the action page hanging. Both halves were wrong. Four bundles use the element,
// `field-level-help` (the same popover) appears throughout including envelopeFieldControl in this
// very wizard, and the freeze was root-caused to LWC membrane proxy depth plus an un-memoized
// getter — neither of which a static string prop can reproduce.
//
// Both calculated figures share ONE denominator — the resolved expected account value — so the
// same weight always means the same dollars, whatever the other rows hold. (An earlier build
// priced a weight's dollars off the pool left after the fixed-dollar carve-outs, which made two
// identical weights show two different dollar figures; reversed 2026-08-30 by request.)
const CELL_HELP = {
    [CELL.PERCENT]:
        'This strategy is recorded in dollars. The weight shown is its share of the expected ' +
        'account value.',
    [CELL.DOLLAR]:
        'This strategy is recorded as a target weight. The dollars shown are its share of the ' +
        'expected account value.'
};


/**
 * envelopeStrategyList — the Allocations table. One list holds every sleeve; whether a row is a
 * fixed-dollar carve-out or a percentage model allocation is a per-row attribute, not a section.
 *
 * Every row shows BOTH a target weight and a dollar figure. Whichever cell the advisor types into is
 * the one that gets recorded, and the other is calculated from it — so choosing a unit costs no
 * extra click and needs no separate control. The strategy's configured Allowed Funding Basis decides
 * which cells are live: a Dollar Only or Percent Only strategy greys its forbidden cell out — a
 * disabled box holding the calculated equivalent, so the row keeps its shape and the cell is
 * visibly present but unavailable — and an Either strategy leaves both live so the advisor
 * switches basis by simply typing in the other one. There is no unit toggle.
 *
 * Any change that flips a row's unit — picking a strategy funded the other way — clears the typed
 * value: a number must never silently change meaning between dollars and percent.
 *
 * Controlled: the parent owns the committed rows and every edit re-emits the full set. Typed amounts
 * are buffered locally and committed on blur (or a short idle window) — while a cell is being
 * edited, the value bound to it is exactly what that cell last reported, which is what stops a
 * controlled input from echoing itself into a loop. See the invariants documented on
 * envelopeTradeInstructions; the same two hold here, and doubling the inputs per row doubled the
 * surface they have to cover — a calculated cell is reassigned whenever ANY other row moves the
 * balance, and every one of those writes comes back as a change event that must not become an edit.
 * Neither input carries a currency formatter for the same reason: a formatter rewrites what it is
 * handed, so the cell could never be bound the exact string it just reported.
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

    // The resolved Expected Account Value (typed, or the Source of Funds fallback), supplied by
    // the parent: the single denominator every calculated cell divides against, in both
    // directions. Null until known, which renders the derived figures as an em dash rather than a
    // fictional $0.
    @api accountValue;

    // New-row id suffix, so rapidly added rows get distinct keys.
    _seq = 0;

    // Amounts typed but not yet committed, keyed by `${rowId}|${cell}`. Reactive on purpose — the
    // counterpart cell has to move as the advisor types. Holds exactly what the input reported.
    _pending = {};

    // Commit timers per cell key, in a plain object mutated in place so arming one never re-renders.
    _timers = { byId: {} };

    // The cell each row was last typed into, so a flush that finds both of a row's cells buffered
    // still has a deterministic winner. Not reactive: read only while committing.
    _lastCell = {};

    disconnectedCallback() {
        this._clearAllTimers();
    }

    get hasRows() {
        return this._rows.length > 0;
    }

    // Rows shaped for render. The remove control is hidden while only one row remains.
    get rows() {
        const rows = this._rows;
        const showRemove = rows.length > 1;
        return rows.map((row) => {
            const state = this._cellState(row);
            return {
                id: row.id,
                strategy: row.strategy,
                excluded: this._optionFor(row.strategy)?.excluded === true,
                showRemove,
                pctEditable: state.pctEditable,
                pctValue: this._cellValue(row, CELL.PERCENT, state),
                pctReadout: this._readout(row, CELL.PERCENT, state),
                pctHelp: CELL_HELP[CELL.PERCENT],
                pctShowsUnit: this._showsUnit(row, CELL.PERCENT, state),
                amtEditable: state.amtEditable,
                amtValue: this._cellValue(row, CELL.DOLLAR, state),
                amtReadout: this._readout(row, CELL.DOLLAR, state),
                amtHelp: CELL_HELP[CELL.DOLLAR],
                amtShowsUnit: this._showsUnit(row, CELL.DOLLAR, state),
                ...this._flagFor(row, state)
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
        this._dropPendingRow(id);
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
            this._dropPendingRow(row.id);
            return { ...row, strategy, type: unit, fundingAmount: null, fundingPercent: null };
        });
        this._emitIfChanged(rows, next);
    }

    // Typing buffers and arms a commit; it does not propagate. The reported string goes into the
    // buffer verbatim and the template hands that same string back to this same input, so the cell is
    // never given a value it did not itself produce.
    handleValueChange(event) {
        const { id, cell } = event.currentTarget.dataset;
        const reported = event.detail.value;
        // I1 at the buffer hop, mirroring envelopeTradeInstructions._buffer: an echo of the value
        // already bound to this cell must not reassign the reactive buffer (a render per echo) nor
        // postpone the armed commit. This is what absorbs the write a calculated cell takes every
        // time another row moves the balance underneath it.
        if (this._reportedIsBound(id, cell, reported)) {
            return;
        }
        const key = this._key(id, cell);
        this._pending = { ...this._pending, [key]: reported };
        this._lastCell[id] = cell;
        clearTimeout(this._timers.byId[key]);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._timers.byId[key] = setTimeout(() => this._commitKeys([key]), COMMIT_IDLE_MS);
    }

    handleValueBlur(event) {
        const { id, cell } = event.currentTarget.dataset;
        this._commitKeys([this._key(id, cell)]);
    }

    /**
     * Commit every buffered amount, completing the flush chain the shell starts before a save. Safe to
     * call when nothing is buffered.
     */
    @api
    flushPendingEdits() {
        // One emit for the whole buffer, not one per cell: every buffered amount is applied to the same
        // snapshot, so nothing is built on a set that another commit in this turn has already superseded.
        this._commitKeys(Object.keys(this._pending));
    }

    _commitKeys(keys) {
        const reported = {};
        keys.forEach((key) => {
            clearTimeout(this._timers.byId[key]);
            delete this._timers.byId[key];
            if (key in this._pending) {
                reported[key] = this._pending[key];
            }
        });
        const committing = Object.keys(reported);
        if (!committing.length) {
            return;
        }
        // Emptied before anything is emitted, so a commit that travels back around into another flush
        // finds nothing left to do — which is what makes the chain re-entrant. A row's OTHER cell is
        // dropped alongside: the value bound to it is about to be recalculated from this commit, so a
        // buffer still holding its old figure would put a stale number straight back.
        const rest = { ...this._pending };
        committing.forEach((key) => {
            delete rest[key];
            const other = this._counterpart(key);
            if (other in rest) {
                clearTimeout(this._timers.byId[other]);
                delete this._timers.byId[other];
                delete rest[other];
            }
        });
        this._pending = rest;

        // At most one cell per row is applied. Two buffered cells on one row cannot arise through the
        // UI (moving between them blurs the first, which commits it), but a flush must still be
        // deterministic rather than dependent on key order.
        const byRow = {};
        committing.forEach((key) => {
            const { id, cell } = this._parse(key);
            if (!byRow[id] || this._lastCell[id] === cell) {
                byRow[id] = { cell, value: reported[key] };
            }
        });

        const rows = this._rows;
        const next = rows.map((row) => {
            const applied = byRow[String(row.id)];
            return applied ? this._withReportedValue(row, applied.cell, applied.value) : row;
        });
        this._emitIfChanged(rows, next);
    }

    /**
     * Write the cell the advisor typed into, and settle `type` onto that cell — which is what makes
     * typing a dollar figure into a percentage row switch its basis with no toggle, and what migrates
     * a stale draft row whose strategy was reclassified after it was saved.
     *
     * Two guards. A cell the rule forbids is disabled and cannot have been typed into, so a commit
     * naming one is dropped rather than trusted. And clearing a CALCULATED cell is a no-op: that
     * figure is not the row's own value, so emptying it must not destroy the value it was derived
     * from — the next render simply calculates it back.
     */
    _withReportedValue(row, cell, valueReported) {
        const state = this._cellState(row);
        const isPercentCell = cell === CELL.PERCENT;
        const editable = isPercentCell ? state.pctEditable : state.amtEditable;
        if (!editable) {
            return row;
        }
        const value = this._toNumber(valueReported);
        if (value === null && !this._owns(cell, state)) {
            return row;
        }
        const type = isPercentCell ? STRATEGY_BASIS.PERCENT : STRATEGY_BASIS.DOLLAR;
        const fundingAmount = isPercentCell ? null : value;
        const fundingPercent = isPercentCell ? value : null;
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
     * How a row's two cells behave right now. The strategy's rule wins where it locks a unit — the
     * locked-out cell is disabled — and an Either strategy (or a row with no strategy yet)
     * leaves both live, keeping whatever unit the row already carries as the one it records.
     */
    _cellState(row) {
        const option = this._optionFor(row.strategy);
        const rule = row.strategy && option ? basisForOption(option) : NO_RULE;
        const unit = rule.locked ? rule.unit : row.type;
        const isDollar = unit === STRATEGY_BASIS.DOLLAR;
        return {
            rule,
            unit,
            isDollar,
            pctEditable: !rule.locked || !isDollar,
            amtEditable: !rule.locked || isDollar
        };
    }

    // Does this cell hold the row's own recorded number, rather than one calculated from the other?
    _owns(cell, state) {
        return cell === CELL.PERCENT ? !state.isDollar : state.isDollar;
    }

    /**
     * The number a cell shows when it is not being typed into: the row's own value where the cell
     * owns the basis, otherwise the figure calculated from the other cell. Null where there is
     * nothing to show, or nothing to divide by.
     *
     * Both directions calculate against the SAME denominator, the resolved expected account value
     * (see CELL_HELP), so the same weight always shows the same dollars. The derived side goes
     * through `_recordedNumber` so it tracks the owning cell's keystrokes rather than jumping a
     * commit later. The derived figure is display only — the row still records exactly one value,
     * and `strategyTotals` still keeps dollar rows out of the percentage total.
     */
    _cellNumber(row, cell, state) {
        if (this._owns(cell, state)) {
            return this._toNumber(cell === CELL.PERCENT ? row.fundingPercent : row.fundingAmount);
        }
        if (cell === CELL.PERCENT) {
            return percentForDollarRow(this._recordedNumber(row, state), this.accountValue);
        }
        return dollarsForPercentRow(this._recordedNumber(row, state), this.accountValue);
    }

    // Whether to print the column's unit beside this cell. Suppressed where the cell has no figure
    // to qualify: '— %' reads as a broken value rather than an absent one.
    _showsUnit(row, cell, state) {
        const editable = cell === CELL.PERCENT ? state.pctEditable : state.amtEditable;
        if (editable) {
            return true;
        }
        return this._cellNumber(row, cell, state) !== null;
    }

    // The row's recorded number as currently DISPLAYED — the buffer wins while its cell is being
    // typed into. Which is why `_pending` is reactive: the calculated cell has to move with the
    // keystrokes rather than jump a commit later.
    _recordedNumber(row, state) {
        const owning = state.isDollar ? CELL.DOLLAR : CELL.PERCENT;
        const key = this._key(row.id, owning);
        if (key in this._pending) {
            return this._toNumber(this._pending[key]);
        }
        return this._toNumber(state.isDollar ? row.fundingAmount : row.fundingPercent);
    }

    /**
     * The exact string the template binds to a cell's input.
     *
     * The committed value renders back as a string (I2 at the commit boundary, see
     * envelopeTradeInstructions): falling back to the NUMBER once the buffer empties would flip the
     * bound type and reassign the input — which a base input answers with another change event, once
     * per idle window. A calculated figure is rounded once, deterministically, for the same reason:
     * the string a cell is handed must be reproducible, or `_reportedIsBound` cannot recognize the
     * echo of it.
     */
    _boundString(row, cell, state) {
        const number = this._cellNumber(row, cell, state);
        if (number === null) {
            return null;
        }
        if (this._owns(cell, state)) {
            return String(number);
        }
        return String(cell === CELL.PERCENT ? this._round(number) : roundCurrency(number));
    }

    // The buffered figure wins while this cell is being edited, so the input is handed back exactly
    // what it reported and the other cell still tracks the keystrokes.
    _cellValue(row, cell, state) {
        const key = this._key(row.id, cell);
        return key in this._pending ? this._pending[key] : this._boundString(row, cell, state);
    }

    // What a locked-out cell shows in its disabled box: the calculated equivalent, or an em dash
    // where there is nothing to show — never a fictional $0 or 0%. Grouped but WITHOUT its unit
    // symbol, because that symbol is now a sibling of the box and printing it here too would double
    // it. Formatted rather than raw because this figure can never be typed into, so nothing has to
    // be able to hand it back unchanged.
    _readout(row, cell, state) {
        const number = this._cellNumber(row, cell, state);
        if (number === null) {
            return '—';
        }
        return cell === CELL.PERCENT ? String(this._round(number)) : this._grouped(number);
    }

    // The value currently bound to a cell: the buffered figure while one is pending, otherwise
    // exactly what `_boundString` produced for it.
    _reportedIsBound(id, cell, reported) {
        const key = this._key(id, cell);
        if (key in this._pending) {
            return this._pending[key] === reported;
        }
        const row = this._rows.find((r) => String(r.id) === String(id));
        if (!row) {
            return false;
        }
        return reported === this._boundString(row, cell, this._cellState(row));
    }

    // The row's inline note: what it still needs, or — for a stale draft whose strategy was
    // reclassified since it was saved — that its value has to be re-entered in the rule's unit.
    // A fully blank row carries no flag; the section alert names it at submit.
    _flagFor(row, state) {
        const flag = (text, isError) => ({
            flag: text,
            flagClass: isError ? 'strategy__flag strategy__flag_error' : 'strategy__flag'
        });
        if (state.rule.locked && state.unit !== row.type) {
            const stale = row.type === STRATEGY_BASIS.DOLLAR ? row.fundingAmount : row.fundingPercent;
            if (Number.isFinite(Number(stale)) && stale !== null && stale !== '') {
                return flag(
                    state.isDollar
                        ? 'This strategy is now recorded in dollars — re-enter the amount.'
                        : 'This strategy is now traded to a target weight — re-enter as a percentage.',
                    true
                );
            }
        }
        // Judged on the cell the row records into, and on the buffer where one is live, so the note
        // clears as the advisor types rather than a commit later.
        const owning = state.isDollar ? CELL.DOLLAR : CELL.PERCENT;
        const typed = Number(this._cellValue(row, owning, state));
        const hasValue = Number.isFinite(typed) && typed > 0;
        if (row.strategy && !hasValue) {
            if (state.pctEditable && state.amtEditable) {
                // Both cells are live and both are labelled by the column strip, so naming them
                // again here only lengthens the most frequently shown string on the table.
                return flag('Enter a value.', false);
            }
            return flag(state.isDollar ? 'Enter an amount.' : 'Enter a target weight.', false);
        }
        if (!row.strategy && hasValue) {
            return flag('Select a strategy.', false);
        }
        return flag('', false);
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
     * inputs. A base input re-fires `change` when its value is set programmatically — and with two
     * cells per row, committing one of them reassigns the other on every affected row — so emitting
     * unconditionally makes that echo a self-sustaining loop that locks the browser. Each unchanged
     * row keeps its identity through the handlers' `map`, so an echo produces an identical set and
     * stops here.
     *
     * The same reason envelopeFieldControl writes back exactly the value its input reported.
     */
    _emitIfChanged(previous, next) {
        if (strategyRowsEqual(previous, next)) {
            return;
        }
        this._emit(next);
    }

    _key(id, cell) {
        return `${id}|${cell}`;
    }

    _parse(key) {
        const at = key.lastIndexOf('|');
        return { id: key.slice(0, at), cell: key.slice(at + 1) };
    }

    _counterpart(key) {
        const { id, cell } = this._parse(key);
        return this._key(id, cell === CELL.PERCENT ? CELL.DOLLAR : CELL.PERCENT);
    }

    // Forget both of a row's buffered amounts and their pending commits. Called wherever the values
    // stop being the right answer for that row: its unit flipped, or the row is gone.
    _dropPendingRow(id) {
        const keys = [this._key(id, CELL.PERCENT), this._key(id, CELL.DOLLAR)];
        keys.forEach((key) => {
            clearTimeout(this._timers.byId[key]);
            delete this._timers.byId[key];
        });
        delete this._lastCell[id];
        if (!keys.some((key) => key in this._pending)) {
            return;
        }
        const rest = { ...this._pending };
        keys.forEach((key) => delete rest[key]);
        this._pending = rest;
    }

    _clearAllTimers() {
        Object.keys(this._timers.byId).forEach((key) => clearTimeout(this._timers.byId[key]));
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

    // Up to four decimal places, trailing zeros dropped — a weight reads as 12.5, not 12.5000.
    // Only DERIVED weights pass through here (a typed value is never reformatted), and four
    // decimals is what keeps the display honest: $10,000.00 of a $100,005 account is 9.9995%, and
    // rounding that to 10 made two rows with different dollars show the same weight.
    _round(value) {
        return Math.round(Number(value) * 10000) / 10000;
    }

    // Grouped dollars at two decimals, no currency symbol — the '$' sits beside the box. Shared
    // with the section footer (formatMoney) so a read-out and the ledger can never round the same
    // figure two different ways.
    _grouped(value) {
        return formatMoney(value);
    }
}