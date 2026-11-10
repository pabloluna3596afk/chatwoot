<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { bodySegments } from './helpers';

const props = defineProps({
  text: { type: String, required: true },
  values: { type: Object, default: () => ({}) },
  labelFor: { type: Function, required: true },
  invalidKeys: { type: Array, default: () => [] },
});
const emit = defineEmits(['change']);
const root = ref(null);
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
const update = (key, event) => {
  if (!event.isComposing && !event.target.composing)
    emit('change', key, event.target.value);
};
watch(
  () => props.text,
  async () => {
    await nextTick();
    root.value?.querySelector('input')?.focus({ preventScroll: true });
  },
  { immediate: true }
);
</script>

<template>
  <div ref="root" class="whitespace-pre-wrap" data-testid="editable-body">
    <template v-for="(part, index) in segments" :key="index">
      <input
        v-if="part.key"
        :value="values[part.key] || ''"
        type="text"
        class="inline-block w-auto min-w-0 max-w-full rounded border bg-n-alpha-2 px-1.5 py-0.5 text-sm text-n-slate-12 focus:outline focus:outline-2 focus:outline-n-brand"
        :class="
          invalidKeys.includes(part.key)
            ? 'border-n-ruby-8'
            : 'border-n-brand/40'
        "
        :size="
          Math.min(
            36,
            Math.max(4, String(values[part.key] || label(part.key)).length + 1)
          )
        "
        :placeholder="label(part.key)"
        :aria-label="
          $t('WHATSAPP_TEMPLATES.SEND_CENTER.DATA_LABEL', {
            name: label(part.key),
            index: part.ordinal,
            total: keys.length,
          })
        "
        :aria-invalid="invalidKeys.includes(part.key)"
        :autofocus="part.ordinal === 1"
        @compositionstart="$event.target.composing = true"
        @compositionend="
          $event.target.composing = false;
          update(part.key, $event);
        "
        @input="update(part.key, $event)"
      /><template v-else>{{ part.text }}</template>
    </template>
  </div>
</template>
