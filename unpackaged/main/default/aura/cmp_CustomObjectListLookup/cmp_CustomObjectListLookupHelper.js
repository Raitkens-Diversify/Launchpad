({
	doInit : function(component, event, helper) {
        console.log('CustomObjectListLookup helper.doInit');
        this.getSelectedRecordDetails(component, event, helper);
        this.getParentObjectName(component, event, helper);
        this.getIconName(component, event, helper);
	},
    
    getSelectedRecordDetails : function(component, event, helper){
        console.log('CustomObjectListLookup helper.getSelectedRecordDetails');
        var selRecordId = component.get("v.selectRecordId");
        if(selRecordId == null || selRecordId == '' || selRecordId == undefined){
            return;
        }
        var action = component.get("c.getSelectedRecordDetails");
        action.setParams({"recordId" : selRecordId});
        action.setCallback(this, function(response) {
            var state = response.getState();
            if (state === "SUCCESS") {
                var result = response.getReturnValue();
                component.set("v.selectRecordName", result.Name);
                this.getIconName(component, event, helper);
                //component.set("v.iconName",'custom:custom8');
            }
        });
        $A.enqueueAction(action);
    },
    
    getParentObjectName : function(component, event, helper){
        console.log('CustomObjectListLookup helper.getParentObjectName');
        var childObjectName=component.get("v.childObjectName");
        var parentFieldName=component.get("v.parentFieldName");
        var getParentObjectName=component.get("c.getParentObjectName");
        getParentObjectName.setParams({"childObjectName":childObjectName,
                                       "parentFieldName":parentFieldName
            
        });
        getParentObjectName.setCallback(this,function(response){
            var state=response.getState();
            if(state=='SUCCESS'){
                var result=response.getReturnValue();
                component.set("v.objectName",result);
                this.getIconName(component, event, helper);
                /*if(result=='Fund_Model__c'){
                    component.set("v.iconName",'custom:custom8');
                }
                if(result == 'Finserv__FinancialAccount__c'){
                    component.set("v.iconName",'custom:custom16');
                }*/
            }else if(state=='ERROR'){
                console.log('Error ' + response.getError[0]);
            }
        });
        $A.enqueueAction(getParentObjectName);
    },
    
    getIconName : function(component, event, helper){
        console.log('CustomObjectListLookup helper.getIconName');
        var objectName=component.get("v.objectName");
        var getIconName=component.get("c.getIconName");
        getIconName.setParams({"sObjectName":objectName});
        getIconName.setCallback(this,function(response){
            var state=response.getState();
            if(state=='SUCCESS'){
                var result=response.getReturnValue();
                component.set("v.iconName",result);
            }else if(state=='ERROR'){
                console.log('Error ' + response.getError[0]);
            }
        });
        $A.enqueueAction(getIconName);
    }
})