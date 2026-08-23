({
    init : function(component, event, helper) {
        var action = component.get("c.getCVAdvertisingTypeOpts");
        action.setCallback(this, function(actionResult) {
            var state = actionResult.getState();
            if (state === "SUCCESS") {
                let result = actionResult.getReturnValue();
                if(result != null && result.includes(component.get('v.advertisingType'))){
                    component.set('v.disabled', false);
                }
                else{
                    component.set('v.disabled', true);
                    component.set('v.invalidAdType', true);
                }
            } 
            else if (state === "ERROR") {
                this.showToastEvent('Error', 'Error', 'Error:' + response.getError()[0].message, 'dismissible');
            }
        }); 
        $A.enqueueAction(action);
    },
    
    updateCVs : function(component, event, cvIds) {
        component.set('v.loading', true);
        var updateAction = component.get("c.updateCVs");
        updateAction.setParams({cvIds : cvIds,
                                adType : component.get('v.advertisingType'),
                                interviewId : component.get('v.flowInterviewId')});
        updateAction.setCallback(this, function(response) {
            var state = response.getState();
            if (state == "SUCCESS") { 
                console.log('Record updated successfully');
            }
            else if (state === "ERROR") {
                this.showToastEvent('Error', 'Error', 'Error while updating record :' + response.getError()[0].message, 'dismissible');
            }
            component.set('v.loading', false);
        }); 
        $A.enqueueAction(updateAction);
    },
    
    updateCVsNonAdReview : function(component, event, cvIds) {
        component.set('v.loading', true);
        var updateAction = component.get("c.updateCVsNonAdReview");
        updateAction.setParams({cvIds : cvIds,
                                interviewId : component.get('v.flowInterviewId')});
        updateAction.setCallback(this, function(response) {
            var state = response.getState();
            if (state == "SUCCESS") { 
                console.log('Record updated successfully');
            }
            else if (state === "ERROR") {
                this.showToastEvent('Error', 'Error', 'Error while updating record :' + response.getError()[0].message, 'dismissible');
            }
            component.set('v.loading', false);
        }); 
        $A.enqueueAction(updateAction);
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
    },
})