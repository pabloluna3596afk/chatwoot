<script setup>
import { computed, nextTick, ref, watch, useId } from 'vue';
import VariablePicker from 'dashboard/components-next/variable-picker/VariablePicker.vue';
import { useI18n } from 'vue-i18n';
import { bodySegments } from './helpers';

const props = defineProps({
  text: { type: String, required: true },
  values: { type: Object, default: () => ({}) },
  expressions: { type: Object, default: () => ({}) },
  labelFor: { type: Function, required: true },
  invalidKeys: { type: Array, default: () => [] },
  attempted: { type: Boolean, default: false },
  examples: { type: Object, default: () => ({}) },
  variableFilter: { type: Function, default: () => true },
  variableSurface: { type: String, default: 'message' },
});
const emit = defineEmits(['change', 'select', 'advance']);
const { t } = useI18n();
const prefix = 'WHATSAPP_TEMPLATES.SEND_CENTER';
const root = ref(null);
const touched = ref([]);
const hintOnEnd = ref({});
const id = useId();
const keys = computed(() => [
  ...new Set(
    bodySegments(props.text)
      .filter(part => part.key)
      .map(part => part.key)
  ),
]);
const segments = computed(() =>
  bodySegments(props.text).map(part =>
    part.key ? { ...part, ordinal: keys.value.indexOf(part.key) + 1 } : part
  )
);
const label = key => props.labelFor(key, keys.value.indexOf(key));
const placeholder = key =>
  props.examples[key] ||
  t(`${prefix}.DATA`, { index: keys.value.indexOf(key) + 1 });
const dataLabel = part =>
  t(`${prefix}.DATA_LABEL`, {
    index: part.ordinal,
    total: keys.value.length,
    example: placeholder(part.key),
  });
const isInvalid = key =>
  (props.invalidKeys.includes(key) ||
    !String(props.values[key] || '').trim()) &&
  (props.attempted || touched.value.includes(key));
const missingLabels = computed(() =>
  [...new Set(props.invalidKeys)].map(key => label(key))
);
const isContact = key =>
  /{{\s*(contact[.\s]|contacto[.\s])/.test(
    props.expressions[key] || props.values[key] || ''
  );
const update = (key, event) => {
  if (!event.isComposing && !event.target.composing)
    emit('change', key, event.target.value);
};
const advance = event => {
  if (event.isComposing || event.target.composing || event.keyCode === 229)
    return;
  event.preventDefault();
  emit('advance', event.target);
};
const revealField = event =>
  event.target.scrollIntoView?.({ block: 'nearest', inline: 'nearest' });
const positionHint = (key, event) => {
  const field = event.currentTarget.getBoundingClientRect();
  const body = root.value.getBoundingClientRect();
  hintOnEnd.value[key] = field.x + field.width / 2 > body.x + body.width / 2;
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
    touched.value = [];
    await nextTick();
    root.value?.querySelector('textarea')?.focus({ preventScroll: true });
  },
  { immediate: true }
);
defineExpose({ missingLabels });
</script>

<template>
  <div
    ref="root"
    class="whitespace-pre-wrap leading-[1.5]"
    data-testid="editable-body"
  >
    <template v-for="(part, index) in segments" :key="index">
      <span
        v-if="part.key"
        class="group/data relative inline-grid max-w-full grid-cols-[auto_minmax(0,1fr)] items-start gap-x-1 rounded-md border border-solid px-1 align-baseline whitespace-normal hover:border-n-brand focus-within:border-n-brand focus-within:ring-2 focus-within:ring-n-brand/30"
        :class="
          isInvalid(part.key)
            ? 'border-n-ruby-8 bg-n-ruby-3'
            : values[part.key]
              ? 'border-n-weak bg-n-alpha-2'
              : 'border-n-brand/30 bg-n-brand/10'
        "
        @mouseenter="positionHint(part.key, $event)"
        @focusin="positionHint(part.key, $event)"
      >
        <span
          aria-hidden="true"
          class="mt-[0.1875rem] flex size-[0.875rem] items-center justify-center rounded-full bg-n-brand text-[0.5625rem] font-semibold leading-none text-white"
          >{{ part.ordinal }}</span
        >
        <span
          aria-hidden="true"
          class="invisible col-start-2 row-start-1 min-w-[6ch] whitespace-pre-wrap break-all text-sm leading-5"
          >{{ String(values[part.key] || placeholder(part.key)) + ' ' }}</span
        >
        <textarea
          :value="values[part.key] || ''"
          rows="1"
          cols="1"
          data-template-field
          class="reset-base col-start-2 row-start-1 m-0 h-full min-h-0 w-full min-w-0 resize-none overflow-hidden whitespace-pre-wrap break-all border-0 bg-transparent p-0 text-sm leading-5 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-0"
          :placeholder="placeholder(part.key)"
          :aria-label="dataLabel(part)"
          :aria-describedby="`${id}-hint-${index}${isInvalid(part.key) ? ` ${id}-error-${part.ordinal}` : ''}`"
          :aria-invalid="isInvalid(part.key)"
          :title="isContact(part.key) ? expressions[part.key] : undefined"
          @compositionstart="$event.target.composing = true"
          @compositionend="
            $event.target.composing = false;
            update(part.key, $event);
          "
          @input="update(part.key, $event)"
          @blur="touched.push(part.key)"
          @focus="revealField"
          @keydown.enter="advance"
        />
        <span
          v-if="isContact(part.key)"
          aria-hidden="true"
          class="absolute -end-1 -top-1 size-1.5 rounded-full bg-n-teal-9"
        />
        <span
          :id="`${id}-hint-${index}`"
          class="pointer-events-none absolute top-full mt-1 opacity-0 z-10 flex w-max max-w-[20rem] whitespace-nowrap items-center gap-2 rounded-md border border-solid border-n-weak bg-n-solid-1 p-1 text-xs leading-4 text-n-slate-11 shadow-md group-hover/data:pointer-events-auto group-hover/data:opacity-100 group-focus-within/data:pointer-events-auto group-focus-within/data:opacity-100"
          :class="hintOnEnd[part.key] ? 'end-0' : 'start-0'"
        >
          <span
            >{{
              $t(`${prefix}.DATA_POSITION`, {
                index: part.ordinal,
                total: keys.length,
              })
            }}<template v-if="examples[part.key]">
              ·
              {{
                $t(`${prefix}.EXAMPLE`, { example: examples[part.key] })
              }}</template
            ></span
          >
          <VariablePicker
            presentation="insert"
            :show-label="false"
            :surface="variableSurface"
            :filter="variableFilter"
            :placeholder="$t('VARIABLES.INSERT_IN_FIELD')"
            :aria-label="$t(`${prefix}.DATA_PICKER`)"
            :title="$t(`${prefix}.DATA_PICKER`)"
            class="!w-6 shrink-0 [&_button[aria-haspopup=listbox]]:!size-6 [&_button[aria-haspopup=listbox]]:!p-0"
            @select="emit('select', part.key, $event.expression)"
          />
          <span class="sr-only">{{ $t(`${prefix}.DATA_PICKER`) }}</span>
        </span>
      </span>
      <template v-else>{{ part.text }}</template>
    </template>
  </div>
  <template v-for="(key, index) in keys" :key="key">
    <p
      v-if="isInvalid(key)"
      :id="`${id}-error-${index + 1}`"
      class="mt-2 text-xs text-n-ruby-11"
      role="status"
    >
      {{ $t(`${prefix}.DATA_REQUIRED`, { index: index + 1 }) }}
    </p>
  </template>
</template>
