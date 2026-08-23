({
        doInit : function(component, event, helper) {
		var record = component.get('v.householdId');
        var action = component.get('c.getHouseholdMembers');
        action.setParams({recordId : record});
        action.setCallback(this, function(response){
        var state = response.getState();
            if (state === "SUCCESS") {
                var householdMembersList = response.getReturnValue();
                var items = [];
                for (let i = 0; i < householdMembersList.length; i++) {
                    var item = {
                        "label": householdMembersList[i].Contact.Name,
                        "value": householdMembersList[i].Contact.AccountId
                    };
                    items.push(item);
                }
                component.set("v.householdMembers", items);
            }else if (state === "ERROR") {
                var errors = response.getError();
                if (errors) {
                    if (errors[0] && errors[0].message) {
                    }
                }
            }
        });
        
        $A.enqueueAction(action);
	},
    handleChange: function (component, event) {
        var selectedOptionValue = event.getParam("value");
        component.set("v.selectedPrimaryOwnerId", selectedOptionValue);
        var record = component.get('v.householdId');
        var primaryId = component.get("v.selectedPrimaryOwnerId");
        var action = component.get('c.getHouseholdMembersMinusPrimary');
        action.setParams({recordId : record, primaryOwnerId : primaryId});
        action.setCallback(this, function(response){
        var state = response.getState();
            if (state === "SUCCESS") {
                var householdMembersListMinusPrimary = response.getReturnValue();
                var items = [];
                for (let i = 0; i < householdMembersListMinusPrimary.length; i++) {
                    var item = {
                        "label": householdMembersListMinusPrimary[i].Contact.Name,
                        "value": householdMembersListMinusPrimary[i].Contact.AccountId
                    };
                    items.push(item);
                }
                component.set("v.householdMembersMinusPrimary", items);
                component.set("v.disabled", false);
            }else if (state === "ERROR") {
                var errors = response.getError();
                if (errors) {
                    if (errors[0] && errors[0].message) {
                    }
                }
            }
        });
        
        $A.enqueueAction(action);
    },
    handleChangeMinusPrimary: function (component, event) {
        var selectedOptionValue = event.getParam("value");
        component.set("v.selectedJointOwnerId", selectedOptionValue);
    }
});