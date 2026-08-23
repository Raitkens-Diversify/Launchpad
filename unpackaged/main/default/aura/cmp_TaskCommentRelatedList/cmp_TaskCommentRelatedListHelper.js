({
    getData : function(cmp) {
        var action = cmp.get('c.getComments');
        action.setParams({ recordId : cmp.get("v.recordId")});
        action.setCallback(this, $A.getCallback(function (response) {
            var state = response.getState();
            if (state === "SUCCESS") {
                var taskComments = response.getReturnValue();
                var firstFiveComments = taskComments ? taskComments.slice(0, 5) : [];
                cmp.set('v.mydataAll', taskComments);
    			cmp.set('v.mydata5', firstFiveComments);
                cmp.set('v.mydata', firstFiveComments);
                cmp.set('v.dataCount', taskComments? taskComments.length: 0);
            } else if (state === "ERROR") {
                var errors = response.getError();
                console.error(errors);
            }
        }));
        $A.enqueueAction(action);
    }
})