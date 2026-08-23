({
	doInit : function(component, event, helper) {
		var emailTemplate = component.get('v.EmailTemplate');
        var cId = component.get('v.CaseId');
        console.log('caseId: ' + cId);
        var uId = component.get('v.UserId');
        var action = component.get('c.getEmailTemplateText');
        action.setParams({emailTemplateName : emailTemplate, caseId : cId, userId : uId});
        action.setCallback(this, function(response){
        var state = response.getState();
            if (state === "SUCCESS") {
                var emailTemplateText = response.getReturnValue();
                console.log('emailTemplateText: ' + emailTemplateText);
                component.set("v.EmailTemplateText", emailTemplateText);
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
    
    copyEmailTemplateText : function(component, event, helper) {
        var textForCopy = component.get("v.EmailTemplateText");
        console.log('textForCopy: ' + textForCopy);
        helper.copyTextHelper(component,event,textForCopy);
    },
})