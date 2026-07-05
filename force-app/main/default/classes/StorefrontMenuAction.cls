/**
    * Returns a plain-text menu for a storefront name so an agent can respond
    * with a simple bulleted list in chat.
    */
    public without sharing class StorefrontMenuAction {
        private class MenuSection {
            public String label;
            public List<String> categoryOrder = new List<String>();
            public Map<String, List<String>> itemsByCategory = new Map<String, List<String>>();
        }
    
        public class StorefrontMenuInput {
            @InvocableVariable(
                label='Storefront Name'
                description='Exact storefront name to resolve to a menu.'
                required=true
            )
            public String storefrontName;
        }
    
        public class StorefrontMenuResult {
            @InvocableVariable(
                label='Menu Response'
                description='Plain text response containing a bulleted storefront menu.'
            )
            public String menuResponse;
        }
    
        @InvocableMethod(
            label='Get Storefront Menu'
            description='Returns a simple bullet list of available menu items for an exact storefront name.'
        )
        public static List<StorefrontMenuResult> getStorefrontMenu(
            List<StorefrontMenuInput> inputs
        ) {
            StorefrontMenuInput input =
                (inputs != null && !inputs.isEmpty()) ? inputs[0] : null;
            StorefrontMenuResult result = new StorefrontMenuResult();
            result.menuResponse = buildMenuResponse(input == null ? null : input.storefrontName);
            return new List<StorefrontMenuResult>{ result };
        }
    
        @TestVisible
        private static String buildMenuResponse(String storefrontName) {
            if (String.isBlank(storefrontName)) {
                return 'Menu unavailable because storefront name is required.';
            }
    
            List<Storefront__c> storefronts = [
                SELECT Id, Name
                FROM Storefront__c
                WHERE Name = :storefrontName.trim()
                ORDER BY CreatedDate ASC
                LIMIT 2
            ];
    
            if (storefronts.isEmpty()) {
                return 'Menu unavailable for ' + storefrontName.trim() + '.';
            }
    
            if (storefronts.size() > 1) {
                return 'More than one storefront is named ' + storefrontName.trim() +
                    '. Please try a more specific storefront.';
            }
    
            Storefront__c storefront = storefronts[0];
            List<Menu__c> menus = [
                SELECT Id, Name, Menu_Display_Name__c
                FROM Menu__c
                WHERE Storefront__c = :storefront.Id
                    AND Active__c = true
                ORDER BY Menu_Display_Name__c NULLS LAST, Name ASC
                LIMIT 200
            ];
    
            if (menus.isEmpty()) {
                return 'No active menu is available for ' + storefront.Name + '.';
            }
    
            List<Id> menuOrder = new List<Id>();
            Set<Id> menuIds = new Set<Id>();
            Map<Id, MenuSection> menuSectionsById = new Map<Id, MenuSection>();
            for (Menu__c menuRecord : menus) {
                MenuSection menuSection = new MenuSection();
                menuSection.label = getMenuLabel(menuRecord);
                menuSectionsById.put(menuRecord.Id, menuSection);
                menuOrder.add(menuRecord.Id);
                menuIds.add(menuRecord.Id);
            }
    
            List<Menu_Item__c> menuItems = [
                SELECT
                    Name,
                    Price__c,
                    Menu__c,
                    Menu_Category__r.Name
                FROM Menu_Item__c
                WHERE Menu__c IN :menuIds
                    AND Available__c = true
                ORDER BY
                    Menu__r.Menu_Display_Name__c NULLS LAST,
                    Menu__r.Name ASC,
                    Menu_Category__r.Name NULLS LAST,
                    Name ASC
                LIMIT 500
            ];
    
            if (menuItems.isEmpty()) {
                return 'No available menu items were found for ' + storefront.Name + '.';
            }
    
            List<String> lines = new List<String>{ 'Menu for ' + storefront.Name + ':' };
            Integer renderedMenuCount = 0;
            for (Menu_Item__c menuItem : menuItems) {
                MenuSection menuSection = menuSectionsById.get(menuItem.Menu__c);
                if (menuSection == null) {
                    continue;
                }
    
                String categoryLabel = getCategoryLabel(menuItem);
                if (!menuSection.itemsByCategory.containsKey(categoryLabel)) {
                    menuSection.itemsByCategory.put(categoryLabel, new List<String>());
                    menuSection.categoryOrder.add(categoryLabel);
                }
    
                menuSection.itemsByCategory.get(categoryLabel).add(getMenuItemLabel(menuItem));
            }
    
            for (Id menuId : menuOrder) {
                MenuSection menuSection = menuSectionsById.get(menuId);
                if (menuSection == null || menuSection.categoryOrder.isEmpty()) {
                    continue;
                }
    
                renderedMenuCount++;
                lines.add('• ' + menuSection.label);
                for (String categoryLabel : menuSection.categoryOrder) {
                    lines.add('  • ' + categoryLabel);
                    for (String itemLabel : menuSection.itemsByCategory.get(categoryLabel)) {
                        lines.add('    • ' + itemLabel);
                    }
                }
            }
    
            if (renderedMenuCount == 0) {
                return 'No available menu items were found for ' + storefront.Name + '.';
            }
    
            return String.join(lines, '\n');
        }
    
        private static String getMenuLabel(Menu__c menuRecord) {
            if (!String.isBlank(menuRecord.Menu_Display_Name__c)) {
                return menuRecord.Menu_Display_Name__c.trim();
            }
    
            if (!String.isBlank(menuRecord.Name)) {
                return menuRecord.Name.trim();
            }
    
            return 'Menu';
        }
    
        private static String getCategoryLabel(Menu_Item__c menuItem) {
            String categoryName =
                menuItem.Menu_Category__r == null ? null : menuItem.Menu_Category__r.Name;
    
            if (!String.isBlank(categoryName)) {
                return categoryName.trim();
            }
    
            return 'Uncategorized';
        }
    
        private static String getMenuItemLabel(Menu_Item__c menuItem) {
            String itemLabel = menuItem.Name;
            if (menuItem.Price__c == null) {
                return itemLabel;
            }
    
            return itemLabel + ' ($' + String.valueOf(menuItem.Price__c.setScale(2)) + ')';
        }
    }