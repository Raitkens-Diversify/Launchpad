/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-17
 *
 * Shared helpers for anchoring fscRelMemberPopover to lightning-datatable rows.
 */
import {
  PREVIEW_PANEL_HEIGHT,
  PREVIEW_PANEL_OFFSET,
  PREVIEW_PANEL_WIDTH
} from "c/fscRelUtils";

const DEFAULT_PREVIEW_TRIGGER_LABEL = "Preview account";
const DEFAULT_FALLBACK_POSITION = Object.freeze({ left: 24, top: 120 });
const DATATABLE_PREVIEW_GAP = 0;

export const getSafeComposedPath = (event) => {
  if (!event || typeof event.composedPath !== "function") {
    return [];
  }

  try {
    return event.composedPath() || [];
  } catch {
    // Locker throws patchedComposedPathValue for some cross-boundary events.
    return [];
  }
};

const isPointerInsideRect = (event, rect) => {
  if (!rect || !Number.isFinite(event?.clientX) || !Number.isFinite(event?.clientY)) {
    return false;
  }

  return (
    event.clientX >= rect.left &&
    event.clientX <= rect.right &&
    event.clientY >= rect.top &&
    event.clientY <= rect.bottom
  );
};

const clampCanvasTop = (top, canvasHeight, panelHeight = PREVIEW_PANEL_HEIGHT) => {
  const minTop = 8;
  const maxTop = Math.max(minTop, canvasHeight - panelHeight - 8);
  return Math.min(Math.max(top, minTop), maxTop);
};

export const collectDeepElements = (root, selector) => {
  const matches = [];
  const visited = new Set();

  const visit = (node) => {
    if (!node || visited.has(node)) {
      return;
    }

    visited.add(node);

    if (node.nodeType === Node.ELEMENT_NODE && node.matches?.(selector)) {
      matches.push(node);
    }

    const searchRoot = node.shadowRoot || node;

    if (!searchRoot.querySelectorAll) {
      return;
    }

    searchRoot.querySelectorAll(selector).forEach((match) => {
      if (!matches.includes(match)) {
        matches.push(match);
      }
    });

    searchRoot.querySelectorAll(":scope > *").forEach((child) => visit(child));
  };

  visit(root);

  return matches;
};

const findPreviewIconInNode = (root) => {
  if (!root) {
    return null;
  }

  const iconCandidates = collectDeepElements(
    root,
    'svg[data-key="preview"], use[href*="preview"]'
  );

  return (
    iconCandidates.find((node) => {
      if (node.nodeName === "svg") {
        const iconKey =
          node.dataset?.key || node.getAttribute?.("data-key") || "";
        return iconKey === "preview";
      }

      return node.getAttribute?.("href")?.includes("preview");
    }) || null
  );
};

export const getPreviewAnchorRect = (button) => {
  if (!button?.getBoundingClientRect) {
    return null;
  }

  const icon = findPreviewIconInNode(button);

  return icon?.getBoundingClientRect?.() || button.getBoundingClientRect();
};

export const hasPreviewIcon = (node) => {
  if (!node) {
    return false;
  }

  if (node.nodeName === "svg") {
    const iconKey = node.dataset?.key || node.getAttribute?.("data-key") || "";
    return iconKey === "preview";
  }

  return Boolean(
    node.querySelector?.('svg[data-key="preview"], use[href*="preview"]')
  );
};

export const isPreviewTriggerNode = (
  node,
  previewTriggerLabel = DEFAULT_PREVIEW_TRIGGER_LABEL
) => {
  if (!node) {
    return false;
  }

  const title = node?.title || node?.getAttribute?.("title") || "";
  const label =
    node?.ariaLabel ||
    node?.getAttribute?.("aria-label") ||
    node?.getAttribute?.("alternative-text") ||
    "";

  if (title === previewTriggerLabel || label === previewTriggerLabel) {
    return true;
  }

  const normalizedLabel = `${title} ${label}`.trim().toLowerCase();
  const normalizedTrigger = previewTriggerLabel.trim().toLowerCase();

  if (normalizedLabel.includes(normalizedTrigger)) {
    return true;
  }

  if (node.nodeName !== "BUTTON") {
    return false;
  }

  return Boolean(
    node.querySelector?.('svg[data-key="preview"], use[href*="preview"]')
  );
};

const resolvePreviewAnchorFromEvent = (
  event,
  previewTriggerLabel = DEFAULT_PREVIEW_TRIGGER_LABEL
) => {
  const { clientX, clientY } = event;

  if (
    Number.isFinite(clientX) &&
    Number.isFinite(clientY) &&
    typeof document.elementsFromPoint === "function"
  ) {
    for (const element of document.elementsFromPoint(clientX, clientY)) {
      if (!element) {
        continue;
      }

      const button = hasPreviewIcon(element)
        ? element.closest?.("button") || element
        : isPreviewTriggerNode(element, previewTriggerLabel)
          ? element.closest?.("button") || element
          : null;

      if (!button) {
        continue;
      }

      const anchorRect = getPreviewAnchorRect(button);
      if (anchorRect) {
        return anchorRect;
      }
    }
  }

  let target = event.target;
  while (target) {
    const button =
      isPreviewTriggerNode(target, previewTriggerLabel) || hasPreviewIcon(target)
        ? target.nodeName === "BUTTON"
          ? target
          : target.closest?.("button")
        : null;

    if (button) {
      const anchorRect = getPreviewAnchorRect(button);
      if (anchorRect) {
        return anchorRect;
      }
    }

    target = target.parentElement || target.host;
  }

  const path = getSafeComposedPath(event);
  const previewIconNode = path.find((node) => hasPreviewIcon(node));
  const iconButton = previewIconNode?.closest?.("button");
  const iconAnchorRect = getPreviewAnchorRect(iconButton);

  if (iconAnchorRect) {
    return iconAnchorRect;
  }

  const trigger = path.find((node) =>
    isPreviewTriggerNode(node, previewTriggerLabel)
  );

  return getPreviewAnchorRect(trigger);
};

export const buildCanvasPreviewPosition = (
  canvasElement,
  anchorRect,
  {
    gap = DATATABLE_PREVIEW_GAP,
    panelWidth = PREVIEW_PANEL_WIDTH
  } = {}
) => {
  if (!canvasElement || !anchorRect) {
    return null;
  }

  const canvasRect = canvasElement.getBoundingClientRect();
  const minLeft = 8;
  const maxLeft = Math.max(minLeft, canvasRect.width - panelWidth - 8);
  let left = anchorRect.left - canvasRect.left - panelWidth - gap;

  if (left < minLeft) {
    left = anchorRect.right - canvasRect.left + gap;
  }

  left = Math.min(Math.max(left, minLeft), maxLeft);

  return {
    left,
    top: Math.max(8, anchorRect.top - canvasRect.top),
    useFixedPosition: false
  };
};

export const buildFixedPreviewPosition = (anchorRect) => {
  if (!anchorRect) {
    return null;
  }

  const gap = 8;
  const maxLeft = Math.max(8, window.innerWidth - PREVIEW_PANEL_WIDTH - 8);
  let left = anchorRect.left - PREVIEW_PANEL_WIDTH - gap;

  if (left < 8) {
    left = anchorRect.right + gap;
  }

  return {
    left: Math.min(Math.max(8, left), maxLeft),
    top: Math.max(8, anchorRect.top + PREVIEW_PANEL_OFFSET.y),
    useFixedPosition: true
  };
};

export const buildFixedPreviewPositionFromPoint = (x, y) => {
  if (!Number.isFinite(x) || !Number.isFinite(y)) {
    return null;
  }

  const gap = 8;
  const maxLeft = Math.max(8, window.innerWidth - PREVIEW_PANEL_WIDTH - 8);
  let left = x - PREVIEW_PANEL_WIDTH - gap;

  if (left < 8) {
    left = x + gap;
  }

  return {
    left: Math.min(Math.max(8, left), maxLeft),
    top: Math.max(8, y + PREVIEW_PANEL_OFFSET.y),
    useFixedPosition: true
  };
};

export const isPointerEventInsideElement = (event, element) => {
  if (!element) {
    return false;
  }

  const rect = element.getBoundingClientRect?.();
  if (isPointerInsideRect(event, rect)) {
    return true;
  }

  const path = getSafeComposedPath(event);
  return path.includes(element);
};

export const findDatatableRowElement = (
  datatableElement,
  datatableRows,
  rowKey,
  row
) => {
  if (!datatableElement || !rowKey) {
    return null;
  }

  const rowData =
    row ||
    (datatableRows || []).find((entry) => entry.rowKey === rowKey) ||
    null;
  const participantId = rowData?.participantId;

  if (participantId && datatableElement.shadowRoot) {
    const participantIdStr = String(participantId).toLowerCase();
    const shadowRows = datatableElement.shadowRoot.querySelectorAll("tbody tr");

    for (const rowElement of shadowRows) {
      const links = collectDeepElements(rowElement, "a");
      const hasParticipantLink = links.some((link) =>
        String(link.href || link.getAttribute?.("href") || "")
          .toLowerCase()
          .includes(participantIdStr)
      );

      if (hasParticipantLink) {
        return rowElement;
      }
    }
  }

  const rowIndex = (datatableRows || []).findIndex(
    (entry) => entry.rowKey === rowKey
  );
  if (rowIndex < 0) {
    return null;
  }

  if (datatableElement.shadowRoot) {
    const shadowRows = datatableElement.shadowRoot.querySelectorAll("tbody tr");
    if (shadowRows[rowIndex]) {
      return shadowRows[rowIndex];
    }
  }

  const rowElements = collectDeepElements(datatableElement, "tbody tr");
  return rowElements[rowIndex] || null;
};

export const findAccountLinkAnchorRectForRow = (
  rowElement,
  accountId,
  accountName
) => {
  if (!rowElement) {
    return null;
  }

  const links = collectDeepElements(rowElement, "a");
  const rowRect = rowElement.getBoundingClientRect?.();
  const rowMidpoint = rowRect
    ? rowRect.left + rowRect.width * 0.5
    : Number.POSITIVE_INFINITY;
  const accountIdStr = accountId ? String(accountId).toLowerCase() : "";
  const normalizedAccountName = (accountName || "").trim().toLowerCase();
  let idMatchRect = null;
  let idMatchLeft = -1;
  let nameMatchRect = null;
  let nameMatchLeft = -1;

  for (const link of links) {
    const href = String(
      link.href || link.getAttribute?.("href") || ""
    ).toLowerCase();
    const label = (link.textContent || "").trim().toLowerCase();
    const rect = link.getBoundingClientRect?.();

    if (!rect || rect.width <= 0 || rect.height <= 0) {
      continue;
    }

    if (rect.left < rowMidpoint) {
      continue;
    }

    if (normalizedAccountName && label === normalizedAccountName) {
      if (rect.left >= nameMatchLeft) {
        nameMatchLeft = rect.left;
        nameMatchRect = rect;
      }
    }

    if (accountIdStr && href.includes(accountIdStr)) {
      if (rect.left >= idMatchLeft) {
        idMatchLeft = rect.left;
        idMatchRect = rect;
      }
    }
  }

  return nameMatchRect || idMatchRect;
};

const findPreviewButtonInCell = (cell) => {
  if (!cell) {
    return null;
  }

  const buttons = collectDeepElements(cell, "button");

  return (
    buttons.find(
      (button) => isPreviewTriggerNode(button) || hasPreviewIcon(button)
    ) || buttons[0] ||
    null
  );
};

export const findPreviewAnchorFromActiveElement = () => {
  const activeElement = document.activeElement;

  if (!activeElement || activeElement.nodeName !== "BUTTON") {
    return null;
  }

  if (
    !isPreviewTriggerNode(activeElement) &&
    !hasPreviewIcon(activeElement)
  ) {
    return null;
  }

  return getPreviewAnchorRect(activeElement);
};

export const findPreviewButtonAnchorRectForRow = (rowElement) => {
  if (!rowElement) {
    return null;
  }

  const activeAnchorRect = findPreviewAnchorFromActiveElement();
  if (activeAnchorRect) {
    return activeAnchorRect;
  }

  const anchorRects = [];

  const collectAnchorRect = (button) => {
    const anchorRect = getPreviewAnchorRect(button);
    if (anchorRect?.width > 0 && anchorRect?.height > 0) {
      anchorRects.push(anchorRect);
    }
  };

  const rowCells = [
    ...rowElement.querySelectorAll(":scope > td, :scope > th")
  ];

  if (rowCells.length >= 3) {
    const previewCell = rowCells[rowCells.length - 3];
    const previewButton = findPreviewButtonInCell(previewCell);
    collectAnchorRect(previewButton);
  }

  const candidates = collectDeepElements(
    rowElement,
    "button, lightning-button-icon"
  );

  for (const candidate of candidates) {
    if (
      candidate?.tagName === "LIGHTNING-BUTTON-ICON" &&
      candidate.shadowRoot
    ) {
      const innerButton = candidate.shadowRoot.querySelector("button");
      if (isPreviewTriggerNode(innerButton) || hasPreviewIcon(innerButton)) {
        collectAnchorRect(innerButton);
      }
    }

    if (isPreviewTriggerNode(candidate) || hasPreviewIcon(candidate)) {
      collectAnchorRect(candidate);
    }
  }

  for (let cellIndex = rowCells.length - 1; cellIndex >= 0; cellIndex -= 1) {
    const cellButtons = collectDeepElements(rowCells[cellIndex], "button");
    cellButtons
      .filter(
        (button) => isPreviewTriggerNode(button) || hasPreviewIcon(button)
      )
      .forEach((button) => collectAnchorRect(button));
  }

  if (anchorRects.length === 0) {
    return null;
  }

  return anchorRects.reduce((rightmost, current) =>
    current.left >= rightmost.left ? current : rightmost
  );
};

export const findRowFallbackAnchorRect = (rowElement) => {
  const rowRect = rowElement?.getBoundingClientRect?.();

  if (!rowRect) {
    return null;
  }

  const previewColumnLeft = rowRect.right - 130;

  return {
    top: rowRect.top + 4,
    left: previewColumnLeft,
    right: previewColumnLeft + 32,
    bottom: rowRect.bottom - 4,
    height: rowRect.height - 8,
    width: 32
  };
};

export const createPreviewPointerState = () => ({
  lastPreviewPointer: null,
  lastPreviewClickRect: null,

  clear() {
    this.lastPreviewPointer = null;
    this.lastPreviewClickRect = null;
  }
});

export const capturePreviewPointerFromEvent = (
  event,
  datatableElement,
  pointerState,
  { previewTriggerLabel = DEFAULT_PREVIEW_TRIGGER_LABEL } = {}
) => {
  if (!pointerState || !isPointerEventInsideElement(event, datatableElement)) {
    return;
  }

  pointerState.lastPreviewPointer = {
    x: event.clientX,
    y: event.clientY
  };

  const anchorRect = resolvePreviewAnchorFromEvent(event, previewTriggerLabel);

  if (anchorRect) {
    pointerState.lastPreviewClickRect = anchorRect;
  }
};

export const trackPreviewPointerFromEvent = (
  event,
  datatableElement,
  pointerState
) => {
  if (!pointerState || !isPointerEventInsideElement(event, datatableElement)) {
    return;
  }

  pointerState.lastPreviewPointer = {
    x: event.clientX,
    y: event.clientY
  };
};

export const bindPreviewPointerListeners = (
  getDatatableElement,
  pointerState,
  { previewTriggerLabel = DEFAULT_PREVIEW_TRIGGER_LABEL } = {}
) => {
  const capture = (event) => {
    capturePreviewPointerFromEvent(
      event,
      getDatatableElement(),
      pointerState,
      { previewTriggerLabel }
    );
  };

  const track = (event) => {
    trackPreviewPointerFromEvent(event, getDatatableElement(), pointerState);
  };

  window.addEventListener("click", capture, true);
  window.addEventListener("mousedown", capture, true);
  window.addEventListener("pointerdown", capture, true);
  window.addEventListener("mousemove", track, { passive: true });

  return { capture, track };
};

export const unbindPreviewPointerListeners = (handlers) => {
  if (!handlers) {
    return;
  }

  window.removeEventListener("click", handlers.capture, true);
  window.removeEventListener("mousedown", handlers.capture, true);
  window.removeEventListener("pointerdown", handlers.capture, true);
  window.removeEventListener("mousemove", handlers.track);
};

export const resolveDatatablePreviewPosition = ({
  canvasElement,
  datatableElement,
  datatableRows,
  rowKey,
  row,
  pointerState,
  frozenAnchorRect = null,
  fallbackPosition = DEFAULT_FALLBACK_POSITION,
  preferFixedPosition = true
}) => {
  const rowElement = findDatatableRowElement(
    datatableElement,
    datatableRows,
    rowKey,
    row
  );
  const buildPosition =
    preferFixedPosition || !canvasElement
      ? (anchorRect) => buildFixedPreviewPosition(anchorRect)
      : (anchorRect) => buildCanvasPreviewPosition(canvasElement, anchorRect);

  const anchorCandidates = [
    frozenAnchorRect,
    pointerState?.lastPreviewClickRect,
    findPreviewAnchorFromActiveElement(),
    findPreviewButtonAnchorRectForRow(rowElement),
    findRowFallbackAnchorRect(rowElement)
  ];

  for (const anchorRect of anchorCandidates) {
    const position = buildPosition(anchorRect);
    if (position) {
      return position;
    }
  }

  if (pointerState?.lastPreviewPointer) {
    const pointerPosition = preferFixedPosition || !canvasElement
      ? buildFixedPreviewPositionFromPoint(
          pointerState.lastPreviewPointer.x,
          pointerState.lastPreviewPointer.y
        )
      : buildCanvasPreviewPosition(canvasElement, {
          left: pointerState.lastPreviewPointer.x,
          top: pointerState.lastPreviewPointer.y,
          right: pointerState.lastPreviewPointer.x + 1,
          bottom: pointerState.lastPreviewPointer.y + 1
        });

    if (pointerPosition) {
      return pointerPosition;
    }
  }

  return {
    left: fallbackPosition.left,
    top: fallbackPosition.top,
    useFixedPosition: preferFixedPosition || !canvasElement
  };
};

export const isPreviewTriggerClick = (
  event,
  datatableElement,
  { previewTriggerLabel = DEFAULT_PREVIEW_TRIGGER_LABEL } = {}
) => {
  const { clientX, clientY } = event;

  if (
    Number.isFinite(clientX) &&
    Number.isFinite(clientY) &&
    typeof document.elementsFromPoint === "function"
  ) {
    for (const element of document.elementsFromPoint(clientX, clientY)) {
      if (
        isPreviewTriggerNode(element, previewTriggerLabel) ||
        hasPreviewIcon(element)
      ) {
        return true;
      }

      const button = element.closest?.("button");
      if (
        button &&
        (isPreviewTriggerNode(button, previewTriggerLabel) ||
          hasPreviewIcon(button))
      ) {
        return true;
      }
    }
  }

  const path = getSafeComposedPath(event);

  return path.some((node) => {
    if (
      isPreviewTriggerNode(node, previewTriggerLabel) ||
      hasPreviewIcon(node)
    ) {
      return true;
    }

    return Boolean(
      datatableElement &&
        path.includes(datatableElement) &&
        node?.nodeName === "BUTTON" &&
        node.querySelector?.('svg[data-key="preview"], use[href*="preview"]')
    );
  });
};