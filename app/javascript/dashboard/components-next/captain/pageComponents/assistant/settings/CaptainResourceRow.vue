<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';

const props = defineProps({
  name: { type: String, required: true },
  language: { type: String, default: '' },
  category: { type: String, default: '' },
  state: { type: String, required: true },
  stateLabel: { type: String, default: '' },
  usages: { type: Array, default: () => [] },
  disabled: { type: Boolean, default: false },
  dimmed: { type: Boolean, default: false },
  publishRoute: { type: Object, default: null },
});
defineEmits(['toggle', 'preview', 'assign']);
const { t } = useI18n();
const canToggle = computed(() =>
  [
    'available',
    'excluded',
    'marketing_off',
    'new',
    'changed',
    'needs_review',
    'unavailable',
  ].includes(props.state)
);
const needsPermission = computed(() =>
  ['marketing_off', 'new', 'changed', 'needs_review', 'needs_data'].includes(
    props.state
  )
);
</script>

<template>
  <li
    class="flex items-center gap-3 px-3 py-2"
    :class="{ 'opacity-50': dimmed }"
  >
    <div class="min-w-0 grow">
      <div class="flex flex-wrap items-center gap-1.5">
        <span class="break-all text-heading-3 text-n-slate-12">{{ name }}</span>
        <span v-if="language" class="text-label-small text-n-slate-10">{{
          language
        }}</span>
        <span
          v-if="category && state !== 'marketing_off'"
          class="rounded-md bg-n-alpha-2 px-2 py-0.5 text-label-small text-n-slate-11"
          >{{ category }}</span
        >
        <span
          v-if="stateLabel"
          class="rounded-md px-2 py-0.5 text-label-small"
          :class="
            needsPermission
              ? 'bg-n-amber-3 text-n-amber-11'
              : 'bg-n-alpha-2 text-n-slate-11'
          "
          >{{ stateLabel }}</span
        >
        <span
          v-for="usage in usages"
          :key="usage"
          class="rounded-md bg-n-blue-3 px-2 py-0.5 text-label-small text-n-blue-11"
          >{{ usage }}</span
        >
      </div>
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
        v-if="state === 'needs_data'"
        intent="secondary"
        sm
        :disabled="disabled"
        :label="t('CAPTAIN.ASSISTANTS.ENVIOS.TEMPLATES.ASSIGN')"
        @click="$emit('assign')"
      />
      <Button
        v-else-if="publishRoute"
        intent="secondary"
        sm
        :label="t('CAPTAIN.ASSISTANTS.ENVIOS.FLOWS.PUBLISH')"
        :to="publishRoute"
      />
      <Switch
        v-else-if="canToggle"
        :model-value="state === 'available'"
        :disabled="disabled || state === 'unavailable'"
        :aria-label="
          t('CAPTAIN.ASSISTANTS.ENVIOS.RESOURCE_PERMISSION', { name })
        "
        @update:model-value="$emit('toggle')"
      />
    </div>
  </li>
</template>
