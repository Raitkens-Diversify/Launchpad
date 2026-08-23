({
	handleSendDocuSignEnvs : function(component, event, helper) {
        component.set('v.loading', true);
		var action = component.get("c.sendOppEnvelopes");
        action.setParams({oppId: component.get('v.recordId')});
        action.setCallback(this, function(actionResult) {
            component.set('v.loading', false);
            var state = actionResult.getState();
            if (state === "SUCCESS") {
                this.showToastEvent("Success", "success", "Opportunity DocuSign Envelopes sent successfully!", "dismissible");
            } else{
                this.showToastEvent('Error', 'error', 'Error occured while sending Opportunity DocuSign Envelopes:' + actionResult.getError()[0].message, 'dismissible');
            }
        });
        $A.enqueueAction(action);
	},
    
    showToastEvent: function(title, type, message, mode){
        var toastEvent = $A.get("e.force:showToast");
        toastEvent.setParams({
            "title": title,
            "type": type,
            "message": message,
            "mode" : mode
        });
        toastEvent.fire();
    }
})