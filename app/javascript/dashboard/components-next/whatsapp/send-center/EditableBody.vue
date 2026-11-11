<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import WhatsAppText from './WhatsAppText';
import TemplateDataField from './TemplateDataField.vue';
import { useI18n } from 'vue-i18n';
import { bodySegments } from './helpers';

const props = defineProps({
  text: { type: String, required: true },
  values: { type: Object, default: () => ({}) },
  expressions: { type: Object, default: () => ({}) },
  labelFor: { type: Function, required: true },
  invalidKeys: { type: Array, default: () => [] },
  attempted: { type: Boolean, default: false },
  systemVariables: { type: Array, default: () => [] },
  variablesStatus: { type: String, default: 'ready' },
  variableFilter: { type: Function, default: () => true },
});
const emit = defineEmits(['change', 'select', 'advance', 'hint']);
const { t } = useI18n();
const root = ref(null);

const keys = computed(() => [
  ...new Set(
    bodySegments(props.text)
      .filter(part => part.key)
      .map(part => part.key)
  ),
]);
const label = key => props.labelFor(key, keys.value.indexOf(key));
const placeholder = computed(() =>
  t('WHATSAPP_TEMPLATES.SEND_CENTER.DATA_PLACEHOLDER')
);
const isMissing = key =>
  props.invalidKeys.includes(key) || !String(props.values[key] || '').trim();
const missingLabels = computed(() => keys.value.filter(isMissing).map(label));
const options = computed(() =>
  props.systemVariables.filter(props.variableFilter)
);
const revealField = event =>
  event.target.scrollIntoView?.({ block: 'nearest', inline: 'nearest' });
const focusField = (part, event) => {
  revealField(event);
  emit('hint', event.target.title || label(part.key));
};
watch(
  () => props.values,
  async () => {
    await nextTick();
    root.value
      ?.querySelector('textarea:focus')
      ?.scrollIntoView?.({ block: 'nearest', inline: 'nearest' });
  },
  { deep: true }
);
watch(
  () => props.text,
  async () => {
    await nextTick();
    root.value?.querySelector('textarea')?.focus({ preventScroll: true });
  },
  { immediate: true }
);
defineExpose({ missingLabels });
</script>

<template>
  <div ref="root" data-testid="editable-body">
    <WhatsAppText :text="text">
      <template #field="{ key }">
        <TemplateDataField
          :value="String(values[key] || '')"
          :expression="expressions[key] || ''"
          :label="label(key)"
          :placeholder="placeholder"
          :missing="isMissing(key)"
          :attempted="attempted"
          :options="options"
          :status="variablesStatus"
          @change="emit('change', key, $event)"
          @select="emit('select', key, $event)"
          @advance="emit('advance', $event)"
          @focus="focusField({ key }, $event)"
          @leave="emit('hint', '')"
        />
      </template>
    </WhatsAppText>
  </div>
</template>
