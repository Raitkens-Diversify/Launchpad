({
    init : function (component, event, helper) {
        var pageReference = component.get("v.pageReference");
        var state = pageReference ? pageReference.state : null;
        var recordTypeId = state ? (state.recordTypeId || state.recordtypeid) : null;

        helper.routeForRecordType(component, recordTypeId);
    }
})