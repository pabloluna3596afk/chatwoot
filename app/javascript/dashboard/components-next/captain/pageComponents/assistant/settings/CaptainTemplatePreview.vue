<script setup>
import AssistantNameText from 'dashboard/components-next/AssistantNameText.vue';
import { useAssistantName } from 'dashboard/composables/useAssistantName';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import SidePanel from 'dashboard/components-next/side-panel/SidePanel.vue';
import WhatsAppBubble from 'dashboard/components-next/whatsapp/WhatsAppBubble.vue';
import { bubbleForCaptain } from './captainTemplatePreview';

const props = defineProps({
  assistant: { type: Object, default: () => ({}) },
  template: { type: Object, default: null },
  params: { type: Object, default: () => ({}) },
  sources: { type: Object, default: () => ({}) },
  complete: { type: Boolean, default: true },
  available: { type: Boolean, default: true },
  inboxName: { type: String, default: '' },
  previewValues: { type: Object, default: () => ({}) },
});

const { t } = useI18n();
const { nameRich } = useAssistantName(() => props.assistant);

const panelRef = ref(null);
const preview = computed(() => {
  const result = props.template
    ? bubbleForCaptain(props.template, props.params, props.previewValues)
    : { bubble: {}, variables: { body: {}, header: {} } };
  ['header', 'body'].forEach(group => {
    Object.entries(result.variables[group]).forEach(([name, value]) => {
      if (!value)
        result.bubble[group] = result.bubble[group].replaceAll(
          `[${name}]`,
          `{{${name}}}`
        );
    });
  });
  return result;
});
const parts = text => (text || '').split(/(\{\{[^}]+\}\})/g);
const variables = computed(() =>
  ['header', 'body'].flatMap(group =>
    Object.entries(preview.value.variables[group]).map(([name, value]) => {
      const source = props.sources[group]?.[name];
      const sourceLabels = {
        alias: 'SOURCE_ALIAS',
        binding: 'SOURCE_BINDING',
        assistant: 'SOURCE_ASSISTANT',
        legacy: 'SOURCE_LEGACY',
      };
      return {
        name,
        value,
        group,
        source: t(
          `CAPTAIN.ASSISTANTS.ENVIOS.PREVIEW_PANEL.${sourceLabels[source] || 'MISSING'}`
        ),
      };
    })
  )
);

const open = () => panelRef.value?.open();
const close = () => panelRef.value?.close();
defineExpose({ open, close });
</script>

<template>
  <SidePanel
    ref="panelRef"
    width="md"
    :title="template?.name || ''"
    :description="
      nameRich('CAPTAIN.ASSISTANTS.ENVIOS.PREVIEW_PANEL.DESCRIPTION')
    "
    full-screen-on-mobile
  >
    <div v-if="available" class="flex flex-col gap-5">
      <p
        v-if="!complete"
        class="mb-0 rounded-lg bg-n-amber-3 p-3 text-sm text-n-amber-11"
        role="status"
      >
        <AssistantNameText
          :text="
            nameRich(
              'CAPTAIN.ASSISTANTS.ENVIOS.PREVIEW_PANEL.MISSING_VARIABLES'
            )
          "
        />
      </p>
      <WhatsAppBubble v-bind="preview.bubble" class="mx-auto w-full max-w-sm">
        <template v-for="group in ['header', 'body']" :key="group" #[group]>
          <p
            class="whitespace-pre-wrap"
            :class="{ 'font-semibold': group === 'header' }"
          >
            <span
              v-for="(part, index) in parts(preview.bubble[group])"
              :key="index"
              :class="
                part.startsWith('{{')
                  ? 'rounded bg-n-amber-3 px-1 text-n-amber-11'
                  : ''
              "
              >{{ part }}</span
            >
          </p>
        </template>
      </WhatsAppBubble>
      <section v-if="variables.length">
        <h3 class="m-0 text-sm font-medium text-n-slate-12">
          <AssistantNameText
            :text="
              nameRich(
                'CAPTAIN.ASSISTANTS.ENVIOS.PREVIEW_PANEL.VARIABLES_TITLE'
              )
            "
          />
        </h3>
        <dl class="mt-3 grid grid-cols-[7rem_1fr] gap-x-3 gap-y-2 text-sm">
          <template
            v-for="item in variables"
            :key="`${item.group}-${item.name}`"
          >
            <dt class="text-n-slate-10">{{ item.name }}</dt>
            <dd class="m-0 text-n-slate-12">
              {{
                item.value ||
                t('CAPTAIN.ASSISTANTS.ENVIOS.PREVIEW_PANEL.MISSING')
              }}
              <span class="block text-xs text-n-slate-10">{{
                item.source
              }}</span>
            </dd>
          </template>
        </dl>
      </section>
      <p class="mb-0 text-xs text-n-slate-10">
        {{
          t('CAPTAIN.ASSISTANTS.ENVIOS.PREVIEW_PANEL.INBOX', {
            name: inboxName,
          })
        }}
      </p>
    </div>
    <p v-else class="mb-0 text-sm text-n-slate-11" role="status">
      {{ t('CAPTAIN.ASSISTANTS.ENVIOS.PREVIEW_PANEL.TEMPLATE_UNAVAILABLE') }}
    </p>
  </SidePanel>
</template>
