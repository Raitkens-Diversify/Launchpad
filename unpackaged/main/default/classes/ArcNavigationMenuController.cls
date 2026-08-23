/**
 * Fetches Experience Cloud navigation menu items for LWR sites.
 * Menu name may be NavigationLinkSet MasterLabel or DeveloperName.
 */
public without sharing class ArcNavigationMenuController {
  public class MenuItemDTO {
    @AuraEnabled
    public String id;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String target;
    @AuraEnabled
    public String type;
    @AuraEnabled
    public String parentId;
    @AuraEnabled
    public Integer position;
    @AuraEnabled
    public List<MenuItemDTO> subMenu;
  }

  /**
   * @param menuName MasterLabel or DeveloperName of the NavigationLinkSet
   * @param publishedState 'Draft' or 'Live'
   */
  @AuraEnabled(cacheable=true)
  public static List<MenuItemDTO> getNavigationMenuItems(
    String menuName,
    String publishedState
  ) {
    List<MenuItemDTO> empty = new List<MenuItemDTO>();
    if (String.isBlank(menuName)) {
      return empty;
    }

    String status = String.isBlank(publishedState) ? 'Live' : publishedState;
    String networkId = Network.getNetworkId();

    List<NavigationLinkSet> linkSets = [
      SELECT Id
      FROM NavigationLinkSet
      WHERE
        NetworkId = :networkId
        AND (MasterLabel = :menuName
        OR DeveloperName = :menuName)
      LIMIT 1
    ];

    if (linkSets.isEmpty()) {
      return empty;
    }

    Id linkSetId = linkSets[0].Id;

    // Ordered by Position so tree assembly preserves menu order
    List<NavigationMenuItem> records = [
      SELECT Id, Label, Target, Type, ParentId, Position, Status
      FROM NavigationMenuItem
      WHERE NavigationLinkSetId = :linkSetId AND Status = :status
      ORDER BY Position
    ];

    Map<Id, MenuItemDTO> byId = new Map<Id, MenuItemDTO>();
    for (NavigationMenuItem record : records) {
      MenuItemDTO dto = new MenuItemDTO();
      dto.id = record.Id;
      dto.label = record.Label;
      dto.target = record.Target;
      dto.type = record.Type;
      dto.parentId = record.ParentId;
      dto.position = record.Position;
      dto.subMenu = new List<MenuItemDTO>();
      byId.put(record.Id, dto);
    }

    List<MenuItemDTO> roots = new List<MenuItemDTO>();
    for (NavigationMenuItem record : records) {
      MenuItemDTO dto = byId.get(record.Id);
      if (dto.parentId != null && byId.containsKey(dto.parentId)) {
        byId.get(dto.parentId).subMenu.add(dto);
      } else {
        roots.add(dto);
      }
    }

    return roots;
  }
}