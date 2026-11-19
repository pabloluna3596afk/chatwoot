<script setup>
import { useAssistantName } from 'dashboard/composables/useAssistantName';
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { variableTokens } from 'dashboard/routes/dashboard/settings/templates/templateData';
import Button from 'dashboard/components-next/button/Button.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';

const props = defineProps({
  assistant: { type: Object, default: () => ({}) },
  name: { type: String, required: true },
  language: { type: String, default: '' },
  reason: { type: String, default: '' },
  missing: { type: Array, default: () => [] },
  configureRoute: { type: Object, default: () => ({}) },
  state: { type: String, required: true },
  stateLabel: { type: String, default: '' },
  usedBy: { type: Array, default: () => [] },
  disabled: { type: Boolean, default: false },
  dimmed: { type: Boolean, default: false },
  modelValue: { type: Boolean, default: false },
  disabledReason: { type: String, default: '' },
  blocked: { type: Boolean, default: false },
});
defineEmits(['update:modelValue', 'preview', 'publish']);
const { t } = useI18n();
const { nameText } = useAssistantName(() => props.assistant);

const canToggle = computed(() =>
  [
    'available',
    'excluded',
    'unavailable',
    'new',
    'changed',
    'needs_review',
  ].includes(props.state)
);
const needsPermission = computed(() =>
  ['new', 'changed', 'needs_review'].includes(props.state)
);
</script>

<template>
  <li
    class="flex min-h-[2.875rem] items-center justify-between gap-3 px-3 py-2.5"
    :class="{ 'opacity-50': dimmed, 'opacity-60': blocked && !dimmed }"
  >
    <div class="min-w-0 grow">
      <div class="flex flex-wrap items-center gap-1.5">
        <span class="break-all text-sm font-medium text-n-slate-12">{{
          name
        }}</span>
        <span v-if="language" class="text-xs text-n-slate-10">{{
          language
        }}</span>
        <span
          v-if="stateLabel"
          class="rounded-md px-2 py-0.5 text-xs"
          :class="
            needsPermission || (disabled && !blocked)
              ? 'bg-n-amber-3 text-n-amber-11'
              : 'bg-n-alpha-2 text-n-slate-11'
          "
          >{{ stateLabel }}</span
        >
        <span
          v-for="usage in usedBy"
          :key="usage"
          class="rounded-md bg-n-blue-3 px-2 py-0.5 text-xs text-n-blue-11"
          >{{ usage }}</span
        >
      </div>
      <p v-if="reason" class="mb-0 mt-1 text-xs text-n-slate-11">
        {{ reason }}
      </p>
      <p
        v-if="state === 'needs_data'"
        class="mb-0 mt-1 text-xs text-n-amber-11"
      >
        {{
          t('CAPTAIN.ASSISTANTS.ENVIOS.REASONS.NEEDS_DATA', {
            variables: variableTokens(missing),
          })
        }}
        <RouterLink :to="configureRoute" class="text-n-brand underline">
          {{ t('CAPTAIN.ASSISTANTS.ENVIOS.CONFIGURE_IN_TEMPLATES') }}
        </RouterLink>
      </p>
    </div>
    <div class="flex shrink-0 items-center gap-2">
      <Button
        intent="secondary"
        sm
        icon="i-lucide-eye"
        data-testid="resource-preview"
        :aria-label="
          t(
            language
              ? 'CAPTAIN.ASSISTANTS.ENVIOS.PREVIEW_TEMPLATE'
              : 'CAPTAIN.ASSISTANTS.ENVIOS.PREVIEW_FLOW',
            { name }
          )
        "
        @click="$emit('preview')"
      />
      <Button
        v-if="state === 'not_published_here'"
        intent="secondary"
        sm
        :label="t('CAPTAIN.ASSISTANTS.ENVIOS.FLOWS.PUBLISH')"
        :disabled="disabled"
        :title="disabledReason"
        @click="$emit('publish')"
      />
      <Switch
        v-else-if="canToggle && !blocked"
        :model-value="modelValue"
        :disabled="disabled"
        :title="disabledReason"
        class="disabled:cursor-not-allowed disabled:opacity-50"
        :aria-label="nameText('CAPTAIN.ASSISTANTS.ENVIOS.ROW_SWITCH', { name })"
        @update:model-value="$emit('update:modelValue', $event)"
      />
    </div>
  </li>
</template>
