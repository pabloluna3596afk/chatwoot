import { computed } from 'vue';
import { useVariableCatalog } from 'dashboard/composables/useVariableCatalog';
import {
  catalogBindings,
  defaultValuesFor,
} from 'dashboard/helper/templateVariableBindings';

// Legacy Meta aliases and paths are adapters over the account's server catalog.
export const useTemplateBindings = (context = 'message') => {
  const catalog = useVariableCatalog(context);
  const bindings = computed(() => catalogBindings(catalog.variables.value));
  const defaultValues = computed(() => defaultValuesFor(bindings.value));
  return { ...catalog, bindings, defaultValues };
};
