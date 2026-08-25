/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-22
 *
 * AuraEnabled facade for the Book of Business record tab.
 * Returns mock data in v1; recordId is accepted for future SOQL wiring.
 */
public with sharing class BookOfBusinessController {
  private static final BookOfBusinessRepository REPOSITORY = new BookOfBusinessRepository();

  @AuraEnabled(cacheable=true)
  public static BookOfBusinessModels.BookOfBusinessResult getBookOfBusinessData(
    Id recordId,
    List<String> additionalFieldApis
  ) {
    return REPOSITORY.selectBookOfBusinessData(recordId, additionalFieldApis);
  }
}