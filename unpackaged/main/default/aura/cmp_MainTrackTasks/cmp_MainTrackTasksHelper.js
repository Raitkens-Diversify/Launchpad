({
	populateTable : function(component, event) {
        
        var action = component.get("c.getTasks");
        action.setParams({
            recordId: component.get("v.recordId")
        });
        action.setCallback(this, function(response) {
            var state = response.getState();
            if (state === "SUCCESS") {
                console.log('response.getReturnValue() :' + response.getReturnValue());
                component.set("v.tasks", response.getReturnValue());
            } else {
                console.error("Error fetching tasks:", response.getError());
            }
        });
        $A.enqueueAction(action);
	},
    
    navigateToTaskHelper : function(component, event) {
        var taskId = event.currentTarget.getAttribute("data-taskid");
        var taskSub = event.currentTarget.getAttribute("data-tasksub");
        var workspaceAPI = component.find("workspace");
    
        workspaceAPI.getEnclosingTabId().then(function(parentTabId) {
            workspaceAPI.openSubtab({
                parentTabId: parentTabId,
                recordId: taskId,
                focus: true,
                label: taskSub
            });
        }).catch(function(error) {
            console.error("Error opening subtab: ", error);
        });

    },
    refresh : function(component) {
        const action = component.get("c.doInit");
        if (action) {
            $A.enqueueAction(action);
        }
        // $A.get('e.force:refreshView').fire();
    }
})