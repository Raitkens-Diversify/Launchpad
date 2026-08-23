({
	doInit : function(component, event, helper) {
		var accountId = component.get('v.recordId');
        var action = component.get('c.getEmailTemplateText');
        action.setParams({emailTemplateName : emailTemplate, caseId : cId, userId : uId});
        action.setCallback(this, function(response){
        var state = response.getState();
            if (state === "SUCCESS") {
                //var emailTemplateText = response.getReturnValue();
                //console.log('emailTemplateText: ' + emailTemplateText);
                //component.set("v.EmailTemplateText", emailTemplateText);
                //component.set("v.triggerHandler", code);
            }else if (state === "ERROR") {
                var errors = response.getError();
               
                if (errors) {
                    if (errors[0] && errors[0].message) {
                         //component.set("v.errorMessage", errors[0].message);
                    }
                }
            }
        });
        
        $A.enqueueAction(action);
	},
})