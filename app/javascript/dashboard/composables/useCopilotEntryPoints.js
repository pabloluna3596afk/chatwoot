import { computed } from 'vue';
import { useRoute } from 'vue-router';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import {
  isAConversationRoute,
  isAInboxViewRoute,
} from 'dashboard/helper/routeHelpers';

export const getCopilotEntryPoints = ({
  enabled,
  conversationSelected,
  contactSidebarOpen,
  copilotPanelOpen,
}) => {
  const showSidepanelCopilotTab =
    enabled && conversationSelected && !contactSidebarOpen;

  return {
    showSidepanelCopilotTab,
    showLauncher: enabled && !copilotPanelOpen && !showSidepanelCopilotTab,
  };
};

export const isCopilotConversationSelected = route =>
  (isAConversationRoute(route.name, true, true) ||
    isAInboxViewRoute(route.name, true)) &&
  !!(
    route.params.id ||
    route.params.conversationId ||
    route.params.conversation_id
  );

export const useCopilotEntryPoints = () => {
  const route = useRoute();
  const { uiSettings } = useUISettings();
  const currentAccountId = useMapGetter('getCurrentAccountId');
  const isFeatureEnabledonAccount = useMapGetter(
    'accounts/isFeatureEnabledonAccount'
  );

  const conversationSelected = computed(() =>
    isCopilotConversationSelected(route)
  );

  const entryPoints = computed(() =>
    getCopilotEntryPoints({
      enabled: isFeatureEnabledonAccount.value(
        currentAccountId.value,
        FEATURE_FLAGS.CAPTAIN
      ),
      conversationSelected: conversationSelected.value,
      contactSidebarOpen: !!uiSettings.value.is_contact_sidebar_open,
      copilotPanelOpen: !!uiSettings.value.is_copilot_panel_open,
    })
  );

  return {
    showCopilotLauncher: computed(() => entryPoints.value.showLauncher),
    showSidepanelCopilotTab: computed(
      () => entryPoints.value.showSidepanelCopilotTab
    ),
  };
};
