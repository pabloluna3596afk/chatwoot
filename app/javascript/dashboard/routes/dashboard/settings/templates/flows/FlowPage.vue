<script setup>
// The full page of a flow, under Settings → Templates & Flows: a new one starts with the start step and then turns into
// the builder in this same page (nothing is created until it is saved), or a saved flow opens the builder directly.
// Back goes to the Flows tab of the list.
import { ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import WhatsappFlowsAPI from 'dashboard/api/whatsappFlows';
import FlowBuilderPage from './FlowBuilderPage.vue';
import FlowStart from './FlowStart.vue';

const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const flow = ref(null);
// A new builder is mounted for each flow that is loaded, not for the first save of a new one.
const builderKey = ref(0);

const toList = () =>
  router.push({ name: 'settings_templates', query: { tab: 'flows' } });

const onCreate = started => {
  flow.value = started;
  builderKey.value += 1;
};

const onSaved = saved => {
  // The first save gives the new flow its own address, so a reload opens the saved flow.
  if (route.name === 'settings_flow_new') {
    flow.value = { ...flow.value, ...saved };
    router.replace({
      name: 'settings_flow_edit',
      params: { flowId: saved.id },
    });
  }
};

const load = async () => {
  if (route.name === 'settings_flow_edit') {
    // Right after the first save the page already has this flow.
    if (String(flow.value?.id) === String(route.params.flowId)) return;
    flow.value = null;
    try {
      const { data } = await WhatsappFlowsAPI.show(route.params.flowId);
      flow.value = data;
      builderKey.value += 1;
    } catch {
      useAlert(t('WHATSAPP_FLOWS.LIST.LOAD_ERROR'));
      toList();
    }
  } else {
    // A new flow: the start step shows (again, after a reload).
    flow.value = null;
  }
};

watch(() => [route.name, route.params.flowId], load, { immediate: true });
</script>

<template>
  <div
    class="flex flex-col w-full h-full px-6 pt-4 pb-8 overflow-auto bg-n-surface-1"
    data-testid="flow-page"
  >
    <div class="w-full mx-auto max-w-[80rem]">
      <FlowBuilderPage
        v-if="flow"
        :key="builderKey"
        :flow="flow"
        @back="toList"
        @saved="onSaved"
      />
      <FlowStart
        v-else-if="route.name === 'settings_flow_new'"
        @create="onCreate"
        @cancel="toList"
      />
    </div>
  </div>
</template>
