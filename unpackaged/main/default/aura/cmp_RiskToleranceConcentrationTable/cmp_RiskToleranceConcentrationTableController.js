({
    init: function (component, event, helper) {debugger;
                                               var netWorthPercentages = component.get('v.netWorthPercentages');
                                               var netWorthAmount = component.get('v.netWorthAmount');
                                               var netWorthTotalPercentage;
                                               if(netWorthAmount != 0){
                                               netWorthPercentages.push(helper.correctFormat((component.get('v.securitizedPrivateRealEstateAmount') / netWorthAmount) *100));
                                               netWorthPercentages.push(helper.correctFormat((component.get('v.privateEquityAmount') / netWorthAmount) *100));
                                               netWorthPercentages.push(helper.correctFormat((component.get('v.privateCreditAmount') / netWorthAmount) *100));
                                               netWorthPercentages.push(helper.correctFormat((component.get('v.intervalFundsAmount') / netWorthAmount) *100));
                                               netWorthPercentages.push(helper.correctFormat((component.get('v.energyProgramsAmount') / netWorthAmount) *100));
                                               netWorthPercentages.push(helper.correctFormat((component.get('v.structuredNotesAmount') / netWorthAmount) *100));
                                               netWorthTotalPercentage = helper.correctFormat((component.get('v.securitizedPrivateRealEstateAmount')+component.get('v.privateEquityAmount')+
                                                                                   component.get('v.privateCreditAmount')+  component.get('v.intervalFundsAmount') +component.get('v.energyProgramsAmount')) /netWorthAmount *100);                                         
                                               
                                               component.set('v.netWorthPercentages',netWorthPercentages);
                                               component.set('v.netWorthTotalPercentage',netWorthTotalPercentage);
                                               }
                                              },
    
})