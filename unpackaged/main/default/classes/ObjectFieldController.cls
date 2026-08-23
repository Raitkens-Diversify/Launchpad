/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-14
 *
 * Returns accessible, displayable object fields for column and filter pickers.
 */
public with sharing class ObjectFieldController {
  @AuraEnabled(cacheable=true)
  public static List<FieldOption> getAccessibleFields(String objectApiName) {
    if (String.isBlank(objectApiName)) {
      throw new AuraHandledException('Object API name is required.');
    }

    Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);

    if (objectType == null) {
      throw new AuraHandledException('Object not found: ' + objectApiName);
    }

    Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();
    List<FieldOption> options = new List<FieldOption>();

    for (String fieldName : fieldMap.keySet()) {
      Schema.DescribeFieldResult describe = fieldMap.get(fieldName).getDescribe();

      if (!describe.isAccessible() || !isDisplayableField(describe.getType())) {
        continue;
      }

      options.add(
        new FieldOption(
          describe.getName(),
          describe.getLabel(),
          String.valueOf(describe.getType()),
          describe.isSortable()
        )
      );
    }

    options.sort(new FieldOptionComparator());
    return options;
  }

  private static Boolean isDisplayableField(Schema.DisplayType fieldType) {
    Set<Schema.DisplayType> excludedTypes = new Set<Schema.DisplayType>{
      Schema.DisplayType.ADDRESS,
      Schema.DisplayType.BASE64,
      Schema.DisplayType.ENCRYPTEDSTRING,
      Schema.DisplayType.LOCATION
    };

    return !excludedTypes.contains(fieldType);
  }

  public class FieldOption {
    @AuraEnabled
    public String apiName { get; set; }
    @AuraEnabled
    public String label { get; set; }
    @AuraEnabled
    public String type { get; set; }
    @AuraEnabled
    public Boolean sortable { get; set; }

    public FieldOption(
      String apiName,
      String label,
      String type,
      Boolean sortable
    ) {
      this.apiName = apiName;
      this.label = label;
      this.type = type;
      this.sortable = sortable;
    }

    public FieldOption() {
      this.sortable = false;
    }
  }

  private class FieldOptionComparator implements Comparator<FieldOption> {
    public Integer compare(FieldOption left, FieldOption right) {
      String leftLabel = left?.label == null ? '' : left.label;
      String rightLabel = right?.label == null ? '' : right.label;
      return leftLabel.toLowerCase().compareTo(rightLabel.toLowerCase());
    }
  }
}