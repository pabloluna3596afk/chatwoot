import { computed, reactive, watch, toValue } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import VariablesAPI from 'dashboard/api/variables';

// Metadata only. Cache and in-flight requests are isolated by account + surface.
const catalogs = reactive(new Map());
const requests = new Map();

export const useVariableCatalog = (surface = 'message') => {
  const accountId = useMapGetter('getCurrentAccountId');
  const key = computed(() => `${accountId.value}:${toValue(surface)}`);
  const state = computed(() => {
    if (!catalogs.has(key.value)) {
      catalogs.set(key.value, { variables: [], status: 'idle' });
    }
    return catalogs.get(key.value);
  });
  const load = (refresh = false) => {
    const cacheKey = key.value;
    const entry = state.value;
    if (requests.has(cacheKey)) return requests.get(cacheKey);
    if (!refresh && entry.status === 'ready') return Promise.resolve();
    entry.status = 'loading';
    const request = VariablesAPI.catalog(accountId.value, toValue(surface))
      .then(({ data }) => {
        entry.variables = data.variables;
        entry.status = 'ready';
      })
      .catch(() => {
        // A failed refresh preserves metadata and all consumer-owned values.
        entry.status = 'error';
      })
      .finally(() => requests.delete(cacheKey));
    requests.set(cacheKey, request);
    return request;
  };
  watch(key, () => load(), { immediate: true });
  return {
    variables: computed(() => state.value.variables),
    status: computed(() => state.value.status),
    refresh: () => load(true),
  };
};
