({
    init : function (component) {
        
    },
    
    handleNewClientClick : function (component, event, helper) {
        component.set("v.openFlow", true);
        var flow = component.find("flowData");
        //YOUR FLOW API NAME SHOULD REPLACE Flow_Name BELOW 
        flow.startFlow("Screen_Flow_New_Client");
    }
})