import { computed, onMounted, unref } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';

import { buildCaptainOptions } from 'dashboard/helper/captainAssignmentOptions';

export function useCaptainAssignment({ inboxIds } = {}) {
  const { t } = useI18n();
  const route = useRoute();
  const store = useStore();
  const featureEnabled = useMapGetter('accounts/isFeatureEnabledonAccount');
  const assistants = useMapGetter('captainAssistants/getRecords');
  const inboxes = useMapGetter('inboxes/getInboxes');
  const enabled = computed(
    () =>
      featureEnabled.value?.(
        Number(route.params.accountId),
        'captain_integration'
      ) === true
  );
  const optionsForInboxes = (ids = []) =>
    enabled.value
      ? buildCaptainOptions({
          inboxIds: ids,
          inboxes: inboxes.value || [],
          assistants: assistants.value || [],
          t,
        })
      : [];
  const options = computed(() => optionsForInboxes(unref(inboxIds) || []));
  onMounted(() => {
    if (enabled.value) {
      store.dispatch('captainAssistants/get');
      store.dispatch('inboxes/get');
    }
  });
  return { enabled, options, optionsForInboxes };
}
