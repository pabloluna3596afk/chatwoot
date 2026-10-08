import { computed, onMounted } from 'vue';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import {
  buildBindings,
  defaultValuesFor,
} from 'dashboard/helper/templateVariableBindings';

// The CRM names a template variable can have (see templateVariableBindings), with the account's custom attributes.
// `context` is 'message' (a conversation) or 'campaign' (no conversation values). `defaultValues` is what the send
// dialog starts a variable with, by its name.
export const useTemplateBindings = (
  context = 'message',
  providedAttributes = null
) => {
  const store = useStore();
  const attributes = useMapGetter('attributes/getAttributes');

  onMounted(() => {
    if (providedAttributes?.value !== null && providedAttributes) return;
    if (!attributes.value?.length) store.dispatch('attributes/get');
  });

  const bindings = computed(() =>
    buildBindings(providedAttributes?.value ?? attributes.value, context)
  );
  const defaultValues = computed(() => defaultValuesFor(bindings.value));
  return { bindings, defaultValues };
};
