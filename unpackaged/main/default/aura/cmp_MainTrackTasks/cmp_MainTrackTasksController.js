({
    doInit: function(component, event, helper) {
        console.log('Hello from doInIt :' + component.get("v.recordId"));
        helper.populateTable(component, event);
         const empApi = component.find("empApi");

        const channel = "/event/Refresh_Detail__e";

        const replayId = -1; // get new events
        empApi.subscribe(channel, replayId, function(message) {
        	helper.populateTable(component, event);
        })
        .then(function(subscription) {
            console.log("Subscribed: ", subscription);
        });
    },
    
    navigateToTask : function(component, event, helper) {
        helper.navigateToTaskHelper(component, event);
	},
    
    handleMessage : function(component, message, helper) {
        if (!message || !message.getParam('recordId')) {
            return;
        }

        const recordId = message.getParam('recordId');

        const currentRecordId = component.get("v.recordId");

        if (!currentRecordId || currentRecordId === recordId) {
            helper.refresh(component);
        }
    }

});