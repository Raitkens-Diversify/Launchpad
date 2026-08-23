({
	doInit : function(component, event, helper) {
		var record = component.get('v.recordId');
        var action = component.get('c.getCaseValues');
        action.setParams({recordId : record});
        action.setCallback(this, function(response){
        var state = response.getState();
            console.log(state);
            if (state === "SUCCESS") {
                var caseList = response.getReturnValue();
                component.set("v.caseObj", caseList);
            }else if (state === "ERROR") {
                var errors = response.getError();
                if (errors) {
                    if (errors[0] && errors[0].message) {
                    }
                }
            }
        });
        
        $A.enqueueAction(action);
	}
})