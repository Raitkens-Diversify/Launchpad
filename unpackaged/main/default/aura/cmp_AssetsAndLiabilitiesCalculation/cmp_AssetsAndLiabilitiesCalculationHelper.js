({ 
    totalLiquidAssets : function(component, event, helper) {
        var liquidAssetVars = ['CashCheckingBalance', 'CashSavingsBalance', 'RetirementPlansBalance',
                               'ExculdingRetirementPlansBalance', 'AnnuitiesBalance', 'OtherLiquidAssetsBalance'];
        var liquidAssetTotal = liquidAssetVars.reduce(
            (currentValue, assetVar) => parseFloat(component.get('v.'+assetVar) || 0)+ currentValue,
            0
        );
        component.set('v.TotalLiquidAssets', liquidAssetTotal);
        this.totalAssets(component, event, helper);
    },
    
    totalAlternativeInvestments : function(component, event, helper) {
        var totalAlternativeInvestmentVars = ['MarketValueOfSecurInv', 'PrivateCreditOwned', 'PrivateEquityOwned', 'EnergyPrograms',
                                          'MarketValueOfIntervalFunds', 'StructuredNotes'];
        var totalAlternativeInvestments = totalAlternativeInvestmentVars.reduce(
            (currentValue, assetVar) => parseFloat(component.get('v.'+assetVar) || 0)+ currentValue,
            0
        );
        component.set('v.TotalAlternativeInvestments', totalAlternativeInvestments);
        //this.totalAssets(component, event, helper);
        this.totalIlliquidAssets(component, event, helper);
    },
    
    totalIlliquidAssets : function(component, event, helper) {
        var IlliquidAssetVars = ['MarketValueOfPR', 'MarketValueOfNonSecurInv', 'MarketValueOfSecurInv',
                                 'MarketValueOfNonREAltInv', 'MarketValueOfIntervalFunds', 'MarketValueOfBusinessInterest',
                                 'ExchangeProceedsatQIBalance','LumpSumPensions','OtherIlliquidAssetsBalance', 
                                 'PrivateCreditOwned', 'PrivateEquityOwned', 'EnergyPrograms','StructuredNotes'];
        var IlliquidAssetTotal = IlliquidAssetVars.reduce(
            (currentValue, assetVar) => parseFloat(component.get('v.'+assetVar) || 0)+ currentValue,
            0
        );
        component.set('v.TotalIlliquidAssets', IlliquidAssetTotal);
        this.totalAssets(component, event, helper);
    },
    
    totalAssets : function(component, event, helper) {
        var totalLiquidAsset = parseFloat(component.get('v.TotalLiquidAssets') || 0);
        var totalIlliquidAsset = parseFloat(component.get('v.TotalIlliquidAssets') || 0);
        var totalAssets = totalLiquidAsset + totalIlliquidAsset;
        component.set('v.TotalAssets', totalAssets);
        this.totalNetWorth(component, event, helper);
    },
    
    totalLongTermLiabilities : function(component, event, helper) {
        var longTermLiabilitiesVars = ['MortgagePayableOnPR', 'MortgagePayableOnNonSecurInv', 'MortgagePayableOnSecurInv',
                                       'DebtSecuredByPersonalProp', 'DebtFromBusinessInterests', 'OtherLongTermLiabilities'];
        var longTermLiabilitiesTotal = longTermLiabilitiesVars.reduce(
            (currentValue, liabilityVar) => parseFloat(component.get('v.'+liabilityVar) || 0)+ currentValue,
            0
        );
        component.set('v.TotalLongTermLiabilities', longTermLiabilitiesTotal);
        this.totalLiabilities(component, event, helper);
    },
    
    totalLiabilities : function(component, event, helper) {
        var totalCurrentLiabilities = parseFloat(component.get('v.TotalCurrentLiabilities') || 0);
        var totalLongTermLiabilities = parseFloat(component.get('v.TotalLongTermLiabilities') || 0);
        var sumLiabilities = totalCurrentLiabilities + totalLongTermLiabilities;
        component.set('v.TotalLiabilities', sumLiabilities);
        this.totalNetWorth(component, event, helper);
    },
    
    totalNetWorth : function(component, event, helper) {
        var totalAssets = parseFloat(component.get('v.TotalAssets') || 0);
        var totalLiabilities = parseFloat(component.get('v.TotalLiabilities') || 0);
        var netWorth = totalAssets - totalLiabilities;
        component.set('v.TotalNetWorth', netWorth);
        this.totalNetWorthExcludingPR(component, event, helper);
    }, 
    
    totalNetWorthExcludingPR : function(component, event, helper) {
        var netWorth = parseFloat(component.get('v.TotalNetWorth') || 0);
        var marketValueOfPR = parseFloat(component.get('v.MarketValueOfPR') || 0);
        var mortgagePayableOnPR = parseFloat(component.get('v.MortgagePayableOnPR') || 0);
        var netWorthExcludingPR = netWorth - (marketValueOfPR - mortgagePayableOnPR);
        component.set('v.TotalNetWorthExcludingPR', netWorthExcludingPR);
    },
})