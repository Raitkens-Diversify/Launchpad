({
    init: function (component) {
        var flow = component.find("flowData");
        flow.startFlow("Log_a_Check");

        // Lift docked composer above the utility bar and size the scroll body to fit
        window.setTimeout($A.getCallback(function () {
            var containerCmp = component.find("flowContainer");
            if (!containerCmp) {
                return;
            }
            var el = containerCmp.getElement();
            if (!el) {
                return;
            }

            var utilityBar = document.querySelector(
                ".utilitybar, .slds-utility-bar, footer.oneUtilityBar, .oneUtilityBar"
            );
            var utilityHeight = 40;
            if (utilityBar) {
                utilityHeight = Math.ceil(utilityBar.getBoundingClientRect().height) || 40;
            }

            // Keep the composer panel itself above the utility bar
            var panel = el.closest(
                ".dockedComposer, .dockedComposerPanel, .oneDockingPanel, .slds-docked-composer"
            );
            if (panel) {
                panel.style.bottom = utilityHeight + 8 + "px";
            }

            var top = el.getBoundingClientRect().top;
            var available = Math.floor(window.innerHeight - top - utilityHeight - 16);
            available = Math.max(280, Math.min(available, 720));
            el.style.height = available + "px";
            el.style.maxHeight = available + "px";
        }), 50);
    },

    handleStatusChange: function (component, event) {
        var status = event.getParam("status");
        if (status === "FINISHED" || status === "FINISHED_SCREEN") {
            $A.get("e.force:closeQuickAction").fire();
        }
    }
})