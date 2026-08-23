({
    doinit: function(component, event, helper) {
        helper.totalLiquidAssets(component, event, helper);  
        helper.totalIlliquidAssets(component, event, helper);  
        helper.totalLongTermLiabilities(component, event, helper);
        helper.totalAlternativeInvestments(component, event, helper);
    },
    
    totalLiquidAssets : function(component, event, helper) {
        helper.totalLiquidAssets(component, event, helper);
    },
    
    totalAlternativeInvestments : function(component, event, helper) {
        helper.totalAlternativeInvestments(component, event, helper);
    },
    
    totalIlliquidAssets : function(component, event, helper) {
        helper.totalIlliquidAssets(component, event, helper);
    },
    
    totalLongTermLiabilities : function(component, event, helper) {
        helper.totalLongTermLiabilities(component, event, helper);
    },
    
    totalLiabilities : function(component, event, helper) {
		helper.totalLiabilities(component, event, helper);        
    }
    
})