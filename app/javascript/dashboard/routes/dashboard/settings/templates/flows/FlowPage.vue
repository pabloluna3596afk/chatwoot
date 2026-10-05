<script setup>
// The full page of a flow, under Settings → Templates & Flows: the start screen of a new one, or the builder (a draft
// that is not saved yet, or a saved flow). Back goes to the Flows tab of the list.
import { ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import WhatsappFlowsAPI from 'dashboard/api/whatsappFlows';
import FlowBuilderPage from './FlowBuilderPage.vue';
import FlowStart from './FlowStart.vue';
import { clearFlowDraft, getFlowDraft, setFlowDraft } from './flowDraft';

const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const flow = ref(null);
// A new builder is mounted for each flow that is loaded, not for the first save of a draft.
const builderKey = ref(0);

const toList = () =>
  router.push({ name: 'settings_templates', query: { tab: 'flows' } });

const onCreate = started => {
  setFlowDraft(started);
  router.replace({ name: 'settings_flow_draft' });
};

const onSaved = saved => {
  // The first save gives the draft its own address, so a reload opens the saved flow.
  if (route.name === 'settings_flow_draft') {
    clearFlowDraft();
    flow.value = { ...flow.value, ...saved };
    router.replace({
      name: 'settings_flow_edit',
      params: { flowId: saved.id },
    });
  }
};

const load = async () => {
  if (route.name === 'settings_flow_draft') {
    const draft = getFlowDraft();
    if (draft) {
      flow.value = draft;
      builderKey.value += 1;
    } else router.replace({ name: 'settings_flow_new' });
  } else if (route.name === 'settings_flow_edit') {
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
      <FlowStart
        v-if="route.name === 'settings_flow_new'"
        @create="onCreate"
        @cancel="toList"
      />
      <FlowBuilderPage
        v-else-if="flow"
        :key="builderKey"
        :flow="flow"
        @back="toList"
        @saved="onSaved"
      />
    </div>
  </div>
</template>
