({
    doInit: function(component, event, helper) {
        const empApi = component.find('empApi');
        const channel = '/event/Refresh_Detail__e';
        const replayId = -1;

        const callback = function (message) {
            console.log('Event received: ', message);
            helper.populateTable(component, event);
        };

        empApi.subscribe(channel, replayId, $A.getCallback(callback))
            .then($A.getCallback(function (subscription) {
                console.log('Subscribed to channel: ', subscription.channel);
        }));

        console.log('Hello from doInIt :' + component.get("v.recordId"));
        helper.populateTable(component, event);
    },
    
    navigateToTask : function(component, event, helper) {
        helper.navigateToTaskHelper(component, event);
	},
    
    unrender: function(component, helper) {
        this.superUnrender();
        helper.unsubscribe(component);
    },
    
    handleMessage: function(component, message, helper) {
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