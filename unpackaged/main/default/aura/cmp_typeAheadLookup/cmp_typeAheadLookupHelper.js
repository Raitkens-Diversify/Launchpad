({
    fetchPickListVal: function(component, fieldName) {
        var action = component.get("c.getselectOptions");       
        var objName = component.get("v.objectName"); 
        var fieldName = component.get("v.fieldName"); 
        action.setParams({
            "objObject": {sobjectType : objName},
            "fld": fieldName
        });
        action.setCallback(this, function(response) {
            if (response.getState() == "SUCCESS") {
                var opts = [];
                var allValues = response.getReturnValue();
                for (var i = 0; i < allValues.length; i++) {
                    opts.push(allValues[i]);
                }
                component.set("v.picklistOptsList", opts);
            }
        });
        $A.enqueueAction(action);
    },
    
})