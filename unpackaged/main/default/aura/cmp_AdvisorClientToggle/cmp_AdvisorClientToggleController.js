({
    
    doInit : function(component, event, helper) {
        var action = component.get("c.getViewState");
        var idForAccount = component.get("v.recordId");
        action.setParams({recordId : idForAccount});
        action.setCallback(this, function(actionResult) {
            var state = actionResult.getState();
            console.log('state: ' + state);
            if (state === "SUCCESS") {
                component.set("v.viewState", actionResult.getReturnValue());
                $A.get('e.force:refreshView').fire();
            } 
            if (state === "ERROR") {
                var errors = actionResult.getError();
                if (errors && errors[0] && errors[0].message) {
                    // This is the specific error message from Apex
                    console.log("Error message: " + errors[0].message);
                } else {
                    // For general troubleshooting of the entire error object
                    console.log("Full error details: ", JSON.stringify(errors));
                }
            }
        });        
        $A.enqueueAction(action); 
    },
	handleClick: function (component, event, helper) {
        var selectedButtonLabel = event.getSource().get("v.label");
        var idForAccount = component.get("v.recordId");
        var action = component.get("c.toggleView");
        action.setParams({ recordId : idForAccount ,
                          viewState : selectedButtonLabel});
        action.setCallback(this, function(actionResult) {
            var state = actionResult.getState();
            console.log('Hstate: ' + state);
            if (state === "SUCCESS") {
                component.set("v.viewState", selectedButtonLabel);
                $A.get('e.force:refreshView').fire();
            } 
            if (state === "ERROR") {
                var errors = actionResult.getError();
                if (errors && errors[0] && errors[0].message) {
                    // This is the specific error message from Apex
                    console.log("Error message: " + errors[0].message);
                } else {
                    // For general troubleshooting of the entire error object
                    console.log("Full error details: ", JSON.stringify(errors));
                }
            }
        });        
        $A.enqueueAction(action); 
    }
})