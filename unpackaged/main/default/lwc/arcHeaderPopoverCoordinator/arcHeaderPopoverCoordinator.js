/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-18
 *
 * Ensures only one Experience Cloud header popover (notification bell, settings menu)
 * is open at a time.
 */
export const HEADER_POPOVER_NOTIFICATION_BELL = "arc-notification-bell";
export const HEADER_POPOVER_MENU_SETTING = "arc-menu-setting";

const listeners = new Set();
let activePopoverId = null;

const notifyListeners = (popoverId) => {
  listeners.forEach((listener) => {
    listener(popoverId);
  });
};

export const subscribeToHeaderPopover = (listener) => {
  listeners.add(listener);

  return () => {
    listeners.delete(listener);
  };
};

export const requestOpenHeaderPopover = (popoverId) => {
  if (!popoverId || activePopoverId === popoverId) {
    return;
  }

  activePopoverId = popoverId;
  notifyListeners(popoverId);
};

export const requestCloseHeaderPopover = (popoverId) => {
  if (!popoverId || activePopoverId !== popoverId) {
    return;
  }

  activePopoverId = null;
  notifyListeners(null);
};

export const getActiveHeaderPopoverId = () => activePopoverId;

export const isClickInsideHost = (event, host) => {
  if (!host) {
    return false;
  }

  const path = typeof event.composedPath === "function" ? event.composedPath() : [];

  return path.includes(host);
};