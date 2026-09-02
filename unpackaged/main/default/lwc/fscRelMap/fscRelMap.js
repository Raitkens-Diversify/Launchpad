/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-11
 */
import { LightningElement, api, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { loadStyle } from 'lightning/platformResourceLoader';
import getRelationshipTree from '@salesforce/apex/FscRelTreeController.getRelationshipTree';
import refreshRelationshipTree from '@salesforce/apex/FscRelTreeController.refreshRelationshipTree';
import refreshPersonAccountMapTree from '@salesforce/apex/FscRelTreeController.refreshPersonAccountMapTree';
import getPersonAccountMapTree from '@salesforce/apex/FscRelTreeController.getPersonAccountMapTree';
import resolveRootAccountId from '@salesforce/apex/FscRelTreeController.resolveRootAccountId';
import getMemberAccountRelationships from '@salesforce/apex/FscRelHouseholdController.getMemberAccountRelationships';
import getMemberAccountRelationshipsForAccount from '@salesforce/apex/FscRelHouseholdController.getMemberAccountRelationshipsForAccount';
import getMemberRelationshipsByMemberAccountIds from '@salesforce/apex/FscRelRelationshipTreeController.getMemberRelationshipsByMemberAccountIds';
import getMemberAccountRelationshipCounts from '@salesforce/apex/FscRelHouseholdController.getMemberAccountRelationshipCounts';
import getHouseholdFamilyCardCount from '@salesforce/apex/FscRelHouseholdController.getHouseholdFamilyCardCount';
import getHouseholdNetworkCardCount from '@salesforce/apex/FscRelHouseholdController.getHouseholdNetworkCardCount';
import getAccountMemberCounts from '@salesforce/apex/FscRelHouseholdController.getAccountMemberCounts';
import getMemberRelationshipRecordTypes from '@salesforce/apex/FscRelHouseholdController.getMemberRelationshipRecordTypes';
import fscRelTreeStyles from '@salesforce/resourceUrl/fscreltreestyles';
import FscRelManageContactRelationshipModal from 'c/fscRelManageContactRelationshipModal';
import FscRelAddClassificationAccountModal from 'c/fscRelAddClassificationAccountModal';
import {
    buildAccountViewModels,
    buildFscRelModalDescription,
    buildMemberRelationshipModalTitle,
    buildMemberViewModels,
    computePreviewPanelCenterPosition,
    dispatchToast,
    extractApexError,
    isExcludedMemberRelationshipRecordType,
    isReadOnlyMemberRelationshipRecordType,
    mapMemberAccountRelationshipsForModal
} from 'c/fscRelUtils';
import {
    applyOpenState,
    buildFullyLoadedMapTree,
    buildMapTree,
    buildPersonCentricMapTree,
    buildBusWireSegments,
    cloneDomRect,
    collectLazyExpandableMemberAccountIds,
    collectLazyExpandableAccountIds,
    collectMemberRelationCountAccountIds,
    collectEntityCentricRelatedAccountsFromTreeData,
    collectLazyExpandableEntityAccountNodes,
    collectNodeIds,
    collectWireBusGroups,
    computeVisibleMapColumnCount,
    countUniqueRelatedContactsFromRelationships,
    createInitialOpenState,
    findMapNode,
    findMemberNodeByAccountId,
    isEntityCentricMapTreeData,
    CLASSIFICATION_VALUES,
    GROUP_IDS,
    MANAGE_CLASSIFICATION_ACTION_PREFIX,
    MAP_NODE_TYPE,
    mergeLoadedGroupIds,
    toCanvasRect
} from 'c/fscRelMapUtils';

const WIRE_STROKE = '#c9c9c9';
const WIRE_WIDTH = '1.5';
const WIRE_DRAW_DELAY_MS = 300;
const WIRE_DRAW_RETRY_MS = 600;

const clearElementChildren = (element) => {
    if (!element) {
        return;
    }

    while (element.firstChild) {
        element.removeChild(element.firstChild);
    }
};

export default class FscRelMap extends NavigationMixin(LightningElement) {
    @api recordId;
    @api rootAccountId;

    wiredTreeResult;
    wiredPersonTreeResult;
    wiredResolveResult;
    apexErrorMessage = '';
    resolveErrorMessage = '';
    _resolvedRootAccountId;
    _isPersonAccount = false;
    _isResolveComplete = false;
    _householdMapHydratedKey = '';
    _personMapHydratedKey = '';
    @track treeData;
    @track personTreeData;
    @track openState = {};
    @track expandAllActive = false;
    nestedMembersByAccountId = {};
    nestedMemberRelationsByAccountId = {};
    nestedEntityRelationsByAccountId = {};
    memberRelationCountByAccountId = {};
    entityRelationCountByAccountId = {};
    accountMemberCountByAccountId = {};
    householdFamilyRecordCount = undefined;
    householdNetworkRecordCount = undefined;
    memberRelationshipRecordTypes = [];
    loadedGroupIds = {};
    @track mapBusyCount = 0;
    _pendingNestedAccountIds = new Set();
    _pendingNestedMemberRelationAccountIds = new Set();
    _pendingEntityRelationAccountIds = new Set();
    _pendingMemberRelationCountIds = new Set();
    _pendingAccountMemberCountIds = new Set();
    _pendingHouseholdFamilyCount = false;
    _pendingHouseholdNetworkCount = false;
    _wireDrawScheduled = false;
    _wireDrawFallbackTimer;
    _wireDrawRetryTimer;
    _treeResizeObserver;
    _treeResizeDebounceTimer;
    _layoutWireDrawFrame;
    _observedTreeElement;
    _layoutWireDrawPending = false;
    _resizeListener;
    _scrollListener;
    _scrollTarget;
    @track previewPanel = {
        isOpen: false,
        recordId: '',
        objectApiName: 'Account',
        memberName: '',
        sourceId: '',
        left: 24,
        top: 24
    };
    @track previewBoundary = {
        isSet: false,
        scrollLeft: 0,
        scrollTop: 0,
        clientWidth: 0,
        clientHeight: 0
    };

    connectedCallback() {
        loadStyle(this, fscRelTreeStyles).catch((error) => {
            // eslint-disable-next-line no-console
            console.error('[fscRelMap] Failed to load fscreltreestyles', error);
        });

        this._resizeListener = () => {
            this.scheduleWireDraw();
            this.refreshPreviewBoundary();
        };
        window.addEventListener('resize', this._resizeListener);
    }

    disconnectedCallback() {
        if (this._resizeListener) {
            window.removeEventListener('resize', this._resizeListener);
            this._resizeListener = undefined;
        }

        if (this._scrollTarget && this._scrollListener) {
            this._scrollTarget.removeEventListener('scroll', this._scrollListener);
            this._scrollTarget = undefined;
            this._scrollListener = undefined;
        }

        this.clearWireDrawTimers();
        this.disconnectTreeResizeObserver();
    }

    disconnectTreeResizeObserver() {
        if (this._treeResizeObserver) {
            this._treeResizeObserver.disconnect();
            this._treeResizeObserver = undefined;
        }

        this._observedTreeElement = undefined;

        if (this._treeResizeDebounceTimer) {
            clearTimeout(this._treeResizeDebounceTimer);
            this._treeResizeDebounceTimer = undefined;
        }

        if (this._layoutWireDrawFrame) {
            cancelAnimationFrame(this._layoutWireDrawFrame);
            this._layoutWireDrawFrame = undefined;
        }
    }

    renderedCallback() {
        this.bindScrollListener();
        this.bindTreeResizeObserver();
        this.scheduleWireDraw();
    }

    bindTreeResizeObserver() {
        if (typeof ResizeObserver === 'undefined') {
            return;
        }

        const tree = this.template.querySelector('.map-canvas__tree');
        if (!tree || this._observedTreeElement === tree) {
            return;
        }

        this.disconnectTreeResizeObserver();

        this._observedTreeElement = tree;
        this._treeResizeObserver = new ResizeObserver(() => {
            this.scheduleWireDrawAfterLayout();
        });
        this._treeResizeObserver.observe(tree);
    }

    scheduleWireDrawAfterLayout({ hideImmediately = false } = {}) {
        if (hideImmediately) {
            this.hideWireCanvas();
        }

        this._layoutWireDrawPending = true;

        if (this._treeResizeDebounceTimer) {
            clearTimeout(this._treeResizeDebounceTimer);
        }

        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._treeResizeDebounceTimer = setTimeout(() => {
            this._treeResizeDebounceTimer = undefined;
            this.clearWireDrawTimers();
            this._wireDrawScheduled = false;

            if (this._layoutWireDrawFrame) {
                cancelAnimationFrame(this._layoutWireDrawFrame);
            }

            this.hideWireCanvas();

            // eslint-disable-next-line @lwc/lwc/no-async-operation
            this._layoutWireDrawFrame = requestAnimationFrame(() => {
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                this._layoutWireDrawFrame = requestAnimationFrame(() => {
                    this._layoutWireDrawFrame = undefined;
                    this.updateWireSegments();
                    this.showWireCanvas();
                    this._layoutWireDrawPending = false;
                });
            });
        }, 48);
    }

    hideWireCanvas() {
        const svg = this.template.querySelector('.map-canvas__wires');

        if (svg) {
            svg.style.visibility = 'hidden';
        }
    }

    showWireCanvas() {
        const svg = this.template.querySelector('.map-canvas__wires');

        if (svg) {
            svg.style.visibility = '';
        }
    }

    bindScrollListener() {
        const body = this.template.querySelector('.map-shell__body');
        if (!body || this._scrollTarget === body) {
            return;
        }

        if (this._scrollTarget && this._scrollListener) {
            this._scrollTarget.removeEventListener('scroll', this._scrollListener);
        }

        this._scrollTarget = body;
        this._scrollListener = () => this.scheduleWireDraw();
        body.addEventListener('scroll', this._scrollListener, { passive: true });
    }

    refreshPreviewBoundary({ force = false } = {}) {
        if (!force && !this.previewPanel.isOpen) {
            return;
        }

        const body = this.template.querySelector('.map-shell__body');
        if (!body) {
            return;
        }

        this.previewBoundary = {
            isSet: true,
            scrollLeft: body.scrollLeft,
            scrollTop: body.scrollTop,
            clientWidth: body.clientWidth,
            clientHeight: body.clientHeight
        };
    }

    get recordIdForResolve() {
        return this.rootAccountId ? undefined : this.recordId;
    }

    get resolvedRootAccountId() {
        if (this.rootAccountId) {
            return this.rootAccountId;
        }

        return this._resolvedRootAccountId || undefined;
    }

    get isUnlinkedPersonCentricMap() {
        return (
            this._isResolveComplete &&
            this._isPersonAccount &&
            !this.rootAccountId &&
            !this._resolvedRootAccountId
        );
    }

    get personAccountIdForMap() {
        if (!this.isUnlinkedPersonCentricMap) {
            return undefined;
        }

        return this.recordId || undefined;
    }

    get resolvedRootAccountIdForTree() {
        if (this.isUnlinkedPersonCentricMap) {
            return undefined;
        }

        return this.resolvedRootAccountId;
    }

    get showMap() {
        if (this.isUnlinkedPersonCentricMap) {
            return Boolean(this.personTreeData);
        }

        return Boolean(this.resolvedRootAccountIdForTree);
    }


    get showResolveError() {
        return (
            Boolean(this.recordId) &&
            this._isResolveComplete &&
            Boolean(this.resolveErrorMessage)
        );
    }

    get isInitializing() {
        if (this.rootAccountId) {
            return !this.treeData && !this.apexErrorMessage;
        }

        if (!this.recordId || !this._isResolveComplete) {
            return true;
        }

        if (this._isPersonAccount && !this._resolvedRootAccountId) {
            return !this.personTreeData && !this.apexErrorMessage;
        }

        return !this.treeData && !this.apexErrorMessage;
    }

    get isLoading() {
        return (
            this.isInitializing ||
            this.isResolveWireLoading ||
            this.isTreeWireLoading
        );
    }

    get isResolveWireLoading() {
        if (this.rootAccountId || !this.recordId) {
            return false;
        }

        if (!this.wiredResolveResult) {
            return true;
        }

        return !this.wiredResolveResult.data && !this.wiredResolveResult.error;
    }

    get isTreeWireLoading() {
        if (this.isUnlinkedPersonCentricMap) {
            if (!this.wiredPersonTreeResult) {
                return true;
            }

            return !this.wiredPersonTreeResult.data && !this.wiredPersonTreeResult.error;
        }

        if (!this.resolvedRootAccountIdForTree) {
            return false;
        }

        if (!this.wiredTreeResult) {
            return true;
        }

        return !this.wiredTreeResult.data && !this.wiredTreeResult.error;
    }

    get isMapBusy() {
        return this.isTreeWireLoading || this.mapBusyCount > 0;
    }

    get loadingMessage() {
        if (this.isInitializing || this.isResolveWireLoading || this.isTreeWireLoading) {
            return 'Loading relationship map';
        }

        return 'Loading relationship data';
    }

    get householdSubtitle() {
        if (this.isUnlinkedPersonCentricMap) {
            return this.personTreeData?.name || 'Person account';
        }

        return this.treeData?.name || 'Household';
    }

    get isEntityCentricMap() {
        return isEntityCentricMapTreeData(this.treeData);
    }

    get baseMapTree() {
        if (this.isUnlinkedPersonCentricMap) {
            return buildPersonCentricMapTree({
                personTreeData: this.personTreeData,
                nestedMemberRelationsByAccountId: this.nestedMemberRelationsByAccountId,
                nestedMemberRelationCountByAccountId: this.memberRelationCountByAccountId,
                memberRelationshipRecordTypes: this.memberRelationshipRecordTypes,
                householdFamilyRecordCount: this.householdFamilyRecordCount
            });
        }

        return buildMapTree({
            treeData: this.treeData,
            nestedMembersByAccountId: this.nestedMembersByAccountId,
            nestedAccountMemberCountByAccountId: this.accountMemberCountByAccountId,
            nestedMemberRelationsByAccountId: this.nestedMemberRelationsByAccountId,
            nestedMemberRelationCountByAccountId: this.memberRelationCountByAccountId,
            nestedEntityRelationsByAccountId: this.nestedEntityRelationsByAccountId,
            entityRelationCountByAccountId: this.entityRelationCountByAccountId,
            memberRelationshipRecordTypes: this.memberRelationshipRecordTypes,
            loadedGroupIds: this.loadedGroupIds,
            householdFamilyRecordCount: this.householdFamilyRecordCount,
            householdNetworkRecordCount: this.householdNetworkRecordCount
        });
    }

    get displayTree() {
        const baseTree = this.baseMapTree;
        if (!baseTree) {
            return null;
        }

        return this.decorateMapTreeForRender(
            applyOpenState(baseTree, this.openState)
        );
    }

    decorateMapTreeForRender(node) {
        if (!node) {
            return null;
        }

        const children = (node.children || []).map((child) =>
            this.decorateMapTreeForRender(child)
        );

        return {
            ...node,
            rowKey: `${node.id}:${node.isOpen === true ? "open" : "closed"}`,
            isClassificationGroup: node.childNodeKind === "classificationGroup",
            children
        };
    }

    get personFamilyGroup() {
        if (!this.isUnlinkedPersonCentricMap || !this.displayTree?.isOpen) {
            return null;
        }

        return (
            (this.displayTree.children || []).find((child) => child.isLazyFamilyGroup) || null
        );
    }

    get personRelationshipGroups() {
        if (!this.isUnlinkedPersonCentricMap || !this.displayTree?.isOpen) {
            return [];
        }

        return (this.displayTree.children || []).filter(
            (child) => child.nodeType === MAP_NODE_TYPE.RELATIONSHIP_GROUP
        );
    }

    get mapCanvasStyle() {
        const columnCount = computeVisibleMapColumnCount(this.displayTree);

        return `--map-visible-columns: ${columnCount};`;
    }

    get isMapFullyExpanded() {
        return this.expandAllActive;
    }

    get expandCollapseLabel() {
        return this.isMapFullyExpanded ? 'Collapse all' : 'Expand all';
    }

    get wireBusGroups() {
        return collectWireBusGroups(this.displayTree, []);
    }

    get showTreeError() {
        return Boolean(this.apexErrorMessage);
    }

    initializePersonMapState(treeData) {
        this.personTreeData = treeData;
        this.expandAllActive = false;
        this.apexErrorMessage = '';
        this.clearNestedMapCaches();
        this.loadedGroupIds = {};
        this.openState = createInitialOpenState(
            buildPersonCentricMapTree({
                personTreeData: treeData,
                nestedMemberRelationsByAccountId: {},
                nestedMemberRelationCountByAccountId: {},
                memberRelationshipRecordTypes: this.memberRelationshipRecordTypes
            })
        );
        void this.loadPersonCentricCounts();
    }

    clearNestedMapCaches() {
        this.nestedMembersByAccountId = {};
        this.nestedMemberRelationsByAccountId = {};
        this.nestedEntityRelationsByAccountId = {};
        this.memberRelationCountByAccountId = {};
        this.entityRelationCountByAccountId = {};
        this.accountMemberCountByAccountId = {};
        this.householdFamilyRecordCount = undefined;
        this.householdNetworkRecordCount = undefined;
    }

    applyRefreshedPersonMapData(treeData) {
        this.personTreeData = treeData;
        this.apexErrorMessage = '';
        this.nestedMemberRelationsByAccountId = {};
        this.memberRelationCountByAccountId = {};
        this.householdFamilyRecordCount = undefined;
        void this.loadPersonCentricCounts();
    }

    applyRefreshedHouseholdTreeData(treeData) {
        this.treeData = treeData;
        this.apexErrorMessage = '';
        this.clearNestedMapCaches();
    }

    async reloadOpenLazyMapData() {
        const baseTree = this.baseMapTree;
        if (!baseTree) {
            return;
        }

        let needsClientRelations = false;
        const accountIdsToReload = new Set();
        const memberAccountIdsToReload = new Set();

        Object.keys(this.openState).forEach((nodeId) => {
            if (this.openState[nodeId] !== true) {
                return;
            }

            const node = findMapNode(baseTree, nodeId);
            if (!node) {
                return;
            }

            if (node.isLazyFamilyGroup || node.isLazyNetworkGroup) {
                needsClientRelations = true;
            }

            if (node.isLazyGroup) {
                this.loadedGroupIds = {
                    ...this.loadedGroupIds,
                    [nodeId]: true
                };
            }

            if (
                node.nodeType === MAP_NODE_TYPE.ACCOUNT &&
                node.isLazyExpandable &&
                node.accountId
            ) {
                if (node.showManageMemberRelationships) {
                    memberAccountIdsToReload.add(node.accountId);
                } else {
                    accountIdsToReload.add(node.accountId);
                }
            }

            if (
                node.nodeType === MAP_NODE_TYPE.MEMBER &&
                node.isLazyExpandable &&
                node.accountId
            ) {
                memberAccountIdsToReload.add(node.accountId);
            }
        });

        const reloadTasks = [];

        if (needsClientRelations) {
            reloadTasks.push(this.loadMemberRelationsForHouseholdClients());
        }

        accountIdsToReload.forEach((accountId) => {
            reloadTasks.push(this.loadNestedMembersForAccountId(accountId));
        });

        memberAccountIdsToReload.forEach((accountId) => {
            reloadTasks.push(this.loadMemberRelationsForAccountId(accountId, true));
        });

        if (reloadTasks.length > 0) {
            await Promise.all(reloadTasks);
        }

        await this.loadMemberRelationCountsForVisibleMembers();
    }

    async loadPersonCentricCounts() {
        if (!this.isUnlinkedPersonCentricMap) {
            return;
        }

        const accountId = this.personTreeData?.members?.[0]?.accountId;
        if (!accountId) {
            return;
        }

        this.beginMapBusy();

        try {
            await Promise.all([
                this.loadMemberRelationCountsForAccountIds([accountId]),
                this.loadHouseholdFamilyRecordCount([accountId])
            ]);

            const relationCount = this.memberRelationCountByAccountId[accountId];

            if (relationCount > 0) {
                await this.loadMemberRelationsForAccountId(accountId);
            }
        } finally {
            this.endMapBusy();
        }
    }

    @wire(getPersonAccountMapTree, { personAccountId: '$personAccountIdForMap' })
    wiredPersonAccountMap(result) {
        this.wiredPersonTreeResult = result;
        const hydrationKey = this.personAccountIdForMap || '';

        if (!hydrationKey) {
            this._personMapHydratedKey = '';
            return;
        }

        if (result.data && this._personMapHydratedKey !== hydrationKey) {
            this.initializePersonMapState(result.data);
            this._personMapHydratedKey = hydrationKey;
            return;
        }

        if (result.error) {
            this.personTreeData = undefined;
            this._personMapHydratedKey = '';
            this.apexErrorMessage = extractApexError(
                result.error,
                'Failed to load person relationship map data.'
            );
        }
    }

    @wire(resolveRootAccountId, { accountId: '$recordIdForResolve' })
    wiredResolveRootAccount(result) {
        this.wiredResolveResult = result;

        if (this.rootAccountId) {
            return;
        }

        if (result.error) {
            this._isResolveComplete = true;
            this._resolvedRootAccountId = undefined;
            this._isPersonAccount = false;
            this.resolveErrorMessage = extractApexError(
                result.error,
                'Failed to resolve root account.'
            );
            return;
        }

        if (!result.data && !result.error) {
            this._isResolveComplete = false;
            return;
        }

        this._isResolveComplete = true;
        this._isPersonAccount = Boolean(result.data.isPersonAccount);
        this._resolvedRootAccountId = result.data.rootAccountId || undefined;
        this.resolveErrorMessage = '';
    }

    @wire(getMemberRelationshipRecordTypes)
    wiredMemberRelationshipRecordTypes({ data, error }) {
        if (data) {
            this.memberRelationshipRecordTypes = Array.isArray(data) ? data : [];

            if (this.treeData && this._householdMapHydratedKey) {
                void this.loadInitialMapCounts();
            }

            if (this.personTreeData && this._personMapHydratedKey) {
                void this.loadPersonCentricCounts();
            }

            return;
        }

        if (error) {
            this.memberRelationshipRecordTypes = [];
        }
    }

    @wire(getRelationshipTree, { rootAccountId: '$resolvedRootAccountIdForTree' })
    wiredRelationshipTree(result) {
        this.wiredTreeResult = result;

        if (!this.resolvedRootAccountIdForTree) {
            return;
        }

        if (result.data) {
            const hydrationKey = this.resolvedRootAccountIdForTree || '';

            if (this._householdMapHydratedKey !== hydrationKey) {
                this.treeData = result.data;
                this.expandAllActive = false;
                this.apexErrorMessage = '';
                this.clearNestedMapCaches();
                this.loadedGroupIds = {};
                this.openState = createInitialOpenState(
                    buildMapTree({
                        treeData: result.data,
                        nestedMembersByAccountId: {},
                        nestedMemberRelationsByAccountId: {},
                        nestedMemberRelationCountByAccountId: {},
                        memberRelationshipRecordTypes: this.memberRelationshipRecordTypes,
                        loadedGroupIds: {}
                    })
                );
                this._householdMapHydratedKey = hydrationKey;
                void this.loadInitialMapCounts();
            }

            return;
        }

        if (result.error) {
            this.treeData = undefined;
            this._householdMapHydratedKey = '';
            this.apexErrorMessage = extractApexError(
                result.error,
                'Failed to load relationship map data.'
            );
        }
    }

    @api
    async refresh() {
        if (!this.personAccountIdForMap && !this.resolvedRootAccountIdForTree) {
            return;
        }

        this.beginMapBusy();

        try {
            if (this.personAccountIdForMap) {
                const data = await refreshPersonAccountMapTree({
                    personAccountId: this.personAccountIdForMap
                });

                if (!this.personTreeData) {
                    this.initializePersonMapState(data);
                } else {
                    this.applyRefreshedPersonMapData(data);
                }

                return;
            }

            const data = await refreshRelationshipTree({
                rootAccountId: this.resolvedRootAccountIdForTree
            });

            if (!this.treeData) {
                this.treeData = data;
                this.expandAllActive = false;
                this.apexErrorMessage = '';
                this.clearNestedMapCaches();
                this.loadedGroupIds = {};
                this.openState = createInitialOpenState(
                    buildMapTree({
                        treeData: data,
                        nestedMembersByAccountId: {},
                        nestedMemberRelationsByAccountId: {},
                        nestedMemberRelationCountByAccountId: {},
                        memberRelationshipRecordTypes: this.memberRelationshipRecordTypes,
                        loadedGroupIds: {}
                    })
                );
                this._householdMapHydratedKey = this.resolvedRootAccountIdForTree || '';
                void this.loadInitialMapCounts();
            } else {
                this.applyRefreshedHouseholdTreeData(data);
                await this.reloadOpenLazyMapData();
            }

            this.scheduleWireDraw();
        } catch (error) {
            this.apexErrorMessage = extractApexError(
                error,
                'Failed to refresh relationship map data.'
            );
        } finally {
            this.endMapBusy();
        }
    }

    beginMapBusy() {
        this.mapBusyCount += 1;
    }

    endMapBusy() {
        this.mapBusyCount = Math.max(0, this.mapBusyCount - 1);
    }

    handleExpandCollapseToggle() {
        if (this.isMapBusy) {
            return;
        }

        if (this.isMapFullyExpanded) {
            this.handleCollapseAll();
            return;
        }

        void this.handleExpandAll();
    }

    async handleExpandAll() {
        const baseTree = this.baseMapTree;
        if (!baseTree || this.isMapBusy) {
            return;
        }

        this.beginMapBusy();

        try {
            if (this.isUnlinkedPersonCentricMap) {
                const accountId = this.personTreeData?.members?.[0]?.accountId;

                if (accountId && this.memberRelationCountByAccountId[accountId] !== 0) {
                    await this.loadMemberRelationsForAccountId(accountId);
                }

                const expandedTree = this.baseMapTree || baseTree;
                const nextOpenState = {};
                collectNodeIds(expandedTree).forEach((nodeId) => {
                    nextOpenState[nodeId] = true;
                });
                this.openState = nextOpenState;
                this.expandAllActive = true;
                this.scheduleWireDraw();
                return;
            }

            if (this.isEntityCentricMap) {
                await this.loadEntityRelationCountsForEntityMap();

                let pendingNodes = collectLazyExpandableEntityAccountNodes(baseTree).filter(
                    ({ accountId }) =>
                        this.entityRelationCountByAccountId[accountId] !== 0 &&
                        !this.nestedEntityRelationsByAccountId[accountId]
                );

                while (pendingNodes.length > 0) {
                    await Promise.all(
                        pendingNodes.map(({ accountId }) =>
                            this.loadEntityRelationsForAccountId(accountId)
                        )
                    );

                    pendingNodes = collectLazyExpandableEntityAccountNodes(
                        this.baseMapTree || baseTree
                    ).filter(
                        ({ accountId }) =>
                            this.entityRelationCountByAccountId[accountId] !== 0 &&
                            !this.nestedEntityRelationsByAccountId[accountId]
                    );
                }

                const nextOpenState = {};
                collectNodeIds(this.baseMapTree || baseTree).forEach((nodeId) => {
                    nextOpenState[nodeId] = true;
                });
                this.openState = nextOpenState;
                this.expandAllActive = true;
                this.scheduleWireDraw();
                return;
            }

            if (!this.treeData) {
                return;
            }

            this.loadedGroupIds = mergeLoadedGroupIds(this.loadedGroupIds);
            await this.loadMemberRelationCountsForVisibleMembers();

            const relatedAccountIds = buildAccountViewModels(this.treeData.relatedAccounts || [])
                .map((account) => account.accountId)
                .filter(Boolean);

            await Promise.all(
                relatedAccountIds.map((accountId) => this.loadNestedMembersForAccountId(accountId))
            );

            let fullyLoadedTree = buildFullyLoadedMapTree({
                treeData: this.treeData,
                nestedMembersByAccountId: this.nestedMembersByAccountId,
                nestedMemberRelationsByAccountId: this.nestedMemberRelationsByAccountId,
                nestedMemberRelationCountByAccountId: this.memberRelationCountByAccountId,
                nestedEntityRelationsByAccountId: this.nestedEntityRelationsByAccountId,
                entityRelationCountByAccountId: this.entityRelationCountByAccountId,
                memberRelationshipRecordTypes: this.memberRelationshipRecordTypes,
                loadedGroupIds: this.loadedGroupIds
            });

            if (!fullyLoadedTree) {
                return;
            }

            const memberAccountIds = collectMemberRelationCountAccountIds(
                fullyLoadedTree,
                {
                    treeData: this.treeData,
                    loadedGroupIds: this.loadedGroupIds
                }
            );
            const nextMemberRelations = { ...this.nestedMemberRelationsByAccountId };

            memberAccountIds.forEach((accountId) => {
                if (this.memberRelationCountByAccountId[accountId] === 0) {
                    nextMemberRelations[accountId] = [];
                }
            });

            this.nestedMemberRelationsByAccountId = nextMemberRelations;

            await Promise.all(
                memberAccountIds.map(async (accountId) => {
                    if (this.memberRelationCountByAccountId[accountId] === 0) {
                        return;
                    }

                    await this.loadMemberRelationsForAccountId(accountId);
                })
            );

            fullyLoadedTree = buildFullyLoadedMapTree({
                treeData: this.treeData,
                nestedMembersByAccountId: this.nestedMembersByAccountId,
                nestedMemberRelationsByAccountId: this.nestedMemberRelationsByAccountId,
                nestedMemberRelationCountByAccountId: this.memberRelationCountByAccountId,
                nestedEntityRelationsByAccountId: this.nestedEntityRelationsByAccountId,
                entityRelationCountByAccountId: this.entityRelationCountByAccountId,
                memberRelationshipRecordTypes: this.memberRelationshipRecordTypes,
                loadedGroupIds: this.loadedGroupIds
            });

            if (!fullyLoadedTree) {
                return;
            }

            const nextOpenState = {};
            collectNodeIds(fullyLoadedTree).forEach((nodeId) => {
                nextOpenState[nodeId] = true;
            });
            this.openState = nextOpenState;
            this.expandAllActive = true;
            this.scheduleWireDraw();
        } finally {
            this.endMapBusy();
        }
    }

    handleCollapseAll() {
        const baseTree = this.baseMapTree;
        if (!baseTree) {
            return;
        }

        const nextOpenState = {};
        collectNodeIds(baseTree).forEach((nodeId) => {
            nextOpenState[nodeId] = false;
        });
        nextOpenState[baseTree.id] = true;
        this.openState = nextOpenState;
        this.expandAllActive = false;
        this.nestedMemberRelationsByAccountId = {};
        this.scheduleWireDraw();
    }

    async loadInitialMapCounts() {
        if (this.isEntityCentricMap) {
            await this.loadEntityRelationCountsForEntityMap();
            return;
        }

        await this.loadMemberRelationCountsForVisibleMembers();
    }

    async loadEntityRelationCountsForEntityMap() {
        if (!this.isEntityCentricMap || !this.treeData?.rootAccountId) {
            return;
        }

        const rootAccountId = this.treeData.rootAccountId;
        const directChildren = collectEntityCentricRelatedAccountsFromTreeData(this.treeData);
        const pendingIds = directChildren
            .map((account) => account.accountId)
            .filter(
                (accountId) =>
                    accountId && this.entityRelationCountByAccountId[accountId] === undefined
            );

        if (pendingIds.length === 0) {
            return;
        }

        await Promise.all(
            pendingIds.map((accountId) =>
                this.loadEntityRelationCountForAccountId(accountId)
            )
        );
    }

    async loadEntityRelationCountForAccountId(accountId) {
        if (!accountId || this.entityRelationCountByAccountId[accountId] !== undefined) {
            return;
        }

        try {
            const data = await getRelationshipTree({ rootAccountId: accountId });
            const relatedAccounts =
                collectEntityCentricRelatedAccountsFromTreeData(data);

            this.entityRelationCountByAccountId = {
                ...this.entityRelationCountByAccountId,
                [accountId]: relatedAccounts.length
            };
        } catch (error) {
            dispatchToast(this, {
                title: 'Could not load relationship counts',
                message: extractApexError(
                    error,
                    'Unexpected error loading entity relationship counts.'
                ),
                variant: 'error'
            });
        } finally {
            this.scheduleWireDraw();
        }
    }

    async loadEntityRelationsForAccountId(accountId) {
        if (!accountId) {
            return;
        }

        if (this.nestedEntityRelationsByAccountId[accountId]) {
            return;
        }

        if (this._pendingEntityRelationAccountIds.has(accountId)) {
            return;
        }

        this._pendingEntityRelationAccountIds.add(accountId);

        try {
            const data = await getRelationshipTree({ rootAccountId: accountId });
            const relatedAccounts =
                collectEntityCentricRelatedAccountsFromTreeData(data);

            this.nestedEntityRelationsByAccountId = {
                ...this.nestedEntityRelationsByAccountId,
                [accountId]: relatedAccounts
            };
            this.entityRelationCountByAccountId = {
                ...this.entityRelationCountByAccountId,
                [accountId]: relatedAccounts.length
            };
        } catch (error) {
            dispatchToast(this, {
                title: 'Could not load relationships',
                message: extractApexError(error, 'Unexpected error loading account relationships.'),
                variant: 'error'
            });
        } finally {
            this._pendingEntityRelationAccountIds.delete(accountId);
            this.scheduleWireDraw();
        }
    }

    async loadMemberRelationCountsForVisibleMembers() {
        if (this.isEntityCentricMap) {
            return;
        }

        const baseTree = this.baseMapTree;
        if (!baseTree) {
            return;
        }

        const clientAccounts = this.isUnlinkedPersonCentricMap
            ? buildAccountViewModels(this.personTreeData?.clientAccounts || [])
            : buildAccountViewModels(this.treeData?.clientAccounts || []);
        const accountIds = collectMemberRelationCountAccountIds(baseTree, {
            treeData: this.isUnlinkedPersonCentricMap
                ? this.personTreeData
                : this.treeData,
            loadedGroupIds: this.loadedGroupIds
        });
        const memberAccountIds = clientAccounts
            .map((account) => account.accountId)
            .filter(Boolean);

        await Promise.all([
            this.loadMemberRelationCountsForAccountIds(accountIds),
            this.loadAccountMemberCountsForAccountIds(
                collectLazyExpandableAccountIds(baseTree)
            ),
            this.loadHouseholdFamilyRecordCount(memberAccountIds),
            this.loadHouseholdNetworkRecordCount(memberAccountIds)
        ]);
    }

    async loadHouseholdFamilyRecordCount(memberAccountIds = []) {
        const pendingIds = [...new Set(memberAccountIds.filter(Boolean))];

        if (pendingIds.length === 0) {
            this.householdFamilyRecordCount = 0;
            return;
        }

        if (this._pendingHouseholdFamilyCount) {
            return;
        }

        this._pendingHouseholdFamilyCount = true;

        try {
            const count = await getHouseholdFamilyCardCount({
                memberAccountIds: pendingIds
            });
            this.householdFamilyRecordCount = count ?? 0;
        } catch (error) {
            dispatchToast(this, {
                title: 'Could not load family count',
                message: extractApexError(
                    error,
                    'Unexpected error loading household family count.'
                ),
                variant: 'error'
            });
        } finally {
            this._pendingHouseholdFamilyCount = false;
            this.scheduleWireDraw();
        }
    }

    async loadHouseholdNetworkRecordCount(memberAccountIds = []) {
        const pendingIds = [...new Set(memberAccountIds.filter(Boolean))];

        if (pendingIds.length === 0) {
            this.householdNetworkRecordCount = 0;
            return;
        }

        if (this._pendingHouseholdNetworkCount) {
            return;
        }

        this._pendingHouseholdNetworkCount = true;

        try {
            const count = await getHouseholdNetworkCardCount({
                memberAccountIds: pendingIds
            });
            this.householdNetworkRecordCount = count ?? 0;
        } catch (error) {
            dispatchToast(this, {
                title: 'Could not load network count',
                message: extractApexError(
                    error,
                    'Unexpected error loading household network count.'
                ),
                variant: 'error'
            });
        } finally {
            this._pendingHouseholdNetworkCount = false;
            this.scheduleWireDraw();
        }
    }

    async loadMemberRelationCountsForAccountIds(accountIds = []) {
        const pendingIds = [...new Set(accountIds)].filter(
            (accountId) =>
                accountId &&
                this.memberRelationCountByAccountId[accountId] === undefined &&
                !this.nestedMemberRelationsByAccountId[accountId] &&
                !this._pendingMemberRelationCountIds.has(accountId)
        );

        if (pendingIds.length === 0) {
            return;
        }

        pendingIds.forEach((accountId) =>
            this._pendingMemberRelationCountIds.add(accountId)
        );

        try {
            const counts = await getMemberAccountRelationshipCounts({
                accountIds: pendingIds
            });
            const normalizedCounts = {};

            pendingIds.forEach((accountId) => {
                normalizedCounts[accountId] = 0;
            });

            Object.keys(counts || {}).forEach((accountId) => {
                normalizedCounts[accountId] = counts[accountId];
            });

            this.memberRelationCountByAccountId = {
                ...this.memberRelationCountByAccountId,
                ...normalizedCounts
            };
        } catch (error) {
            dispatchToast(this, {
                title: 'Could not load relationship counts',
                message: extractApexError(
                    error,
                    'Unexpected error loading member relationship counts.'
                ),
                variant: 'error'
            });
        } finally {
            pendingIds.forEach((accountId) =>
                this._pendingMemberRelationCountIds.delete(accountId)
            );
            this.scheduleWireDraw();
        }
    }

    async loadAccountMemberCountsForAccountIds(accountIds = []) {
        const pendingIds = [...new Set(accountIds)].filter(
            (accountId) =>
                accountId &&
                this.accountMemberCountByAccountId[accountId] === undefined &&
                !this.nestedMembersByAccountId[accountId] &&
                !this._pendingAccountMemberCountIds.has(accountId)
        );

        if (pendingIds.length === 0) {
            return;
        }

        pendingIds.forEach((accountId) =>
            this._pendingAccountMemberCountIds.add(accountId)
        );

        try {
            const counts = await getAccountMemberCounts({
                accountIds: pendingIds
            });
            const normalizedCounts = {};

            pendingIds.forEach((accountId) => {
                normalizedCounts[accountId] = 0;
            });

            Object.keys(counts || {}).forEach((accountId) => {
                normalizedCounts[accountId] = counts[accountId];
            });

            this.accountMemberCountByAccountId = {
                ...this.accountMemberCountByAccountId,
                ...normalizedCounts
            };
        } catch (error) {
            dispatchToast(this, {
                title: 'Could not load member counts',
                message: extractApexError(
                    error,
                    'Unexpected error loading account member counts.'
                ),
                variant: 'error'
            });
        } finally {
            pendingIds.forEach((accountId) =>
                this._pendingAccountMemberCountIds.delete(accountId)
            );
            this.scheduleWireDraw();
        }
    }

    get showPreviewPanel() {
        return this.previewPanel.isOpen && Boolean(this.previewPanel.recordId);
    }

    get activePreviewSourceId() {
        return this.previewPanel.sourceId || '';
    }

    handleCardAction(event) {
        const detail = event.detail || {};

        if (detail.action === 'preview') {
            event.stopPropagation();
            this.handlePreviewRequest(detail);
            return;
        }

        if (detail.action === 'toggle') {
            event.stopPropagation();
            this.handleNodeToggle(detail.nodeId);
            return;
        }

        if (detail.action === 'layoutchange') {
            event.stopPropagation();
            this.scheduleWireDrawAfterLayout({ hideImmediately: true });
            return;
        }

        if (String(detail.action || '').startsWith('manageaar:')) {
            event.stopPropagation();
            this.openManageMemberRelationshipModal({
                memberAccountId: detail.accountId,
                memberName: detail.memberName,
                memberIconName: detail.memberIconName,
                recordTypeDeveloperName: detail.recordTypeDeveloperName,
                recordTypeLabel: detail.recordTypeLabel,
                reciprocalRoleRecordTypeDeveloperName:
                    detail.reciprocalRoleRecordTypeDeveloperName,
                selectMemberFromClients: detail.selectMemberFromClients === true
            });
            return;
        }

        if (String(detail.action || '').startsWith(MANAGE_CLASSIFICATION_ACTION_PREFIX)) {
            event.stopPropagation();
            const classificationValue = String(detail.action).slice(
                MANAGE_CLASSIFICATION_ACTION_PREFIX.length
            );

            void this.openAddClassificationAccountModal({
                classificationValue,
                classificationLabel:
                    detail.classificationLabel ||
                    detail.classificationValue ||
                    classificationValue
            });
            return;
        }

        if (detail.action === 'record') {
            event.stopPropagation();
            if (detail.contactId && detail.objectApiName === 'Contact') {
                this.handleContactNavigation(detail.contactId);
                return;
            }

            this.handleRecordNavigation(detail.accountId);
        }
    }

    handlePreviewRequest(detail) {
        const recordId = detail?.contactId || detail?.accountId;
        if (!recordId) {
            return;
        }

        const wasOpen = this.previewPanel.isOpen;
        let nextLeft = this.previewPanel.left;
        let nextTop = this.previewPanel.top;

        if (!wasOpen) {
            const scrollContainer = this.template.querySelector('.map-shell__body');
            this.refreshPreviewBoundary({ force: true });
            const position = computePreviewPanelCenterPosition(scrollContainer, {
                scrollRelative: true
            });
            nextLeft = position.left;
            nextTop = position.top;
        } else {
            this.refreshPreviewBoundary({ force: true });
        }

        this.previewPanel = {
            isOpen: true,
            recordId,
            objectApiName: detail?.objectApiName || 'Account',
            memberName: detail.memberName || '',
            sourceId: detail.sourceId || detail.nodeId || '',
            left: nextLeft,
            top: nextTop
        };
    }

    handlePreviewClose() {
        this.previewPanel = {
            ...this.previewPanel,
            isOpen: false,
            recordId: '',
            objectApiName: 'Account',
            memberName: '',
            sourceId: ''
        };
    }

    handleRecordNavigation(accountId) {
        if (!accountId) {
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: accountId,
                objectApiName: 'Account',
                actionName: 'view'
            }
        });
    }

    handleContactNavigation(contactId) {
        if (!contactId) {
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: contactId,
                objectApiName: 'Contact',
                actionName: 'view'
            }
        });
    }

    async handleNodeToggle(nodeId) {
        const baseTree = this.baseMapTree;
        if (!baseTree || !nodeId) {
            return;
        }

        const node = findMapNode(baseTree, nodeId);
        const currentOpen =
            this.openState[nodeId] === true ||
            (this.openState[nodeId] !== false && Boolean(node?.defaultOpen));
        const nextOpen = !currentOpen;

        if (!nextOpen) {
            this.expandAllActive = false;

            this.openState = {
                ...this.openState,
                [nodeId]: false
            };
            this.scheduleWireDraw();
            return;
        }

        if (this.isMapBusy) {
            return;
        }

        this.openState = {
            ...this.openState,
            [nodeId]: true
        };
        this.scheduleWireDraw();

        this.beginMapBusy();

        try {
            if (node?.isLazyFamilyGroup || node?.isLazyNetworkGroup) {
                if (this.isUnlinkedPersonCentricMap) {
                    const accountId = this.personTreeData?.members?.[0]?.accountId;

                    if (accountId) {
                        await this.loadMemberRelationsForAccountId(accountId);
                    }
                } else {
                    await this.loadMemberRelationsForHouseholdClients();
                }
            } else if (node?.isLazyGroup) {
                this.loadedGroupIds = {
                    ...this.loadedGroupIds,
                    [nodeId]: true
                };
                await this.loadMemberRelationCountsForVisibleMembers();
            } else if (
                node?.isEntityCentricRelatedAccount &&
                node?.isLazyExpandable &&
                node?.accountId
            ) {
                const cachedCount = this.entityRelationCountByAccountId[node.accountId];
                if (cachedCount === undefined || cachedCount !== 0) {
                    await this.loadEntityRelationsForAccountId(node.accountId);
                }
            } else if (
                node?.nodeType === MAP_NODE_TYPE.ACCOUNT &&
                node?.showManageMemberRelationships &&
                node?.isLazyExpandable &&
                node?.accountId &&
                !node?.isEntityCentricRelatedAccount
            ) {
                const cachedCount = this.memberRelationCountByAccountId[node.accountId];
                if (cachedCount === undefined || cachedCount !== 0) {
                    await this.loadMemberRelationsForAccountId(node.accountId);
                }
            } else if (
                node?.nodeType === MAP_NODE_TYPE.ACCOUNT &&
                node?.isLazyExpandable &&
                node?.accountId &&
                !node?.isEntityCentricRelatedAccount
            ) {
                await this.loadNestedMembersForAccountId(node.accountId);
            } else if (
                node?.nodeType === MAP_NODE_TYPE.MEMBER &&
                (node?.showManageMemberRelationships || node?.showManageRelatedContacts) &&
                node?.isLazyExpandable &&
                node?.accountId
            ) {
                const cachedCount = this.memberRelationCountByAccountId[node.accountId];
                if (cachedCount === undefined || cachedCount !== 0) {
                    await this.loadMemberRelationsForAccountId(node.accountId);
                }
            } else if (node?.isClassificationGroupNode) {
                // Classification groups such as COI already include their children.
            } else {
                await this.loadNestedMembersForNode(nodeId);
            }
        } catch (error) {
            this.openState = {
                ...this.openState,
                [nodeId]: false
            };
        } finally {
            this.endMapBusy();
        }

        this.scheduleWireDraw();
    }

    async loadNestedMembersForAccountId(accountId) {
        if (!accountId) {
            return;
        }

        if (this.nestedMembersByAccountId[accountId]) {
            return;
        }

        if (this._pendingNestedAccountIds.has(accountId)) {
            return;
        }

        this._pendingNestedAccountIds.add(accountId);

        try {
            const data = await getRelationshipTree({ rootAccountId: accountId });
            const members = data?.members || [];
            this.nestedMembersByAccountId = {
                ...this.nestedMembersByAccountId,
                [accountId]: members
            };
            this.accountMemberCountByAccountId = {
                ...this.accountMemberCountByAccountId,
                [accountId]: members.length
            };
        } catch (error) {
            dispatchToast(this, {
                title: 'Could not load members',
                message: extractApexError(error, 'Unexpected error loading account members.'),
                variant: 'error'
            });
        } finally {
            this._pendingNestedAccountIds.delete(accountId);
            this.scheduleWireDraw();
        }
    }

    async loadMemberRelationsForHouseholdClients() {
        const members = this.resolveClientMembers();
        const accountIds = members.map((member) => member.accountId).filter(Boolean);

        if (accountIds.length === 0) {
            return;
        }

        try {
            const relationshipsByAccountId = await getMemberRelationshipsByMemberAccountIds({
                memberAccountIds: accountIds
            });
            const nextNestedMemberRelations = { ...this.nestedMemberRelationsByAccountId };
            const nextMemberRelationCounts = { ...this.memberRelationCountByAccountId };

            accountIds.forEach((accountId) => {
                const relationships = Array.isArray(relationshipsByAccountId?.[accountId])
                    ? relationshipsByAccountId[accountId]
                    : [];
                nextNestedMemberRelations[accountId] = relationships;
                nextMemberRelationCounts[accountId] =
                    countUniqueRelatedContactsFromRelationships(relationships);
            });

            this.nestedMemberRelationsByAccountId = nextNestedMemberRelations;
            this.memberRelationCountByAccountId = nextMemberRelationCounts;
        } catch (error) {
            dispatchToast(this, {
                title: 'Could not load member relationships',
                message: extractApexError(
                    error,
                    'Unexpected error loading member account relationships.'
                ),
                variant: 'error'
            });
        } finally {
            this.scheduleWireDraw();
        }
    }

    async loadMemberRelationsForAccountId(accountId, forceReload = false) {
        if (!accountId) {
            return;
        }

        if (!forceReload && this.nestedMemberRelationsByAccountId[accountId]) {
            return;
        }

        if (this._pendingNestedMemberRelationAccountIds.has(accountId)) {
            return;
        }

        this._pendingNestedMemberRelationAccountIds.add(accountId);

        try {
            const data = await getMemberAccountRelationshipsForAccount({
                memberAccountId: accountId
            });
            const relationships = Array.isArray(data) ? data : [];
            this.nestedMemberRelationsByAccountId = {
                ...this.nestedMemberRelationsByAccountId,
                [accountId]: relationships
            };
            this.memberRelationCountByAccountId = {
                ...this.memberRelationCountByAccountId,
                [accountId]: countUniqueRelatedContactsFromRelationships(relationships)
            };
        } catch (error) {
            dispatchToast(this, {
                title: 'Could not load member relationships',
                message: extractApexError(
                    error,
                    'Unexpected error loading member account relationships.'
                ),
                variant: 'error'
            });
        } finally {
            this._pendingNestedMemberRelationAccountIds.delete(accountId);
            this.scheduleWireDraw();
        }
    }

    async loadNestedMembersForNode(nodeId) {
        const baseTree = this.baseMapTree;
        const node = findMapNode(baseTree, nodeId);

        if (!node?.accountId || node.nodeType !== 'account') {
            return;
        }

        await this.loadNestedMembersForAccountId(node.accountId);
    }

    async loadNestedMembersForOpenAccounts() {
        const baseTree = this.baseMapTree;
        if (!baseTree) {
            return;
        }

        const accountNodeIds = [];
        const walk = (node) => {
            if (node?.nodeType === 'account') {
                accountNodeIds.push(node.id);
            }

            (node?.children || []).forEach(walk);
        };
        walk(baseTree);

        await Promise.all(
            accountNodeIds.map((nodeId) => this.loadNestedMembersForNode(nodeId))
        );
    }

    resolveClientMembers() {
        const clientAccounts = this.isUnlinkedPersonCentricMap
            ? buildAccountViewModels(this.personTreeData?.clientAccounts || [])
            : buildAccountViewModels(this.treeData?.clientAccounts || []);

        return clientAccounts
            .filter((account) => account.accountId)
            .map((account) => ({
                accountId: account.accountId,
                name: account.name || account.label || ""
            }));
    }

    resolveClientMemberAccountIds() {
        return this.resolveClientMembers()
            .map((member) => member.accountId)
            .filter(Boolean);
    }

    resolveTargetMemberAccountId() {
        if (!this._isPersonAccount || !this.recordId) {
            return null;
        }

        return this.recordId;
    }

    resolveTargetMemberName(accountId) {
        if (!accountId) {
            return '';
        }

        if (this.isUnlinkedPersonCentricMap) {
            const personMember = this.personTreeData?.members?.[0];

            if (personMember?.accountId === accountId) {
                return personMember.name || this.personTreeData?.name || '';
            }
        }

        const memberMatch = buildMemberViewModels(this.treeData?.members || []).find(
            (member) => member.accountId === accountId
        );

        if (memberMatch?.name) {
            return memberMatch.name;
        }

        const clientMatch = buildAccountViewModels(this.treeData?.clientAccounts || []).find(
            (account) => account.accountId === accountId
        );

        return clientMatch?.name || '';
    }

    resolveMemberIconName(accountId) {
        if (!accountId || !this.baseMapTree) {
            return '';
        }

        const mapNode = findMemberNodeByAccountId(this.baseMapTree, accountId);
        if (mapNode?.iconName) {
            return mapNode.iconName;
        }

        if (this.isUnlinkedPersonCentricMap) {
            const personMember = this.personTreeData?.members?.[0];
            if (personMember?.accountId === accountId) {
                return 'standard:contact';
            }
        }

        const memberMatch = buildMemberViewModels(this.treeData?.members || []).find(
            (member) => member.accountId === accountId
        );
        if (memberMatch?.iconName) {
            return memberMatch.iconName;
        }

        const clientMatch = buildAccountViewModels(this.treeData?.clientAccounts || []).find(
            (account) => account.accountId === accountId
        );

        return clientMatch?.iconName || '';
    }

    async loadClientMemberRelationships(recordTypeDeveloperName) {
        const clientMembers = this.resolveClientMembers();
        const relationships = [];

        await Promise.all(
            clientMembers.map(async (member) => {
                try {
                    const rows = await getMemberAccountRelationships({
                        memberAccountId: member.accountId,
                        recordTypeDeveloperName
                    });

                    (Array.isArray(rows) ? rows : []).forEach((relationship) => {
                        relationships.push({
                            ...relationship,
                            memberAccountId:
                                relationship.memberAccountId || member.accountId,
                            memberAccountName: member.name
                        });
                    });
                } catch (error) {
                    // Skip members that fail to load; modal still opens for others.
                }
            })
        );

        return relationships;
    }

    async openManageMemberRelationshipModal({
        memberAccountId,
        memberName,
        memberIconName,
        recordTypeDeveloperName,
        recordTypeLabel,
        reciprocalRoleRecordTypeDeveloperName,
        selectMemberFromClients = false
    }) {
        if (!recordTypeDeveloperName) {
            return;
        }

        if (isExcludedMemberRelationshipRecordType(recordTypeDeveloperName)) {
            return;
        }

        const isReadOnlyRecordType =
            isReadOnlyMemberRelationshipRecordType(recordTypeDeveloperName);
        const targetMemberAccountId = this.resolveTargetMemberAccountId();
        let useClientSelectMode = selectMemberFromClients;

        if (isReadOnlyRecordType && targetMemberAccountId) {
            if (useClientSelectMode || !memberAccountId) {
                memberAccountId = targetMemberAccountId;
                memberName =
                    this.resolveTargetMemberName(targetMemberAccountId) || memberName;
            }

            useClientSelectMode = false;
        }

        if (!useClientSelectMode && !memberAccountId) {
            return;
        }

        const clientMembers = useClientSelectMode
            ? this.resolveClientMembers()
            : [];
        const clientMemberAccountIds = clientMembers
            .map((member) => member.accountId)
            .filter(Boolean);
        const wasExpanded = memberAccountId
            ? this.isMemberRelationsExpanded(memberAccountId)
            : false;
        let relationships = [];
        let savedMemberAccountId = memberAccountId;

        if (useClientSelectMode) {
            try {
                relationships = await this.loadClientMemberRelationships(
                    recordTypeDeveloperName
                );
            } catch (error) {
                dispatchToast(this, {
                    title: 'Could not load member relationships',
                    message: extractApexError(
                        error,
                        'Unexpected error loading member account relationships.'
                    ),
                    variant: 'error'
                });
                return;
            }
        } else if (memberAccountId) {
            try {
                relationships = await getMemberAccountRelationships({
                    memberAccountId,
                    recordTypeDeveloperName
                });
                if (wasExpanded) {
                    const allRelationships = await getMemberAccountRelationshipsForAccount({
                        memberAccountId
                    });
                    this.nestedMemberRelationsByAccountId = {
                        ...this.nestedMemberRelationsByAccountId,
                        [memberAccountId]: Array.isArray(allRelationships)
                            ? allRelationships
                            : []
                    };
                }
            } catch (error) {
                dispatchToast(this, {
                    title: 'Could not load member relationships',
                    message: extractApexError(
                        error,
                        'Unexpected error loading member account relationships.'
                    ),
                    variant: 'error'
                });
                return;
            }
        }

        const modalTitle = buildMemberRelationshipModalTitle(
            recordTypeDeveloperName,
            recordTypeLabel,
            { isReadOnly: isReadOnlyRecordType }
        );
        const result = await FscRelManageContactRelationshipModal.open({
            size: 'medium',
            description: buildFscRelModalDescription(modalTitle),
            memberAccountId: memberAccountId || '',
            memberName: memberName || '',
            memberIconName:
                memberIconName ||
                this.resolveMemberIconName(memberAccountId) ||
                '',
            recordTypeDeveloperName,
            recordTypeLabel: recordTypeLabel || '',
            reciprocalRoleRecordTypeDeveloperName:
                reciprocalRoleRecordTypeDeveloperName || recordTypeDeveloperName,
            initialRelationships: mapMemberAccountRelationshipsForModal(relationships),
            selectMemberFromClients: useClientSelectMode,
            clientMemberAccountIds,
            clientMembers
        });

        if (result?.confirmed && result?.message) {
            dispatchToast(this, {
                title: 'Member relationships updated',
                message: result.message,
                variant: 'success'
            });
        }

        savedMemberAccountId = result?.memberAccountId || savedMemberAccountId;

        if (!savedMemberAccountId || !result?.confirmed) {
            return;
        }

        await this.refresh();

        const memberWasExpanded = this.isMemberRelationsExpanded(savedMemberAccountId);

        if (memberWasExpanded) {
            const memberNode = findMemberNodeByAccountId(
                this.baseMapTree,
                savedMemberAccountId
            );
            if (memberNode) {
                await this.loadMemberRelationsForAccountId(savedMemberAccountId, true);
                this.openState = {
                    ...this.openState,
                    [memberNode.id]: true
                };
            }
        }

        await this.loadMemberRelationCountsForVisibleMembers();
        this.scheduleWireDraw();
    }

    async openAddClassificationAccountModal({
        classificationValue,
        classificationLabel
    }) {
        const rootAccountId = this.resolvedRootAccountIdForTree;

        if (!rootAccountId || !classificationValue) {
            return;
        }

        const modalTitle = `Add ${classificationValue}`;
        const result = await FscRelAddClassificationAccountModal.open({
            size: 'small',
            description: buildFscRelModalDescription(modalTitle),
            rootAccountId,
            rootAccountName: this.householdSubtitle,
            classificationValue,
            classificationLabel: classificationValue
        });

        if (result?.confirmed && result?.message) {
            dispatchToast(this, {
                title: 'Account added',
                message: result.message,
                variant: 'success'
            });
        }

        if (!result?.confirmed) {
            return;
        }

        await this.refresh();
        this.scheduleWireDraw();
    }

    isMemberRelationsExpanded(accountId) {
        if (!accountId) {
            return false;
        }

        const memberNode = findMemberNodeByAccountId(this.baseMapTree, accountId);
        if (!memberNode) {
            return false;
        }

        return (
            this.openState[memberNode.id] === true ||
            (this.openState[memberNode.id] !== false &&
                Boolean(memberNode.defaultOpen))
        );
    }

    collectAnchorRectsFromTree() {
        const anchorRects = {};
        const wrappers = this.template.querySelectorAll('[data-anchor-id]');

        wrappers.forEach((wrapper) => {
            const nodeId = wrapper.dataset.anchorId;
            if (!nodeId) {
                return;
            }

            const cardHost = wrapper.querySelector('c-fsc-rel-map-card');
            const addCard = wrapper.querySelector('.map-card');
            const cardAnchor = cardHost || addCard || wrapper;
            const rawRect =
                cardHost && typeof cardHost.getWireAnchorRect === 'function'
                    ? cardHost.getWireAnchorRect()
                    : cardAnchor.getBoundingClientRect();
            anchorRects[nodeId] = cloneDomRect(rawRect);
        });

        this.template
            .querySelectorAll('c-fsc-rel-map-relationship-groups')
            .forEach((groupsComponent) => {
                if (typeof groupsComponent.collectAnchorRects !== 'function') {
                    return;
                }

                const groupAnchorRects = groupsComponent.collectAnchorRects();
                Object.keys(groupAnchorRects || {}).forEach((nodeId) => {
                    anchorRects[nodeId] = cloneDomRect(groupAnchorRects[nodeId]);
                });
            });

        return anchorRects;
    }

    scheduleWireDraw() {
        if (this._layoutWireDrawPending) {
            return;
        }

        if (this._wireDrawScheduled) {
            return;
        }

        this._wireDrawScheduled = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        requestAnimationFrame(() => {
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            requestAnimationFrame(() => {
                this._wireDrawScheduled = false;
                this.updateWireSegments();
            });
        });

        this.clearWireDrawTimers();
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._wireDrawFallbackTimer = setTimeout(() => {
            this.updateWireSegments();
        }, WIRE_DRAW_DELAY_MS);

        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._wireDrawRetryTimer = setTimeout(() => {
            this.updateWireSegments();
        }, WIRE_DRAW_RETRY_MS);
    }

    clearWireDrawTimers() {
        if (this._wireDrawFallbackTimer) {
            clearTimeout(this._wireDrawFallbackTimer);
            this._wireDrawFallbackTimer = undefined;
        }

        if (this._wireDrawRetryTimer) {
            clearTimeout(this._wireDrawRetryTimer);
            this._wireDrawRetryTimer = undefined;
        }
    }

    updateWireSegments() {
        const canvas = this.template.querySelector('[data-map-canvas]');
        const svg = this.template.querySelector('.map-canvas__wires');
        if (!canvas || !svg) {
            return;
        }

        const canvasRect = canvas.getBoundingClientRect();
        if (!canvasRect.width || !canvasRect.height) {
            return;
        }

        const anchorRects = this.collectAnchorRectsFromTree();
        const svgNamespace = 'http://www.w3.org/2000/svg';
        const fragment = document.createDocumentFragment();
        let segmentCount = 0;

        this.wireBusGroups.forEach((group) => {
            const parentRect = toCanvasRect(anchorRects[group.parentId], canvasRect);
            if (!parentRect) {
                return;
            }

            const childEntries = [
                ...(group.childIds || []).map((childId) => ({
                    rect: toCanvasRect(anchorRects[childId], canvasRect),
                    dashed: false
                })),
                ...(group.dashedChildIds || []).map((childId) => ({
                    rect: toCanvasRect(anchorRects[childId], canvasRect),
                    dashed: true
                }))
            ];

            buildBusWireSegments(parentRect, childEntries).forEach((segment) => {
                const path = document.createElementNS(svgNamespace, 'path');
                path.setAttribute('d', segment.d);
                path.setAttribute('fill', 'none');
                path.setAttribute('stroke', WIRE_STROKE);
                path.setAttribute('stroke-width', WIRE_WIDTH);
                path.setAttribute('stroke-linecap', 'round');
                path.setAttribute('stroke-linejoin', 'round');
                if (segment.dashed) {
                    path.setAttribute('stroke-dasharray', '4 3');
                }
                fragment.appendChild(path);
                segmentCount += 1;

                if (segment.dot) {
                    const dot = document.createElementNS(svgNamespace, 'circle');
                    dot.setAttribute('cx', String(segment.dotX));
                    dot.setAttribute('cy', String(segment.dotY));
                    dot.setAttribute('r', '2.5');
                    dot.setAttribute('fill', WIRE_STROKE);
                    fragment.appendChild(dot);
                }
            });
        });

        svg.setAttribute('width', String(Math.ceil(Math.max(canvas.scrollWidth, canvasRect.width))));
        svg.setAttribute('height', String(Math.ceil(Math.max(canvas.scrollHeight, canvasRect.height))));
        svg.setAttribute(
            'viewBox',
            `0 0 ${Math.ceil(Math.max(canvas.scrollWidth, canvasRect.width))} ${Math.ceil(Math.max(canvas.scrollHeight, canvasRect.height))}`
        );
        clearElementChildren(svg);
        svg.appendChild(fragment);

        if (segmentCount === 0 && this.wireBusGroups.length > 0) {
            this.clearWireDrawTimers();
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            this._wireDrawFallbackTimer = setTimeout(() => {
                this.updateWireSegments();
            }, WIRE_DRAW_DELAY_MS);
        }
    }
}