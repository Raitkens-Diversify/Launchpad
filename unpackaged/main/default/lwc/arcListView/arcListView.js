/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-12
 */
import { LightningElement, api, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { loadStyle } from 'lightning/platformResourceLoader';
import { refreshApex } from '@salesforce/apex';
import resolveReferenceLabels from '@salesforce/apex/ArcListViewController.resolveReferenceLabels';
import resolveRecordTypeLabels from '@salesforce/apex/ArcListViewController.resolveRecordTypeLabels';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import {
    getListInfosByObjectName,
    getListInfoByName,
    getListRecordsByName,
    getListObjectInfo,
    createListInfo,
    updateListInfoByName,
    deleteListInfo
} from 'lightning/uiListsApi';
import diversifyStyles from '@salesforce/resourceUrl/diversifyStyles';
import envelopeWizardStyles from '@salesforce/resourceUrl/envelopeWizardStyles';
import getListViewPreference from '@salesforce/apex/UserPreferenceController.getListViewPreference';
import saveListViewPreference from '@salesforce/apex/UserPreferenceController.saveListViewPreference';
import {
    usesQueryParamRecordRoute,
    isExperienceBuilderDesignMode
} from 'c/recordNavigationCommunityUtils';
import {
    SORT_ASC,
    resolveSortDirection,
    sortRecords
} from 'c/dataTableSortUtils';

const ARC_APPLICATION_NAME = 'ARC';
const LIST_VIEW_FETCH_SIZE = 200;
const DEFAULT_TABLE_PAGE_SIZE = 25;
const DEFAULT_TABLE_PAGE_SIZE_OPTIONS = [10, 25, 50];

const DEFAULT_ENVELOPE_COLUMNS = [
    'Name',
    'Household_Name__c',
    'Financial_Advisor_Team__c',
    'CreatedDate',
    'Status__c',
    'LastModifiedDate'
];

const parseListViewPreference = (preferenceJson) => {
    if (!preferenceJson) {
        return null;
    }

    try {
        const parsed = JSON.parse(preferenceJson);

        if (!parsed || typeof parsed !== 'object') {
            return null;
        }

        return parsed;
    } catch {
        return null;
    }
};

const OPERATOR_LABELS = {
    Equals: 'equals',
    NotEqual: 'does not equal',
    Contains: 'contains',
    NotContain: 'does not contain',
    StartsWith: 'starts with',
    GreaterThan: 'greater than',
    GreaterOrEqual: 'greater or equal',
    LessThan: 'less than',
    LessOrEqual: 'less or equal',
    Includes: 'includes',
    Excludes: 'excludes',
    Within: 'within'
};

const REFERENCE_REF_PREFIX = '__ref_';

let filterKeyCounter = 0;

const looksLikeSalesforceId = (value) =>
    typeof value === 'string' && /^[a-zA-Z0-9]{15,18}$/.test(value);

const getReferenceLookupKey = (column = {}) =>
    column.lookupId || column.fieldApiName || column.fieldName || '';

const RECORD_TYPE_LOOKUP_FIELD = 'RecordTypeId';

const isRecordTypeColumn = (column = {}) => {
    const fieldApiName = (column.fieldApiName || column.fieldName || '').toLowerCase();
    const lookupId = column.lookupId;

    return (
        lookupId === RECORD_TYPE_LOOKUP_FIELD ||
        fieldApiName === 'recordtypeid' ||
        fieldApiName === 'recordtype.name' ||
        fieldApiName.startsWith('recordtype.')
    );
};

const normalizeListViewColumn = (column = {}) => {
    const fieldApiName = column.fieldApiName || column.fieldName || column.label || '';
    const label = column.label || fieldApiName;

    if (!isRecordTypeColumn({ ...column, fieldApiName })) {
        return {
            fieldApiName,
            label,
            lookupId: column.lookupId || null
        };
    }

    let normalizedFieldApiName = fieldApiName;

    if (fieldApiName.includes('.')) {
        normalizedFieldApiName = fieldApiName.split('.').pop() || 'Name';
    } else if (fieldApiName === RECORD_TYPE_LOOKUP_FIELD) {
        normalizedFieldApiName = 'Name';
    }

    return {
        fieldApiName: normalizedFieldApiName,
        label,
        lookupId: RECORD_TYPE_LOOKUP_FIELD
    };
};

const getRecordTypeDisplayValue = (rec, lookupRecordId) => {
    const recordTypeName = rec?.recordTypeInfo?.name;

    if (!recordTypeName) {
        return '';
    }

    const recordTypeId =
        rec?.recordTypeId ||
        rec?.fields?.RecordTypeId?.value ||
        rec?.recordTypeInfo?.recordTypeId;

    if (!lookupRecordId) {
        return recordTypeName;
    }

    if (recordTypeId && String(recordTypeId) === String(lookupRecordId)) {
        return recordTypeName;
    }

    return '';
};

const getDisplayValueFromField = (field, targetFieldApiName = 'Name') => {
    if (!field) {
        return '';
    }

    // List view API puts the resolved related label on displayValue for lookup fields.
    if (field.displayValue != null && field.displayValue !== '') {
        return String(field.displayValue);
    }

    const nestedFields = field.value?.fields;

    if (!nestedFields || typeof field.value !== 'object') {
        return '';
    }

    const nestedKeys = [targetFieldApiName, 'Name', 'CaseNumber'].filter(
        (key, index, array) => key && array.indexOf(key) === index
    );

    for (const nestedKey of nestedKeys) {
        const nestedField = nestedFields[nestedKey];

        if (!nestedField) {
            continue;
        }

        if (nestedField.displayValue != null && nestedField.displayValue !== '') {
            return String(nestedField.displayValue);
        }

        if (
            nestedField.value != null &&
            nestedField.value !== '' &&
            !looksLikeSalesforceId(String(nestedField.value))
        ) {
            return String(nestedField.value);
        }
    }

    return '';
};

const buildHeuristicRelationshipName = (lookupId) => {
    if (!lookupId) {
        return null;
    }

    if (lookupId === 'RecordTypeId') {
        return 'RecordType';
    }

    if (lookupId.endsWith('Id') && lookupId !== 'Id') {
        return lookupId.slice(0, -2);
    }

    if (lookupId.endsWith('__c')) {
        return lookupId.replace(/__c$/, '__r');
    }

    return null;
};

const buildHeuristicLookupField = (relationshipName) => {
    if (!relationshipName) {
        return null;
    }

    if (relationshipName === 'RecordType') {
        return 'RecordTypeId';
    }

    if (relationshipName.endsWith('__r')) {
        return relationshipName.replace(/__r$/, '__c');
    }

    if (relationshipName.endsWith('Id')) {
        return relationshipName;
    }

    return `${relationshipName}Id`;
};

const buildRelationshipContext = (objectInfo) => {
    const relationshipNameByLookupField = {};
    const lookupFieldByRelationshipName = {};
    const fields = objectInfo?.fields;

    if (fields) {
        Object.values(fields).forEach((field) => {
            if (!field?.apiName || !field?.relationshipName) {
                return;
            }

            relationshipNameByLookupField[field.apiName] = field.relationshipName;
            lookupFieldByRelationshipName[field.relationshipName] = field.apiName;
        });
    }

    return {
        relationshipNameByLookupField,
        lookupFieldByRelationshipName
    };
};

const getRelationshipNameForLookupField = (lookupId, relationshipContext = {}) => {
    if (!lookupId) {
        return null;
    }

    return (
        relationshipContext.relationshipNameByLookupField?.[lookupId] ||
        buildHeuristicRelationshipName(lookupId)
    );
};

const getLookupFieldForRelationshipName = (
    relationshipName,
    relationshipContext = {}
) => {
    if (!relationshipName) {
        return null;
    }

    return (
        relationshipContext.lookupFieldByRelationshipName?.[relationshipName] ||
        buildHeuristicLookupField(relationshipName)
    );
};

const getRecordFieldNode = (fields, fieldPath) => {
    if (!fields || !fieldPath || !fieldPath.includes('.')) {
        return null;
    }

    const segments = fieldPath.split('.');
    let currentFields = fields;

    for (let index = 0; index < segments.length; index += 1) {
        const segment = segments[index];
        const fieldNode = currentFields?.[segment];

        if (!fieldNode) {
            return null;
        }

        if (index === segments.length - 1) {
            return fieldNode;
        }

        currentFields = fieldNode.value?.fields;

        if (!currentFields) {
            return null;
        }
    }

    return null;
};

const resolveListFieldNode = (fields, column = {}, relationshipContext = {}) => {
    if (!fields || !column) {
        return null;
    }

    const fieldApiName = column.fieldApiName || column.fieldName || '';
    const lookupId = column.lookupId;

    if (lookupId && fields[lookupId]) {
        return fields[lookupId];
    }

    if (lookupId) {
        const relationshipName = getRelationshipNameForLookupField(
            lookupId,
            relationshipContext
        );

        if (relationshipName && fields[relationshipName]) {
            return fields[relationshipName];
        }
    }

    if (fieldApiName && fields[fieldApiName]) {
        return fields[fieldApiName];
    }

    if (fieldApiName.includes('.')) {
        const relationshipFieldNode = getRecordFieldNode(fields, fieldApiName);

        if (relationshipFieldNode) {
            return relationshipFieldNode;
        }

        const relationshipName = fieldApiName.split('.')[0];

        if (relationshipName && fields[relationshipName]) {
            return fields[relationshipName];
        }

        const lookupFieldApiName = getLookupFieldForRelationshipName(
            relationshipName,
            relationshipContext
        );

        if (lookupFieldApiName && fields[lookupFieldApiName]) {
            return fields[lookupFieldApiName];
        }
    }

    return null;
};

const extractLookupRecordIdForColumn = (
    recordFields,
    column = {},
    fieldNode = null,
    relationshipContext = {}
) => {
    let lookupRecordId = extractLookupRecordId(fieldNode);

    if (lookupRecordId) {
        return lookupRecordId;
    }

    const lookupId = column.lookupId || (isRecordTypeColumn(column) ? RECORD_TYPE_LOOKUP_FIELD : null);
    const fieldApiName = column.fieldApiName || column.fieldName || '';

    if (lookupId) {
        lookupRecordId = extractLookupRecordId(recordFields[lookupId]);

        if (lookupRecordId) {
            return lookupRecordId;
        }

        const relationshipName = getRelationshipNameForLookupField(
            lookupId,
            relationshipContext
        );

        if (relationshipName) {
            lookupRecordId = extractLookupRecordId(recordFields[relationshipName]);

            if (lookupRecordId) {
                return lookupRecordId;
            }
        }
    }

    if (fieldApiName.includes('.')) {
        const relationshipName = fieldApiName.split('.')[0];
        lookupRecordId = extractLookupRecordId(recordFields[relationshipName]);

        if (lookupRecordId) {
            return lookupRecordId;
        }
    }

    return null;
};

const resolveColumnStorageKey = (column = {}) => {
    const fieldApiName = column.fieldApiName || column.fieldName || '';

    if (column.lookupId && column.lookupId !== fieldApiName) {
        return `${column.lookupId}${fieldApiName}`;
    }

    if (fieldApiName.includes('.')) {
        return fieldApiName.replace(/\./g, '');
    }

    return fieldApiName;
};

const extractLookupRecordId = (field) => {
    if (!field) {
        return null;
    }

    if (typeof field.value === 'string' && looksLikeSalesforceId(field.value)) {
        return field.value;
    }

    const nestedId = field.value?.id || field.value?.fields?.Id?.value;

    if (nestedId && looksLikeSalesforceId(String(nestedId))) {
        return String(nestedId);
    }

    return null;
};

const getSimpleFieldValue = (field, isNumericFieldType, fieldApiName) => {
    if (!field) {
        return '';
    }

    if (isNumericFieldType(fieldApiName)) {
        return field.value != null && field.value !== '' ? field.value : '';
    }

    const displayValue = getDisplayValueFromField(field, fieldApiName);

    if (displayValue) {
        return displayValue;
    }

    if (field.value == null || field.value === '' || typeof field.value === 'object') {
        return '';
    }

    const rawValue = String(field.value);

    return looksLikeSalesforceId(rawValue) ? '' : rawValue;
};

const isReferenceFieldColumn = (column = {}, objectColumns = []) => {
    if (column.lookupId || isRecordTypeColumn(column)) {
        return true;
    }

    const fieldApiName = column.fieldApiName || column.fieldName || '';

    if (fieldApiName.includes('.')) {
        return true;
    }

    const lookupKey = getReferenceLookupKey(column);
    const meta = objectColumns.find((col) => col.fieldApiName === lookupKey);

    return (meta?.dataType || '').toLowerCase().includes('reference');
};

const cloneManagerColumns = (columns = []) =>
    columns.map((column) => ({ ...column }));

const toManagerColumns = (listViewColumns = [], objectColumns = []) => {
    const labelByField = new Map(
        objectColumns.map((col) => [col.fieldApiName, col.label])
    );

    return listViewColumns.map((col) => {
        const fieldApiName = col.fieldApiName || col.fieldName || col.label;

        return {
            key: resolveColumnStorageKey(col),
            label: col.label || labelByField.get(fieldApiName) || fieldApiName,
            fieldName: fieldApiName,
            lookupId: col.lookupId || null,
            type: 'text',
            sortable: true,
            visible: true
        };
    });
};

const toDefaultManagerColumns = (fieldApiNames = [], objectColumns = []) => {
    const labelByField = new Map(
        objectColumns.map((col) => [col.fieldApiName, col.label])
    );

    return fieldApiNames.map((fieldApiName) => ({
        key: fieldApiName,
        label: labelByField.get(fieldApiName) || fieldApiName,
        fieldName: fieldApiName,
        type: 'text',
        sortable: true,
        visible: true
    }));
};

const getActiveDisplayColumns = (managerColumns = []) =>
    managerColumns
        .filter((column) => column.visible !== false)
        .map((column) => column.fieldName || column.key);

/**
 * LWR list-view experience: switch Salesforce list views, view records,
 * configure columns/filters, and create or update list views via uiListsApi.
 */
export default class ArcListView extends LightningElement {
    static renderMode = 'light';

    /** Object API name, e.g. Envelope__c */
    @api objectApiName = 'Envelope__c';
    /** Panel title shown in the toolbar */
    @api title = 'Envelopes';
    /** Default list view API name when first loading */
    @api defaultListViewApiName = 'All';
    /** Required stable id used to store pinned list views for this table */
    _tableId = '';

    @api
    get tableId() {
        return this._tableId;
    }

    set tableId(value) {
        const nextTableId = (value || '').trim();

        if (nextTableId === this._tableId) {
            return;
        }

        this._tableId = nextTableId;
        this._appliedPinnedListView = false;
        this._preferenceResolved = false;
        this.listViewPreference = null;
    }

    /** Show client-side search above the table (enabled by default) */
    @api enableSearch;
    /** Placeholder for the search input */
    @api searchPlaceholder = 'Search...';

    _pageSize = DEFAULT_TABLE_PAGE_SIZE;
    @api
    get pageSize() {
        return this._pageSize;
    }
    set pageSize(value) {
        const parsed = Number(value);
        this._pageSize =
            Number.isFinite(parsed) && parsed > 0
                ? Math.floor(parsed)
                : DEFAULT_TABLE_PAGE_SIZE;
    }

    _pageSizeOptions = DEFAULT_TABLE_PAGE_SIZE_OPTIONS;
    @api
    get pageSizeOptions() {
        return this._pageSizeOptions;
    }
    set pageSizeOptions(value) {
        this._pageSizeOptions =
            Array.isArray(value) && value.length
                ? [...value]
                : DEFAULT_TABLE_PAGE_SIZE_OPTIONS;
    }

    @track listViews = [];
    @track columns = [];
    @track sourceTableRows = [];
    @track draftManagerColumns = [];
    @track draftFilters = [];

    selectedListViewApiName;
    errorMessage;
    isLoading = true;
    showCreateModal = false;
    showSettingsModal = false;
    settingsTab = 'columns';
    createLabel = '';
    createError;
    settingsError;
    isCreating = false;
    isSavingSettings = false;
    isDeletingListView = false;
    filterLogicString = '';
    draftFilterLogic = '';
    columnManagerKey = 0;
    objectColumns = [];
    objectInfo;
    currentListViewLabel = '';
    searchTerm = '';
    tableSortField = '';
    tableSortDirection = SORT_ASC;
    listViewPreference = null;
    _rawListRecords = [];
    _optionalFields;
    _optionalFieldsSignature = '';
    _referenceResolutionToken = 0;
    _stylesLoaded = false;
    _pageRef;
    _appliedPinnedListView = false;
    _preferenceResolved = false;
    _listInfosWire;
    _listInfoWire;
    _recordsWire;
    _listObjectInfoWire;

    connectedCallback() {
        if (!this.selectedListViewApiName) {
            this.selectedListViewApiName = this.defaultListViewApiName;
        }
        if (!this._stylesLoaded) {
            this._stylesLoaded = true;
            Promise.all([
                loadStyle(this, diversifyStyles),
                loadStyle(this, envelopeWizardStyles),
            ]).catch(() => {
                /* Theme CSS optional if inline/component CSS covers layout */
            });
        }
    }

    @wire(CurrentPageReference)
    wiredPageReference(pageRef) {
        this._pageRef = pageRef;
    }

    get isSearchEnabled() {
        return this.enableSearch !== false;
    }

    get listViewFetchSize() {
        return LIST_VIEW_FETCH_SIZE;
    }

    get hasColumns() {
        return this.columns && this.columns.length > 0;
    }

    get tableColumns() {
        return (this.columns || []).map((col) => {
            const fieldApiName = col.fieldApiName;

            return {
                label: col.label,
                fieldName: resolveColumnStorageKey(col),
                type: this.resolveColumnType(fieldApiName, col),
                sortable: true,
                sortType: 'text',
                isLink: !col.lookupId && fieldApiName === 'Name'
            };
        });
    }

    get enableTablePagination() {
        return true;
    }

    get linkQueryParamObjectApiNames() {
        return usesQueryParamRecordRoute(this.objectApiName)
            ? this.objectApiName
            : '';
    }

    get tableEmptyMessage() {
        if (this.isLoading) {
            return 'Loading…';
        }

        if (this.searchTerm.trim() && this.sourceTableRows.length > 0) {
            return 'No results found.';
        }

        return 'No records to display.';
    }

    get filteredTableRows() {
        const term = this.searchTerm.trim().toLowerCase();
        const rows = this.sourceTableRows || [];

        return rows.filter((row) => {
            if (!term) {
                return true;
            }

            const haystack = (this.columns || [])
                .map((column) => row[resolveColumnStorageKey(column)])
                .filter((value) => value !== null && value !== undefined && value !== '')
                .join(' ')
                .toLowerCase();

            return haystack.includes(term);
        });
    }

    get displayTableRows() {
        const rows = this.filteredTableRows;

        if (!this.tableSortField) {
            return rows;
        }

        return sortRecords(
            rows,
            this.tableSortField,
            this.tableSortDirection,
            this.tableColumns,
            (record, sortField, column) =>
                this.resolveTableSortValue(record, sortField, column)
        );
    }

    resolveTableSortValue(record, sortField, column) {
        if (!record || !sortField) {
            return null;
        }

        const sortFieldName = column?.sortFieldName || sortField;
        const primaryValue = record[sortFieldName];

        if (
            primaryValue !== null &&
            primaryValue !== undefined &&
            primaryValue !== ''
        ) {
            return primaryValue;
        }

        if (sortFieldName !== sortField) {
            const fallbackValue = record[sortField];

            if (
                fallbackValue !== null &&
                fallbackValue !== undefined &&
                fallbackValue !== ''
            ) {
                return fallbackValue;
            }
        }

        return primaryValue;
    }

    handleTableSort(event) {
        const fieldName = event.detail?.fieldName;

        if (!fieldName) {
            return;
        }

        this.tableSortDirection = resolveSortDirection(
            fieldName,
            this.tableSortField,
            this.tableSortDirection
        );
        this.tableSortField = fieldName;
    }

    isReferenceColumn(column) {
        return isReferenceFieldColumn(column, this.objectColumns);
    }

    resolveMissingReferenceLabels() {
        const pendingReferenceIds = new Set();
        const pendingReferenceCells = [];
        const pendingRecordTypeIds = new Set();
        const pendingRecordTypeCells = [];

        (this.sourceTableRows || []).forEach((row, rowIndex) => {
            (this.columns || []).forEach((column) => {
                if (!this.isReferenceColumn(column)) {
                    return;
                }

                const fieldApiName = column.fieldApiName || column.fieldName || '';
                const columnType = this.resolveColumnType(fieldApiName, column);

                if (columnType === 'userid') {
                    return;
                }

                const storageKey = resolveColumnStorageKey(column);
                const refKey = `${REFERENCE_REF_PREFIX}${storageKey}`;
                const recordId = row[refKey];

                if (!recordId || row[storageKey]) {
                    return;
                }

                if (isRecordTypeColumn(column)) {
                    pendingRecordTypeIds.add(recordId);
                    pendingRecordTypeCells.push({ rowIndex, storageKey, recordId });
                    return;
                }

                pendingReferenceIds.add(recordId);
                pendingReferenceCells.push({ rowIndex, storageKey, recordId });
            });
        });

        if (!pendingReferenceIds.size && !pendingRecordTypeIds.size) {
            return;
        }

        const resolutionToken = ++this._referenceResolutionToken;
        const resolutionTasks = [];

        if (pendingReferenceIds.size) {
            resolutionTasks.push(
                resolveReferenceLabels({
                    recordIds: [...pendingReferenceIds]
                }).then((labelById) => ({
                    labelById,
                    pendingCells: pendingReferenceCells
                }))
            );
        }

        if (pendingRecordTypeIds.size) {
            resolutionTasks.push(
                resolveRecordTypeLabels({
                    objectApiName: this.objectApiName,
                    recordTypeIds: [...pendingRecordTypeIds]
                }).then((labelById) => ({
                    labelById,
                    pendingCells: pendingRecordTypeCells
                }))
            );
        }

        Promise.all(resolutionTasks)
            .then((results) => {
                if (resolutionToken !== this._referenceResolutionToken) {
                    return;
                }

                const updatedRows = (this.sourceTableRows || []).map((row) => ({
                    ...row
                }));
                let hasChanges = false;

                results.forEach(({ labelById, pendingCells }) => {
                    pendingCells.forEach(({ rowIndex, storageKey, recordId }) => {
                        const label = labelById?.[recordId];

                        if (!label) {
                            return;
                        }

                        updatedRows[rowIndex][storageKey] = label;
                        hasChanges = true;
                    });
                });

                if (hasChanges) {
                    this.sourceTableRows = updatedRows;
                }
            })
            .catch(() => {
                /* Keep blank cells when label resolution fails. */
            });
    }

    remapSourceTableRows() {
        if (!this.columns.length || !this._rawListRecords.length) {
            this.sourceTableRows = [];
            return;
        }

        this._referenceResolutionToken += 1;
        this.sourceTableRows = this._rawListRecords.map((rec) =>
            this.mapRecordToTableRow(rec)
        );
        this.resolveMissingReferenceLabels();
    }

    get listViewOptions() {
        return (this.listViews || []).map((lv) => ({
            ...lv,
            selected: lv.value === this.selectedListViewApiName
        }));
    }

    get isListViewPinned() {
        const preference = this.listViewPreference;

        return Boolean(
            preference?.pinned &&
                preference.listViewApiName &&
                preference.listViewApiName === this.selectedListViewApiName
        );
    }

    get pinIconName() {
        return this.isListViewPinned ? 'utility:pinned' : 'utility:pin';
    }

    get pinButtonClass() {
        const stateClass = this.isListViewPinned
            ? 'arc-list-view__pin--active'
            : 'arc-list-view__pin--inactive';

        return `div-btn div-btn--icon arc-list-view__pin ${stateClass}`;
    }

    get pinButtonTitle() {
        return this.isListViewPinned
            ? 'Unpin default list view for this table'
            : 'Pin current list view as default for this table';
    }

    get normalizedTableId() {
        return (this.tableId || '').trim();
    }

    get hasTableId() {
        return Boolean(this.normalizedTableId) && this.normalizedTableId !== 'arc-list-view';
    }

    get showTableIdError() {
        return this.isDesignMode && !this.hasTableId;
    }

    get isDesignMode() {
        return isExperienceBuilderDesignMode(this._pageRef);
    }

    get isPinDisabled() {
        return !this.hasTableId;
    }

    get hasError() {
        return !!this.errorMessage;
    }

    get optionalFields() {
        return this._optionalFields;
    }

    buildOptionalFieldsList() {
        if (!this.columns.length) {
            return [];
        }

        const relationshipContext = buildRelationshipContext(this.objectInfo);
        const fields = new Set();

        this.columns.forEach((col) => {
            const fieldApiName = col.fieldApiName || col.fieldName;
            const lookupKey = col.lookupId || null;

            if (lookupKey) {
                fields.add(`${this.objectApiName}.${lookupKey}`);
                return;
            }

            if (fieldApiName?.includes('.')) {
                const relationshipName = fieldApiName.split('.')[0];
                const lookupFieldApiName = getLookupFieldForRelationshipName(
                    relationshipName,
                    relationshipContext
                );

                if (lookupFieldApiName) {
                    fields.add(`${this.objectApiName}.${lookupFieldApiName}`);
                }

                return;
            }

            if (fieldApiName) {
                fields.add(`${this.objectApiName}.${fieldApiName}`);
                return;
            }

            const meta = this.objectColumns.find(
                (objectColumn) => objectColumn.fieldApiName === fieldApiName
            );
            const dataType = (meta?.dataType || '').toLowerCase();

            if (dataType.includes('reference')) {
                fields.add(`${this.objectApiName}.${fieldApiName}`);
            }
        });

        fields.add(`${this.objectApiName}.Id`);
        return [...fields].sort();
    }

    syncOptionalFields() {
        const nextFields = this.buildOptionalFieldsList();
        const signature = nextFields.join('|');

        if (signature === this._optionalFieldsSignature) {
            return;
        }

        this._optionalFieldsSignature = signature;
        this._optionalFields = nextFields.length ? nextFields : undefined;
    }

    get settingsTabs() {
        return [
            {
                id: 'columns',
                label: 'Select Fields to Display',
                active: this.settingsTab === 'columns',
                className:
                    this.settingsTab === 'columns'
                        ? 'arc-list-view__tab arc-list-view__tab--active'
                        : 'arc-list-view__tab'
            },
            {
                id: 'filters',
                label: 'Filters',
                active: this.settingsTab === 'filters',
                className:
                    this.settingsTab === 'filters'
                        ? 'arc-list-view__tab arc-list-view__tab--active'
                        : 'arc-list-view__tab'
            }
        ];
    }

    get isColumnsTab() {
        return this.settingsTab === 'columns';
    }

    get isFiltersTab() {
        return this.settingsTab === 'filters';
    }

    get hasDraftFilters() {
        return this.draftFilters.length > 0;
    }

    get defaultManagerColumns() {
        return toDefaultManagerColumns(
            DEFAULT_ENVELOPE_COLUMNS,
            this.objectColumns
        );
    }

    get filterableObjectColumns() {
        return (this.objectColumns || []).filter((col) => col.filterable);
    }

    get filterFieldOptions() {
        return this.filterableObjectColumns.map((col) => ({
            label: col.label,
            value: col.fieldApiName
        }));
    }

    @wire(getListObjectInfo, { objectApiName: '$objectApiName' })
    wiredListObjectInfo(result) {
        this._listObjectInfoWire = result;
        const { data, error } = result;
        if (data) {
            this.objectColumns = data.columns || [];
        } else if (error) {
            this.objectColumns = [];
        }
    }

    @wire(getObjectInfo, { objectApiName: '$objectApiName' })
    wiredObjectInfo({ data, error }) {
        if (data) {
            this.objectInfo = data;
            this.syncOptionalFields();
            this.remapSourceTableRows();
            return;
        }

        if (error) {
            this.objectInfo = undefined;
        }
    }

    @wire(getListViewPreference, {
        applicationName: ARC_APPLICATION_NAME,
        tableId: '$normalizedTableId'
    })
    wiredListViewPreference({ data, error }) {
        if (!this.normalizedTableId) {
            this._preferenceResolved = true;
            this.listViewPreference = null;
            return;
        }

        this._preferenceResolved = true;

        if (data) {
            const preference = parseListViewPreference(data.entryJson);
            this.listViewPreference = preference;
            this.applyPinnedListViewIfNeeded();
            return;
        }

        if (error) {
            this.listViewPreference = null;
            this.applyPinnedListViewIfNeeded();
        }
    }

    @wire(getListInfosByObjectName, {
        objectApiName: '$objectApiName',
        pageSize: 100,
        recentListsOnly: false
    })
    wiredListInfos(result) {
        this._listInfosWire = result;
        const { data, error } = result;
        if (data) {
            const lists = data.lists || [];
            this.listViews = lists.map((item) => ({
                label: item.label || item.apiName,
                value: item.apiName
            }));
            if (
                !this.applyPinnedListViewIfNeeded() &&
                this._preferenceResolved &&
                (!this.selectedListViewApiName ||
                    !this.listViews.some(
                        (lv) => lv.value === this.selectedListViewApiName
                    ))
            ) {
                this.selectedListViewApiName =
                    this.listViews[0]?.value || this.defaultListViewApiName;
            }
            this.errorMessage = undefined;
        } else if (error) {
            this.errorMessage = this.reduceError(error);
            this.isLoading = false;
        }
    }

    @wire(getListInfoByName, {
        objectApiName: '$objectApiName',
        listViewApiName: '$selectedListViewApiName'
    })
    wiredListInfo(result) {
        this._listInfoWire = result;
        const { data, error } = result;
        if (data) {
            const displayColumns = data.displayColumns || [];
            this.columns = displayColumns.map((col) =>
                normalizeListViewColumn({
                    fieldApiName: col.fieldApiName || col.fieldName || col.label,
                    label: col.label || col.fieldApiName,
                    lookupId: col.lookupId || null
                })
            );
            this.syncOptionalFields();
            this.currentListViewLabel = data.label || this.selectedListViewApiName;
            this.filterLogicString = data.filterLogicString || '';
            this.errorMessage = undefined;
            this.remapSourceTableRows();
        } else if (error && this.selectedListViewApiName) {
            this.errorMessage = this.reduceError(error);
            this.columns = [];
            this.sourceTableRows = [];
        }
    }

    @wire(getListRecordsByName, {
        objectApiName: '$objectApiName',
        listViewApiName: '$selectedListViewApiName',
        optionalFields: '$optionalFields',
        pageSize: '$listViewFetchSize'
    })
    wiredRecords(result) {
        this._recordsWire = result;
        const { data, error } = result;

        if (!data && !error) {
            return;
        }

        this.isLoading = false;
        if (data) {
            this._rawListRecords = data.records || [];
            this.remapSourceTableRows();
            this.errorMessage = undefined;
        } else if (error && this.selectedListViewApiName && this.optionalFields) {
            this.errorMessage = this.reduceError(error);
            this._rawListRecords = [];
            this.sourceTableRows = [];
            this._referenceResolutionToken += 1;
        }
    }

    mapRecordToTableRow(rec) {
        const id = rec?.fields?.Id?.value || rec?.id;
        const row = {
            id,
            objectApiName: this.objectApiName
        };
        const recordFields = rec?.fields || {};
        const relationshipContext = buildRelationshipContext(this.objectInfo);

        this.columns.forEach((col) => {
            const storageKey = resolveColumnStorageKey(col);
            const fieldApiName = col.fieldApiName || col.fieldName || '';
            const fieldNode = resolveListFieldNode(
                recordFields,
                col,
                relationshipContext
            );
            const isReferenceColumn = this.isReferenceColumn(col);
            const columnType = this.resolveColumnType(fieldApiName, col);
            const displayValue = getDisplayValueFromField(fieldNode, fieldApiName);
            const lookupRecordId = extractLookupRecordIdForColumn(
                recordFields,
                col,
                fieldNode,
                relationshipContext
            );
            const recordTypeDisplayValue = isRecordTypeColumn(col)
                ? getRecordTypeDisplayValue(rec, lookupRecordId)
                : '';

            if (displayValue || recordTypeDisplayValue) {
                row[storageKey] = displayValue || recordTypeDisplayValue;
                return;
            }

            if (isReferenceColumn && columnType === 'userid' && lookupRecordId) {
                row[storageKey] = lookupRecordId;
                return;
            }

            if (isReferenceColumn && lookupRecordId) {
                row[storageKey] = '';
                row[`${REFERENCE_REF_PREFIX}${storageKey}`] = lookupRecordId;
                return;
            }

            row[storageKey] = getSimpleFieldValue(
                fieldNode,
                (name) => this.isNumericFieldType(name, col),
                fieldApiName
            );
        });

        return row;
    }

    isNumericFieldType(fieldApiName, column = null) {
        const dataType = (
            this.getColumnMeta(fieldApiName, column)?.dataType || ''
        ).toLowerCase();

        return (
            dataType.includes('currency') ||
            dataType.includes('double') ||
            dataType.includes('int') ||
            dataType.includes('percent') ||
            dataType === 'number'
        );
    }

    resolveColumnType(fieldApiName, column = null) {
        const meta = this.getColumnMeta(fieldApiName, column);
        const dataType = (meta?.dataType || '').toLowerCase();

        if (
            dataType.includes('currency') ||
            dataType.includes('double') ||
            dataType.includes('percent')
        ) {
            return 'currency';
        }

        if (
            dataType.includes('int') ||
            dataType === 'number'
        ) {
            return 'number';
        }

        if (dataType.includes('date')) {
            return 'date';
        }

        if (this.isUserReferenceColumn(meta)) {
            return 'userid';
        }

        return 'text';
    }

    isUserReferenceColumn(meta) {
        const dataType = (meta?.dataType || '').toLowerCase();

        if (!dataType.includes('reference')) {
            return false;
        }

        const referenceEntities = meta?.referenceToEntities || meta?.referenceTo || [];

        return referenceEntities.some(
            (entity) =>
                entity === 'User' ||
                entity?.objectApiName === 'User' ||
                entity?.apiName === 'User'
        );
    }

    getColumnMeta(fieldApiName, column = null) {
        if (column?.lookupId) {
            return (
                this.objectColumns.find(
                    (col) => col.fieldApiName === column.lookupId
                ) || null
            );
        }

        if (fieldApiName?.includes('.')) {
            const leafFieldName = fieldApiName.split('.').pop();
            return (
                this.objectColumns.find(
                    (col) => col.fieldApiName === leafFieldName
                ) || null
            );
        }

        return (
            this.objectColumns.find((col) => col.fieldApiName === fieldApiName) ||
            null
        );
    }

    getOperatorLabel(operator) {
        return OPERATOR_LABELS[operator] || operator;
    }

    buildOperatorOptions(fieldApiName) {
        const meta = this.getColumnMeta(fieldApiName);
        const operators = meta?.supportedFilterOperators?.length
            ? meta.supportedFilterOperators
            : Object.keys(OPERATOR_LABELS);
        return operators.map((operator) => ({
            label: this.getOperatorLabel(operator),
            value: operator
        }));
    }

    buildPicklistOptions(fieldApiName) {
        const meta = this.getColumnMeta(fieldApiName);
        return (meta?.picklistValues || []).map((entry) => ({
            label: entry.label || entry.value,
            value: entry.value
        }));
    }

    initDraftEditor(sourceColumns, sourceFilters, sourceFilterLogic) {
        const columnsForEditor =
            sourceColumns?.length > 0
                ? sourceColumns
                : DEFAULT_ENVELOPE_COLUMNS.map((fieldApiName) => ({
                      fieldApiName,
                      label: fieldApiName
                  }));

        this.draftManagerColumns = cloneManagerColumns(
            toManagerColumns(columnsForEditor, this.objectColumns)
        );
        this.columnManagerKey += 1;

        this.draftFilters = (sourceFilters || []).map((filter, index) =>
            this.buildDraftFilterRow(filter, index)
        );
        this.draftFilterLogic =
            sourceFilterLogic || this.buildDefaultFilterLogic(this.draftFilters.length);
    }

    buildDraftFilterRow(filter, index) {
        const fieldApiName = filter.fieldApiName;
        const meta = this.getColumnMeta(fieldApiName);
        const operatorOptions = this.buildOperatorOptions(fieldApiName).map(
            (opt) => ({
                ...opt,
                selected: opt.value === filter.operator
            })
        );
        const picklistOptions = this.buildPicklistOptions(fieldApiName).map(
            (opt) => ({
                ...opt,
                selected:
                    opt.value === (filter.operandLabels?.[0] || filter.operandValue)
            })
        );
        const operandValue = (filter.operandLabels || [])
            .filter((val) => val != null && val !== '')
            .join('; ');

        return {
            key: `filter-${filterKeyCounter++}`,
            index: index + 1,
            fieldApiName,
            operator: filter.operator || meta?.defaultFilterOperator || 'Equals',
            operandValue,
            operatorOptions,
            picklistOptions,
            isPicklist: (meta?.picklistValues || []).length > 0,
            fieldOptions: this.filterFieldOptions.map((opt) => ({
                ...opt,
                selected: opt.value === fieldApiName
            }))
        };
    }

    getDraftManagerColumns() {
        const columnManager =
            this.querySelector?.('c-ds-column-manager') ||
            this.template?.querySelector('c-ds-column-manager');
        return columnManager
            ? columnManager.getDraftColumns()
            : this.draftManagerColumns;
    }

    buildDefaultFilterLogic(filterCount) {
        if (filterCount <= 1) {
            return filterCount === 1 ? '1' : '';
        }
        return Array.from({ length: filterCount }, (_, i) => i + 1).join(' AND ');
    }

    buildFilteredByInfoPayload() {
        return this.draftFilters
            .map((filter) => ({
                fieldApiName: filter.fieldApiName,
                operator: filter.operator,
                operandLabels: this.parseOperandLabels(filter.operandValue)
            }))
            .filter(
                (filter) =>
                    filter.fieldApiName &&
                    filter.operator &&
                    filter.operandLabels.length > 0
            );
    }

    parseOperandLabels(value) {
        if (value == null || value === '') {
            return [];
        }
        return String(value)
            .split(';')
            .map((part) => part.trim())
            .filter(Boolean);
    }

    isFilterRowStarted(filter) {
        return (
            !!filter.fieldApiName ||
            !!filter.operator ||
            this.parseOperandLabels(filter.operandValue).length > 0
        );
    }

    validateDraftEditor() {
        if (!getActiveDisplayColumns(this.getDraftManagerColumns()).length) {
            return 'Select at least one field to display.';
        }

        for (const filter of this.draftFilters) {
            if (!this.isFilterRowStarted(filter)) {
                continue;
            }

            if (!filter.fieldApiName) {
                return 'Each filter must have a field selected.';
            }
            if (!filter.operator) {
                return 'Each filter must have an operator selected.';
            }
            if (!this.parseOperandLabels(filter.operandValue).length) {
                const meta = this.getColumnMeta(filter.fieldApiName);
                return `Enter a value for the ${meta?.label || filter.fieldApiName} filter.`;
            }
        }

        const activeFilterCount = this.buildFilteredByInfoPayload().length;
        if (activeFilterCount > 1 && !(this.draftFilterLogic || '').trim()) {
            return 'Enter filter logic when using multiple filters.';
        }

        return null;
    }

    async refreshListData() {
        this.isLoading = true;
        const refreshTasks = [];
        if (this._listInfoWire) {
            refreshTasks.push(refreshApex(this._listInfoWire));
        }
        if (this._recordsWire) {
            refreshTasks.push(refreshApex(this._recordsWire));
        }
        if (refreshTasks.length) {
            await Promise.all(refreshTasks);
        }
    }

    handleListViewChange(event) {
        this.selectedListViewApiName = event.target.value;
        this.searchTerm = '';
        this.tableSortField = '';
        this.tableSortDirection = SORT_ASC;
        this._optionalFieldsSignature = '';
        this._rawListRecords = [];
        this._referenceResolutionToken += 1;
        this.isLoading = true;
    }

    handlePinToggle() {
        if (!this.hasTableId) {
            return;
        }

        const nextPinned = !this.isListViewPinned;
        const preference = this.buildCurrentListViewPreference(nextPinned);

        this.listViewPreference = preference;
        this.persistListViewPreference(preference);
    }

    applyPinnedListViewIfNeeded() {
        if (
            this._appliedPinnedListView ||
            !this._preferenceResolved ||
            !this.listViews.length
        ) {
            return false;
        }

        const preference = this.listViewPreference;

        if (!preference?.pinned || !preference.listViewApiName) {
            this._appliedPinnedListView = true;
            return false;
        }

        if (preference.tableId && preference.tableId !== this.normalizedTableId) {
            return false;
        }

        if (preference.objectApiName && preference.objectApiName !== this.objectApiName) {
            return false;
        }

        const pinnedListView = this.listViews.find(
            (listView) => listView.value === preference.listViewApiName
        );

        if (!pinnedListView) {
            return false;
        }

        this.selectedListViewApiName = pinnedListView.value;
        this._appliedPinnedListView = true;
        this.isLoading = true;
        return true;
    }

    buildCurrentListViewPreference(pinned) {
        const selectedListView = this.listViews.find(
            (listView) => listView.value === this.selectedListViewApiName
        );

        return {
            pinned,
            tableId: this.normalizedTableId,
            listViewApiName: this.selectedListViewApiName || '',
            listViewLabel:
                selectedListView?.label ||
                this.currentListViewLabel ||
                this.selectedListViewApiName ||
                '',
            objectApiName: this.objectApiName,
            updatedAt: new Date().toISOString()
        };
    }

    async persistListViewPreference(preference) {
        if (!this.normalizedTableId || !preference) {
            return;
        }

        try {
            await saveListViewPreference({
                applicationName: ARC_APPLICATION_NAME,
                tableId: this.normalizedTableId,
                preferenceJson: JSON.stringify(preference)
            });
            this.listViewPreference = preference;
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        }
    }

    handleSearchChange(event) {
        this.searchTerm = event.detail?.value ?? event.target?.value ?? '';
    }

    openCreateModal() {
        this.createLabel = '';
        this.createError = undefined;
        this.settingsTab = 'columns';
        this.initDraftEditor(this.columns, [], '');
        this.showCreateModal = true;
    }

    closeCreateModal() {
        this.showCreateModal = false;
        this.createError = undefined;
        this.isCreating = false;
    }

    openSettingsModal() {
        if (!this.selectedListViewApiName) {
            return;
        }
        this.settingsError = undefined;
        this.settingsTab = 'columns';
        const listInfo = this._listInfoWire?.data;
        const sourceFilters = listInfo?.filteredByInfo || [];
        this.initDraftEditor(
            this.columns,
            sourceFilters,
            listInfo?.filterLogicString || this.filterLogicString
        );
        this.showSettingsModal = true;
    }

    closeSettingsModal() {
        this.showSettingsModal = false;
        this.settingsError = undefined;
        this.isSavingSettings = false;
        this.isDeletingListView = false;
    }

    get isSettingsActionDisabled() {
        return this.isSavingSettings || this.isDeletingListView;
    }

    async handleSettingsDeleteClick() {
        if (
            !this.selectedListViewApiName ||
            this.isSavingSettings ||
            this.isDeletingListView
        ) {
            return;
        }

        const listViewLabel =
            this.currentListViewLabel || this.selectedListViewApiName;
        const confirmed = window.confirm(
            `Delete "${listViewLabel}"? This action cannot be undone.`
        );

        if (!confirmed) {
            return;
        }

        this.isDeletingListView = true;
        this.settingsError = undefined;

        try {
            const deletedApiName = this.selectedListViewApiName;

            await deleteListInfo({
                objectApiName: this.objectApiName,
                listViewApiName: deletedApiName
            });

            this.showSettingsModal = false;
            this.listViews = this.listViews.filter(
                (listView) => listView.value !== deletedApiName
            );

            if (this.listViewPreference?.listViewApiName === deletedApiName) {
                const clearedPreference = {
                    ...this.listViewPreference,
                    pinned: false,
                    listViewApiName: ''
                };

                await this.persistListViewPreference(clearedPreference);
            }

            this.selectedListViewApiName =
                this.listViews[0]?.value || this.defaultListViewApiName || '';
            this.searchTerm = '';
            this._optionalFieldsSignature = '';
            this._rawListRecords = [];
            this._referenceResolutionToken += 1;

            if (this._listInfosWire) {
                await refreshApex(this._listInfosWire);
            }

            await this.refreshListData();
        } catch (error) {
            this.settingsError = this.reduceError(error);
        } finally {
            this.isDeletingListView = false;
        }
    }

    handleSettingsTabClick(event) {
        this.settingsTab = event.currentTarget.dataset.tab;
    }

    handleDraftColumnsChange(event) {
        this.draftManagerColumns = cloneManagerColumns(event.detail.columns);
    }

    handleCreateLabelChange(event) {
        this.createLabel = event.target.value;
    }

    handleAddFilter() {
        const defaultField = this.filterableObjectColumns[0];
        if (!defaultField) {
            this.settingsError =
                'No filterable fields are available for this object.';
            return;
        }
        const newFilter = this.buildDraftFilterRow(
            {
                fieldApiName: defaultField.fieldApiName,
                operator: defaultField.defaultFilterOperator || 'Equals',
                operandLabels: []
            },
            this.draftFilters.length
        );
        this.draftFilters = [...this.draftFilters, newFilter];
        this.draftFilterLogic = this.buildDefaultFilterLogic(this.draftFilters.length);
        this.settingsError = undefined;
        this.createError = undefined;
    }

    handleRemoveFilter(event) {
        const filterKey = event.currentTarget.dataset.key;
        this.draftFilters = this.draftFilters
            .filter((filter) => filter.key !== filterKey)
            .map((filter, index) => ({ ...filter, index: index + 1 }));
        this.draftFilterLogic = this.buildDefaultFilterLogic(this.draftFilters.length);
    }

    handleFilterFieldChange(event) {
        const filterKey = event.currentTarget.dataset.key;
        const fieldApiName = event.target.value;
        const meta = this.getColumnMeta(fieldApiName);
        this.draftFilters = this.draftFilters.map((filter) => {
            if (filter.key !== filterKey) {
                return filter;
            }
            const operator = meta?.defaultFilterOperator || 'Equals';
            return this.buildDraftFilterRow(
                {
                    fieldApiName,
                    operator,
                    operandLabels: []
                },
                filter.index - 1
            );
        });
    }

    handleFilterOperatorChange(event) {
        const filterKey = event.currentTarget.dataset.key;
        const operator = event.target.value;
        this.draftFilters = this.draftFilters.map((filter) => {
            if (filter.key !== filterKey) {
                return filter;
            }
            return {
                ...filter,
                operator,
                operatorOptions: filter.operatorOptions.map((opt) => ({
                    ...opt,
                    selected: opt.value === operator
                }))
            };
        });
    }

    handleFilterValueChange(event) {
        const filterKey = event.currentTarget.dataset.key;
        const operandValue = event.target.value;
        this.draftFilters = this.draftFilters.map((filter) => {
            if (filter.key !== filterKey) {
                return filter;
            }
            const picklistOptions = filter.picklistOptions.map((opt) => ({
                ...opt,
                selected: opt.value === operandValue
            }));
            return {
                ...filter,
                operandValue,
                picklistOptions
            };
        });
    }

    handleFilterLogicChange(event) {
        this.draftFilterLogic = event.target.value;
    }

    buildListInfoPayload({ includeEmptyFilters = false } = {}) {
        const displayColumns = getActiveDisplayColumns(this.getDraftManagerColumns());
        const filteredByInfo = this.buildFilteredByInfoPayload();
        const payload = { displayColumns };

        if (filteredByInfo.length || includeEmptyFilters) {
            payload.filteredByInfo = filteredByInfo;
            payload.filterLogicString =
                filteredByInfo.length === 0
                    ? ''
                    : filteredByInfo.length === 1
                      ? '1'
                      : (this.draftFilterLogic || '').trim() ||
                        this.buildDefaultFilterLogic(filteredByInfo.length);
        }

        return payload;
    }

    async handleCreateSave() {
        const label = (this.createLabel || '').trim();
        if (!label) {
            this.createError = 'Enter a list view name.';
            return;
        }
        const listViewApiName = this.buildListViewApiName(label);
        if (!listViewApiName) {
            this.createError = 'List view name must include letters or numbers.';
            return;
        }

        const validationError = this.validateDraftEditor();
        if (validationError) {
            this.createError = validationError;
            return;
        }

        this.isCreating = true;
        this.createError = undefined;

        try {
            const listPayload = this.buildListInfoPayload();
            const result = await createListInfo({
                objectApiName: this.objectApiName,
                listViewApiName,
                label,
                visibility: 'Private',
                ...listPayload
            });

            const createdApiName =
                result?.apiName ||
                result?.data?.apiName ||
                listViewApiName;

            this.showCreateModal = false;
            this.selectedListViewApiName = createdApiName;
            await this.refreshListData();

            const exists = this.listViews.some((lv) => lv.value === createdApiName);
            if (!exists) {
                this.listViews = [
                    ...this.listViews,
                    { label, value: createdApiName }
                ];
            }
        } catch (error) {
            this.createError = this.reduceError(error);
        } finally {
            this.isCreating = false;
        }
    }

    async handleSettingsSave() {
        if (!this.selectedListViewApiName) {
            return;
        }

        const validationError = this.validateDraftEditor();
        if (validationError) {
            this.settingsError = validationError;
            return;
        }

        this.isSavingSettings = true;
        this.settingsError = undefined;

        try {
            const listPayload = this.buildListInfoPayload({
                includeEmptyFilters: true
            });
            await updateListInfoByName({
                objectApiName: this.objectApiName,
                listViewApiName: this.selectedListViewApiName,
                ...listPayload
            });

            this.showSettingsModal = false;
            await this.refreshListData();
        } catch (error) {
            this.settingsError = this.reduceError(error);
        } finally {
            this.isSavingSettings = false;
        }
    }

    toApiName(label) {
        if (!label) {
            return '';
        }
        let apiName = label
            .trim()
            .replace(/[^a-zA-Z0-9]+/g, '_')
            .replace(/^_+|_+$/g, '');
        if (/^[0-9]/.test(apiName)) {
            apiName = `X${apiName}`;
        }
        return apiName.substring(0, 40);
    }

    buildListViewApiName(label) {
        const base = this.toApiName(label);
        if (!base) {
            return '';
        }

        const LIST_VIEW_DEVELOPER_NAME_MAX_LENGTH = 40;
        const UNIQUE_SUFFIX_LENGTH = 8;
        const suffix = (
            typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function'
                ? crypto.randomUUID()
                : `${Date.now()}${Math.random().toString(36).slice(2)}`
        )
            .replace(/-/g, '')
            .slice(0, UNIQUE_SUFFIX_LENGTH);
        const maxBaseLength = Math.max(
            1,
            LIST_VIEW_DEVELOPER_NAME_MAX_LENGTH - 1 - suffix.length
        );

        return `${base.substring(0, maxBaseLength)}_${suffix}`;
    }

    reduceError(error) {
        if (!error) {
            return 'Unknown error';
        }
        if (Array.isArray(error.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        if (typeof error.body?.message === 'string') {
            return error.body.message;
        }
        if (typeof error.message === 'string') {
            return error.message;
        }
        try {
            return JSON.stringify(error);
        } catch {
            return 'Unexpected error';
        }
    }
}