<script setup>
import { computed, nextTick, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  value: { type: String, default: '' },
  expression: { type: String, default: '' },
  label: { type: String, required: true },
  placeholder: { type: String, default: '' },
  missing: { type: Boolean, default: false },
  attempted: { type: Boolean, default: false },
  options: { type: Array, default: () => [] },
  status: { type: String, default: 'ready' },
});
const emit = defineEmits(['change', 'select', 'advance', 'focus', 'leave']);
const { t } = useI18n();
const prefix = 'WHATSAPP_TEMPLATES.SEND_CENTER';
const CLOSE_MARK = '\u00d7';
const id = useId();
const input = ref(null);
const open = ref(false);
const active = ref(-1);
const alignment = ref('start');
const MENU_WIDTH_REM = 14;
const MENU_HEIGHT_REM = 14;
const above = ref(false);
const selected = computed(() =>
  props.options.find(
    option => !option.disabled && option.expression === props.expression
  )
);
const display = computed(() =>
  selected.value ? String(selected.value.value) : props.value
);
const query = ref('');
const options = computed(() =>
  props.options.filter(option =>
    `${option.label} ${option.value}`
      .toLowerCase()
      .includes(query.value.trim().toLowerCase())
  )
);
const close = () => {
  open.value = false;
  active.value = -1;
};
const focus = event => {
  emit('focus', event);
  query.value = selected.value ? '' : props.value;
};
const showMenu = event => {
  if (selected.value) return;
  const rect = event.target.getBoundingClientRect();
  const bubble = event.target
    .closest('[data-testid=editable-body]')
    ?.getBoundingClientRect();
  const rem = Number.parseFloat(
    getComputedStyle(document.documentElement).fontSize
  );
  const menuWidth = MENU_WIDTH_REM * rem;
  alignment.value = 'start';
  if (bubble && rect.left + menuWidth > bubble.right)
    alignment.value = rect.right - menuWidth >= bubble.left ? 'end' : 'center';
  const viewport = event.target
    .closest('[data-testid=chat-preview-scroll]')
    ?.getBoundingClientRect();
  above.value =
    viewport &&
    viewport.bottom - rect.bottom < MENU_HEIGHT_REM * rem &&
    rect.top - viewport.top > MENU_HEIGHT_REM * rem;
  open.value = true;
};
const update = event => {
  if (event.isComposing || event.target.composing) return;
  query.value = event.target.value;
  active.value = -1;
  showMenu(event);
  emit('change', event.target.value);
};
const choose = option => {
  if (!option.disabled) {
    emit('select', option.expression);
    close();
  }
};
const keydown = async event => {
  if (event.isComposing || event.target.composing || event.keyCode === 229)
    return;
  if (event.key === 'Escape' && open.value) {
    event.preventDefault();
    event.stopPropagation();
    close();
    return;
  }
  if (selected.value && ['ArrowDown', 'ArrowUp'].includes(event.key)) return;
  if (event.key === 'ArrowUp' && !open.value) return;
  if (['ArrowDown', 'ArrowUp'].includes(event.key)) {
    event.preventDefault();
    showMenu(event);
    const enabled = options.value
      .map((option, index) => (option.disabled ? -1 : index))
      .filter(index => index !== -1);
    const position = enabled.indexOf(active.value);
    active.value =
      event.key === 'ArrowDown'
        ? (enabled[(position + 1) % enabled.length] ?? -1)
        : (enabled[(position <= 0 ? enabled.length : position) - 1] ?? -1);
    await nextTick();
    document
      .getElementById(`${id}-option-${active.value}`)
      ?.scrollIntoView?.({ block: 'nearest' });
  }
  if (event.key === 'Enter') {
    event.preventDefault();
    if (open.value && active.value >= 0) choose(options.value[active.value]);
    else {
      close();
      emit('advance', event.target);
    }
  }
  if (event.key === 'Tab') close();
};
const clear = async () => {
  emit('change', '');
  await nextTick();
  input.value?.focus();
};
</script>

<template>
  <span
    class="relative inline-grid max-w-full grid-cols-[minmax(0,1fr)_auto] items-start gap-x-1 rounded-md border border-solid px-1 align-baseline whitespace-normal focus-within:ring-2 focus-within:ring-n-brand/30"
    :class="
      missing
        ? attempted
          ? 'border-n-ruby-8 bg-n-ruby-3'
          : 'border-n-amber-7 bg-n-amber-3'
        : 'border-n-weak bg-n-alpha-2'
    "
    @focusout="
      !$event.currentTarget.contains($event.relatedTarget) &&
        (close(), emit('leave'))
    "
  >
    <span
      aria-hidden="true"
      class="invisible col-start-1 row-start-1 min-w-[6ch] whitespace-pre-wrap break-all leading-5"
      >{{ display || placeholder }}{{ ' ' }}</span
    >
    <textarea
      ref="input"
      :value="display"
      rows="1"
      cols="1"
      data-template-field
      role="combobox"
      aria-autocomplete="list"
      aria-haspopup="listbox"
      :aria-label="label"
      :aria-expanded="open && !selected"
      :aria-controls="open && !selected ? `${id}-list` : undefined"
      :aria-activedescendant="
        open && active >= 0 ? `${id}-option-${active}` : undefined
      "
      :aria-invalid="missing && attempted"
      :placeholder="placeholder"
      :readonly="Boolean(selected)"
      :title="selected?.label"
      class="reset-base col-start-1 row-start-1 m-0 h-full min-h-0 w-full min-w-0 resize-none overflow-hidden whitespace-pre-wrap break-all border-0 bg-transparent p-0 [font-size:inherit] [font-family:inherit] [font-weight:inherit] [font-style:inherit] [text-decoration:inherit] leading-5 text-n-slate-12 focus:outline-none focus:ring-0"
      :class="
        missing
          ? attempted
            ? 'placeholder:text-n-ruby-11'
            : 'placeholder:text-n-amber-11'
          : 'placeholder:text-n-slate-10'
      "
      @focus="focus"
      @click="showMenu"
      @input="update"
      @compositionstart="$event.target.composing = true"
      @compositionend="
        $event.target.composing = false;
        update($event);
      "
      @keydown="keydown"
    />
    <button
      v-if="selected"
      type="button"
      :aria-label="t(`${prefix}.REMOVE_VARIABLE`, { variable: selected.label })"
      class="col-start-2 row-start-1 text-n-slate-11 hover:text-n-slate-12"
      @click="clear"
    >
      {{ CLOSE_MARK }}
    </button>
    <span
      v-if="open && !selected"
      class="absolute z-50 w-56 max-w-[calc(100vw-6rem)] rounded-lg border border-n-weak bg-n-solid-1 p-1 font-sans text-xs font-normal not-italic text-n-slate-12 shadow-lg"
      :class="[
        {
          'start-0': alignment === 'start',
          'end-0': alignment === 'end',
          'start-1/2 -translate-x-1/2': alignment === 'center',
        },
        above ? 'bottom-full mb-1' : 'top-full mt-1',
      ]"
      @mousedown.prevent
    >
      <span :id="`${id}-title`" class="block px-2 py-1.5 font-medium">{{
        t(`${prefix}.SYSTEM_VARIABLES`)
      }}</span>
      <span
        :id="`${id}-list`"
        role="listbox"
        :aria-labelledby="`${id}-title`"
        class="block max-h-40 overflow-y-auto overscroll-contain"
      >
        <span
          v-if="query"
          role="option"
          aria-selected="false"
          class="sticky top-0 block truncate rounded bg-n-solid-1 px-2 py-2 text-n-blue-11 cursor-pointer"
          @click="close"
          >{{ t(`${prefix}.USE_TEXT`, { text: query }) }}</span
        >
        <span
          v-for="(option, index) in options"
          :id="`${id}-option-${index}`"
          :key="option.id"
          role="option"
          :aria-selected="active === index"
          :aria-disabled="option.disabled"
          :title="option.disabled ? t(`${prefix}.NO_DATA`) : option.label"
          class="flex h-8 items-center justify-between gap-2 rounded px-2"
          :class="[
            option.disabled
              ? 'cursor-not-allowed text-n-slate-10'
              : 'cursor-pointer hover:bg-n-alpha-2',
            active === index ? 'bg-n-alpha-2' : '',
          ]"
          @click="choose(option)"
        >
          <span class="min-w-0 truncate">{{ option.label }}</span
          ><span class="max-w-[45%] truncate text-n-slate-11">{{
            option.value || t(`${prefix}.NO_DATA`)
          }}</span>
        </span>
        <span v-if="!options.length" class="block px-2 py-2 text-n-slate-11">{{
          t(
            status === 'error'
              ? 'VARIABLE_PICKER.ERROR'
              : status === 'loading'
                ? 'VARIABLE_PICKER.LOADING'
                : 'VARIABLE_PICKER.EMPTY'
          )
        }}</span>
      </span>
    </span>
  </span>
</template>
