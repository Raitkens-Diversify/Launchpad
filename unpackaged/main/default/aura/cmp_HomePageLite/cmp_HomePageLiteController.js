({
	handleNewClientClick : function (component, event, helper) {
        component.set("v.openFlow", true);
        component.set("v.showScreen2", false);
        var flow = component.find("flowData");
        //YOUR FLOW API NAME SHOULD REPLACE Flow_Name BELOW 
        flow.startFlow("CRM_Lite_New_Client");
    },
    
    handleNewOrderClick : function (component, event, helper) {
        component.set("v.showScreen2", true);
        component.set("v.showScreen1", false);
    },
})