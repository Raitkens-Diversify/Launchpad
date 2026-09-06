/**
 * Maintains the Resource Center category tree (Path__c / Depth__c, cycle and
 * max-depth guards, descendant rewrites). See ResourceCategoryTreeHandler.
 */
trigger Resource_Category_Trigger on Resource_Category__c (before insert, before update, after update, after delete) {
    if (Trigger.isBefore) {
        ResourceCategoryTreeHandler.beforeSave(Trigger.new);
    } else if (Trigger.isUpdate) {
        ResourceCategoryTreeHandler.afterUpdate(Trigger.new, Trigger.oldMap);
    } else if (Trigger.isDelete) {
        ResourceCategoryTreeHandler.afterDelete(Trigger.old);
    }
}