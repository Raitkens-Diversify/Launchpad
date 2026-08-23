/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 */
import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { openRecordInNewTab } from "c/recordNavigationUtils";
import {
  DISPLAY_NOT_APPLICABLE,
  formatDisplayValue
} from "c/notificationCenterUtils";

const CONTEXT_LABELS = Object.freeze({
  objectType: "Object Type",
  triggerType: "DML Operation",
  recordId: "Record ID",
  recordLabel: "Record",
  changedByUserId: "Changed By (User ID)",
  changedByUserName: "Changed By",
  changedAt: "Changed At",
  changedFields: "Changed Fields"
});

const CONTEXT_FIELD_ORDER = Object.freeze([
  "objectType",
  "triggerType",
  "recordLabel",
  "recordId",
  "changedByUserName",
  "changedByUserId",
  "changedAt",
  "changedFields"
]);

const formatChangedAt = (value) => {
  if (!value) {
    return DISPLAY_NOT_APPLICABLE;
  }

  const parsedDate = Date.parse(String(value).replace(/\+0000$/, "Z"));
  if (Number.isNaN(parsedDate)) {
    return String(value);
  }

  return new Date(parsedDate).toLocaleString([], {
    year: "numeric",
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit"
  });
};

const buildFieldChangeNodes = (fieldChanges, parentKey) => {
  return fieldChanges.map((fieldChange, index) => {
    const nodeKey = `${parentKey}-field-${index}`;
    const children = [];

    const previousValue = fieldChange.oldDisplay ?? fieldChange.oldValue;
    const nextValue = fieldChange.newDisplay ?? fieldChange.newValue;

    children.push({
      id: `${nodeKey}-previous`,
      label: "Old Value",
      value: formatDisplayValue(previousValue),
      isLeaf: true,
      depth: 2
    });
    children.push({
      id: `${nodeKey}-next`,
      label: "New Value",
      value: formatDisplayValue(nextValue),
      isLeaf: true,
      depth: 2
    });

    if (fieldChange.apiName && fieldChange.apiName !== fieldChange.label) {
      children.push({
        id: `${nodeKey}-api`,
        label: "Field API Name",
        value: fieldChange.apiName,
        isLeaf: true,
        depth: 2
      });
    }

    return {
      id: nodeKey,
      label: fieldChange.label || fieldChange.apiName || `Field ${index + 1}`,
      isBranch: true,
      isExpanded: true,
      depth: 1,
      children
    };
  });
};

const isInsertOperation = (triggerType) => {
  const normalized = String(triggerType || "")
    .trim()
    .toLowerCase();

  return normalized === "insert" || normalized === "created" || normalized === "create";
};

const buildContextNodes = (context) => {
  const nodes = [];

  CONTEXT_FIELD_ORDER.forEach((fieldName) => {
    const value = context[fieldName];

    if (value === null || value === undefined || value === "") {
      return;
    }

    if (fieldName === "changedFields") {
      if (isInsertOperation(context.triggerType)) {
        return;
      }

      if (!Array.isArray(value) || value.length === 0) {
        return;
      }

      nodes.push({
        id: "changed-fields",
        label: CONTEXT_LABELS.changedFields,
        isBranch: true,
        isExpanded: true,
        depth: 0,
        children: buildFieldChangeNodes(value, "changed-fields")
      });
      return;
    }

    if (fieldName === "changedByUserId" && context.changedByUserName) {
      return;
    }

    if (fieldName === "recordLabel") {
      nodes.push({
        id: fieldName,
        label: CONTEXT_LABELS.recordLabel,
        value: formatDisplayValue(value),
        isLeaf: true,
        isLink: Boolean(context.recordId),
        recordId: context.recordId,
        depth: 0
      });
      return;
    }

    if (fieldName === "changedByUserName") {
      nodes.push({
        id: fieldName,
        label: CONTEXT_LABELS.changedByUserName,
        value: formatDisplayValue(value),
        isLeaf: true,
        isLink: Boolean(context.changedByUserId),
        recordId: context.changedByUserId,
        depth: 0
      });
      return;
    }

    nodes.push({
      id: fieldName,
      label: CONTEXT_LABELS[fieldName] || fieldName,
      value:
        fieldName === "changedAt" ? formatChangedAt(value) : formatDisplayValue(value),
      isLeaf: true,
      depth: 0
    });
  });

  return nodes;
};

const buildGenericNodes = (value, parentKey, depth = 0) => {
  if (value === null || value === undefined) {
    return [
      {
        id: `${parentKey}-null`,
        label: "Value",
        value: DISPLAY_NOT_APPLICABLE,
        isLeaf: true,
        depth
      }
    ];
  }

  if (Array.isArray(value)) {
    if (value.length === 0) {
      return [];
    }

    return value.map((entry, index) => {
      const nodeKey = `${parentKey}-item-${index}`;

      if (entry !== null && typeof entry === "object") {
        return {
          id: nodeKey,
          label: `Item ${index + 1}`,
          isBranch: true,
          isExpanded: depth < 1,
          depth,
          children: buildGenericNodes(entry, nodeKey, depth + 1)
        };
      }

      return {
        id: nodeKey,
        label: `Item ${index + 1}`,
        value: formatDisplayValue(entry),
        isLeaf: true,
        depth
      };
    });
  }

  if (typeof value === "object") {
    return Object.keys(value).map((key) => {
      const nodeKey = `${parentKey}-${key}`;
      const entry = value[key];

      if (entry !== null && typeof entry === "object") {
        return {
          id: nodeKey,
          label: key,
          isBranch: true,
          isExpanded: depth < 1,
          depth,
          children: buildGenericNodes(entry, nodeKey, depth + 1)
        };
      }

      return {
        id: nodeKey,
        label: key,
        value: formatDisplayValue(entry),
        isLeaf: true,
        depth
      };
    });
  }

  return [
    {
      id: `${parentKey}-value`,
      label: "Value",
      value: formatDisplayValue(value),
      isLeaf: true,
      depth
    }
  ];
};

const flattenTree = (nodes, collapsedNodeIds) => {
  const rows = [];

  nodes.forEach((node) => {
    const isExpanded = node.isBranch ? !collapsedNodeIds.has(node.id) : false;

    rows.push({
      ...node,
      isExpanded,
      toggleIcon: isExpanded ? "utility:chevrondown" : "utility:chevronright",
      rowClass: node.isLeaf
        ? "context-tree__row context-tree__row--leaf"
        : "context-tree__row context-tree__row--branch",
      indentStyle: `padding-left: ${0.375 + node.depth * 1.25}rem`
    });

    if (node.isBranch && isExpanded && node.children?.length) {
      rows.push(...flattenTree(node.children, collapsedNodeIds));
    }
  });

  return rows;
};

export default class NotificationCenterChangeContextTree extends NavigationMixin(
  LightningElement
) {
  @api changeContextJson = "";

  collapsedNodeIds = new Set();

  get hasContext() {
    return this.treeNodes.length > 0;
  }

  get parseError() {
    if (!this.changeContextJson?.trim()) {
      return "";
    }

    try {
      JSON.parse(this.changeContextJson);
      return "";
    } catch {
      return "Unable to parse change context JSON.";
    }
  }

  get treeNodes() {
    if (!this.changeContextJson?.trim()) {
      return [];
    }

    let parsedContext;
    try {
      parsedContext = JSON.parse(this.changeContextJson);
    } catch {
      return [];
    }

    const rootNodes =
      parsedContext && typeof parsedContext === "object" && !Array.isArray(parsedContext)
        ? buildContextNodes(parsedContext)
        : buildGenericNodes(parsedContext, "root");

    return flattenTree(rootNodes, this.collapsedNodeIds);
  }

  handleToggleNode = (event) => {
    event.stopPropagation();

    const nodeId = event.currentTarget.dataset.nodeId;
    if (!nodeId) {
      return;
    }

    const nextCollapsedNodeIds = new Set(this.collapsedNodeIds);
    if (nextCollapsedNodeIds.has(nodeId)) {
      nextCollapsedNodeIds.delete(nodeId);
    } else {
      nextCollapsedNodeIds.add(nodeId);
    }

    this.collapsedNodeIds = nextCollapsedNodeIds;
  };

  handleToggleNodeKeyDown = (event) => {
    if (event.key !== "Enter" && event.key !== " ") {
      return;
    }

    event.preventDefault();
    this.handleToggleNode(event);
  };

  handleRecordNavigate = (event) => {
    event.stopPropagation();
    openRecordInNewTab(this, event.currentTarget.dataset.recordId);
  };

  handleRecordNavigateKeyDown = (event) => {
    if (event.key !== "Enter" && event.key !== " ") {
      return;
    }

    event.preventDefault();
    event.stopPropagation();
    this.handleRecordNavigate(event);
  };
}