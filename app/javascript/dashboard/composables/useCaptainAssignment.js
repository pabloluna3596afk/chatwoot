import { computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';

export function useCaptainAssignment() {
  const { t } = useI18n();
  const route = useRoute();
  const store = useStore();
  const featureEnabled = useMapGetter('accounts/isFeatureEnabledonAccount');
  const assistants = useMapGetter('captainAssistants/getRecords');
  const enabled = computed(
    () =>
      featureEnabled.value?.(
        Number(route.params.accountId),
        'captain_integration'
      ) === true
  );
  const options = computed(() => {
    if (!enabled.value || !assistants.value?.length) return [];
    return [
      {
        id: 'captain',
        name: t('CAPTAIN.ASSIGNMENT.GENERAL'),
        icon: 'i-woot-captain',
      },
      ...assistants.value.map(assistant => ({
        id: `captain:${assistant.id}`,
        name: assistant.name,
        icon: 'i-woot-captain',
      })),
    ];
  });
  onMounted(() => {
    if (enabled.value) store.dispatch('captainAssistants/get');
  });
  return { enabled, options };
}
