public with sharing class FieldSetController {

    @AuraEnabled(cacheable=true)
    public static List<FieldMetadata> getFieldSetFields(String objectName, String fieldSetName) {

        List<FieldMetadata> fieldList = new List<FieldMetadata>();

        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectName);
        if (objectType == null) {
            throw new AuraHandledException('Object not found: ' + objectName);
        }

        Schema.DescribeSObjectResult objDescribe = objectType.getDescribe();
        Map<String, Schema.FieldSet> fieldSetMap = objDescribe.fieldSets.getMap();

        if (!fieldSetMap.containsKey(fieldSetName)) {
            throw new AuraHandledException('Field Set not found: ' + fieldSetName);
        }

        Schema.FieldSet fieldSet = fieldSetMap.get(fieldSetName);

        for (Schema.FieldSetMember field : fieldSet.getFields()) {
            fieldList.add(buildFieldMetadata(field));
        }

        return fieldList;
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, List<FieldMetadata>> getMultipleFieldSets(String objectName, List<String> fieldSetNames) {

        Map<String, List<FieldMetadata>> result = new Map<String, List<FieldMetadata>>();

        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectName);
        if (objectType == null) {
            throw new AuraHandledException('Object not found: ' + objectName);
        }

        Schema.DescribeSObjectResult objDescribe = objectType.getDescribe();
        Map<String, Schema.FieldSet> fieldSetMap = objDescribe.fieldSets.getMap();

        for (String fsName : fieldSetNames) {
            List<FieldMetadata> fieldList = new List<FieldMetadata>();

            if (fieldSetMap.containsKey(fsName)) {
                for (Schema.FieldSetMember field : fieldSetMap.get(fsName).getFields()) {
                    fieldList.add(buildFieldMetadata(field));
                }
            }

            result.put(fsName, fieldList);
        }

        return result;
    }

    // Common builder method
    private static FieldMetadata buildFieldMetadata(Schema.FieldSetMember field) {

        FieldMetadata meta = new FieldMetadata();

        meta.label = field.getLabel();
        meta.fieldPath = field.getFieldPath();
        meta.type = String.valueOf(field.getType());
        meta.required = field.getRequired() || field.getDbRequired();
        meta.disabled = (field.getFieldPath() == 'Id' || field.getFieldPath() == 'CreatedDate');

        Schema.DescribeFieldResult describe = field.getSObjectField().getDescribe();

        meta.inputType = determineInputType(describe);
        meta.maxLength = describe.getLength();
        meta.scale = describe.getScale();
        meta.precision = describe.getPrecision();

        if (describe.getType() == Schema.DisplayType.REFERENCE) {
            List<Schema.SObjectType> references = describe.getReferenceTo();
            if (!references.isEmpty()) {
                meta.referenceTo = references[0].getDescribe().getName();
            }
        }

        if (describe.getType() == Schema.DisplayType.PICKLIST || 
            describe.getType() == Schema.DisplayType.MULTIPICKLIST) {

            meta.picklistOptions = new List<PicklistOption>();

            for (Schema.PicklistEntry entry : describe.getPicklistValues()) {
                if (entry.isActive()) {
                    meta.picklistOptions.add(
                        new PicklistOption(entry.getLabel(), entry.getValue())
                    );
                }
            }
        }

        return meta;
    }

    private static String determineInputType(Schema.DescribeFieldResult fieldDescribe) {
        switch on fieldDescribe.getType() {
            when STRING, TEXTAREA, ID { return 'text'; }
            when EMAIL { return 'email'; }
            when PHONE { return 'tel'; }
            when URL { return 'url'; }
            when DATE { return 'date'; }
            when DATETIME { return 'datetime'; }
            when TIME { return 'time'; }
            when INTEGER, LONG, DOUBLE, CURRENCY, PERCENT { return 'number'; }
            when BOOLEAN { return 'checkbox'; }
            when PICKLIST, MULTIPICKLIST { return 'combobox'; }
            when else { return 'text'; }
        }
    }

    // 🔹 Wrapper classes
    public class FieldMetadata {
        @AuraEnabled public String label;
        @AuraEnabled public String fieldPath;
        @AuraEnabled public String type;
        @AuraEnabled public String inputType;
        @AuraEnabled public Boolean required;
        @AuraEnabled public Boolean disabled;
        @AuraEnabled public Integer maxLength;
        @AuraEnabled public Integer scale;
        @AuraEnabled public Integer precision;
        @AuraEnabled public String referenceTo;
        @AuraEnabled public List<PicklistOption> picklistOptions;
    }

    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;

        public PicklistOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }
}