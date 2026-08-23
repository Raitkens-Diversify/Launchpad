({
    // Decides where to send the user once a record type has been selected.
    // Users with the Create_DRP_Standard permission who pick the Diversify
    // Related Person record type are routed to the native create screen; every
    // other case keeps the existing Wizard flow behavior.
    routeForRecordType : function (component, recordTypeId) {
        var helper = this;
        var action = component.get("c.shouldRouteToDrpStandard");
        action.setParams({ recordTypeId: recordTypeId });
        action.setCallback(this, function (response) {
            var state = response.getState();
            if (state === "SUCCESS" && response.getReturnValue() === true) {
                helper.navigateToNativeCreate(recordTypeId);
            } else {
                // SUCCESS-without-match, ERROR, or INCOMPLETE all fall back to
                // the Wizard so the create experience never breaks.
                helper.startCreateProspectFlow(component, recordTypeId);
            }
        });
        $A.enqueueAction(action);
    },

    // Opens the standard Account create page. nooverride=1 bypasses this
    // Lightning action override so the assigned flexipage is rendered.
    navigateToNativeCreate : function (recordTypeId) {
        var url = "/lightning/o/Account/new?nooverride=1&useRecordTypeCheck=0";
        if (recordTypeId) {
            url += "&recordTypeId=" + encodeURIComponent(recordTypeId);
        }
        var navEvt = $A.get("e.force:navigateToURL");
        navEvt.setParams({ "url": url });
        navEvt.fire();
    },

    startCreateProspectFlow : function (component, recordTypeId) {
        var flow = component.find("flowData");
        flow.startFlow("Create_Prospect", [
            { name: "recordTypeId", type: "String", value: recordTypeId }
        ]);
    }
})