import { computed, watch } from 'vue';
import { useAccount } from './useAccount';
import { useStore } from './store';

export function usePlanCatalog() {
  const store = useStore();
  const { accountId } = useAccount();
  const load = (reload = false) =>
    store.dispatch('plans/load', { accountId: accountId.value, reload });
  watch(accountId, () => load(), { immediate: true });
  return {
    plans: computed(() =>
      store.state.plans.accountId === accountId.value
        ? store.state.plans.records
            .filter(plan => plan.state !== 'hidden')
            .slice()
            .sort((a, b) => a.display_order - b.display_order)
        : []
    ),
    status: computed(() =>
      store.state.plans.accountId === accountId.value
        ? store.state.plans.status
        : 'loading'
    ),
    retry: () => load(true),
  };
}
