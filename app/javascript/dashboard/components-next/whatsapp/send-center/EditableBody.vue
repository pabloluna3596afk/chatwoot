<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { bodySegments } from './helpers';

const props = defineProps({
  text: { type: String, required: true },
  values: { type: Object, default: () => ({}) },
  labelFor: { type: Function, required: true },
  invalidKeys: { type: Array, default: () => [] },
  attempted: { type: Boolean, default: false },
});
const emit = defineEmits(['change']);
const root = ref(null);
const touched = ref([]);
const segments = computed(() => {
  let ordinal = 0;
  return bodySegments(props.text).map(part => {
    if (!part.key) return part;
    ordinal += 1;
    return { ...part, ordinal };
  });
});
const keys = computed(() =>
  segments.value.filter(part => part.key).map(part => part.key)
);
const label = key => props.labelFor(key, keys.value.indexOf(key));
const isInvalid = key =>
  props.invalidKeys.includes(key) &&
  (props.attempted || touched.value.includes(key));
const missingLabels = computed(() =>
  [...new Set(props.invalidKeys)].map(key => label(key))
);
const revealField = event => {
  event.target.scrollIntoView?.({ block: 'nearest', inline: 'nearest' });
};
defineExpose({ missingLabels });
const update = (key, event) => {
  if (!event.isComposing && !event.target.composing)
    emit('change', key, event.target.value);
};
watch(
  () => props.text,
  async () => {
    touched.value = [];
    await nextTick();
    root.value?.querySelector('input')?.focus({ preventScroll: true });
  },
  { immediate: true }
);
</script>

<template>
  <div ref="root" class="whitespace-pre-wrap" data-testid="editable-body">
    <template v-for="(part, index) in segments" :key="index">
      <span
        v-if="part.key"
        class="relative inline-grid max-w-full align-baseline whitespace-normal"
      >
        <span
          aria-hidden="true"
          class="invisible col-start-1 row-start-1 whitespace-pre-wrap break-all border px-2 py-1 text-sm"
          >{{ String(values[part.key] || label(part.key)) + ' ' }}</span
        >
        <input
          :value="values[part.key] || ''"
          type="text"
          size="1"
          class="col-start-1 row-start-1 w-full min-w-0 rounded-md border px-2 py-1 text-sm text-n-slate-12 placeholder:text-n-slate-11 focus:outline focus:outline-2 focus:outline-n-brand"
          :class="
            isInvalid(part.key)
              ? 'border-n-ruby-8 bg-n-ruby-3'
              : 'border-n-brand/40 bg-n-brand/10'
          "
          :placeholder="label(part.key)"
          :aria-label="
            $t('WHATSAPP_TEMPLATES.SEND_CENTER.DATA_LABEL', {
              name: label(part.key),
              index: part.ordinal,
              total: keys.length,
            })
          "
          :aria-invalid="isInvalid(part.key)"
          :autofocus="part.ordinal === 1"
          @compositionstart="$event.target.composing = true"
          @compositionend="
            $event.target.composing = false;
            update(part.key, $event);
          "
          @input="update(part.key, $event)"
          @blur="touched.push(part.key)"
          @focus="revealField" /></span
      ><template v-else>{{ part.text }}</template>
    </template>
  </div>
</template>
