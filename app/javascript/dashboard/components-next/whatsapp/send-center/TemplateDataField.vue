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
const title = computed(() => selected.value?.label || props.label);
const display = computed(() => {
  if (selected.value) return String(selected.value.value);
  // The parser keeps Liquid defaults while the server resolves the context.
  // Show the placeholder during that interval, never the expression itself.
  return props.expression.includes('{{') && props.value === props.expression
    ? ''
    : props.value;
});
const pending = computed(() => props.missing || !display.value.trim());
const query = ref('');
const options = computed(() => [
  ...(query.value.trim()
    ? [
        {
          id: 'text',
          kind: 'text',
          value: t('WHATSAPP_TEMPLATES.SEND_CENTER.USE_TEXT', {
            text: query.value,
          }),
        },
      ]
    : []),
  ...props.options.filter(option =>
    `${option.label} ${option.value}`
      .toLowerCase()
      .includes(query.value.trim().toLowerCase())
  ),
  ...(selected.value
    ? [
        {
          id: 'remove',
          kind: 'remove',
          value: t('WHATSAPP_TEMPLATES.SEND_CENTER.REMOVE_VALUE'),
        },
      ]
    : []),
]);
const close = () => {
  open.value = false;
  active.value = -1;
};
const focus = event => {
  emit('focus', event);
  query.value = '';
};
const showMenu = () => {
  if (open.value) return;
  const rect = input.value.parentElement.getBoundingClientRect();
  const bubble = input.value
    .closest('[data-testid=editable-body]')
    ?.getBoundingClientRect();
  const rem = Number.parseFloat(
    getComputedStyle(document.documentElement).fontSize
  );
  const menuWidth = MENU_WIDTH_REM * rem;
  alignment.value = 'start';
  if (bubble && rect.left + menuWidth > bubble.right)
    alignment.value = rect.right - menuWidth >= bubble.left ? 'end' : 'center';
  const viewport = input.value
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
const choose = async option => {
  if (!option.disabled) {
    if (option.kind === 'text') emit('change', query.value);
    else if (option.kind === 'remove') emit('change', '');
    else emit('select', option.expression);
    close();
    await nextTick();
    input.value?.focus({ preventScroll: true });
  }
};
const keydown = async event => {
  if (event.isComposing || event.target.composing || event.keyCode === 229)
    return;
  if (event.key === 'Escape' && open.value) {
    event.preventDefault();
    event.stopPropagation();
    close();
    await nextTick();
    input.value?.focus({ preventScroll: true });
    return;
  }
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
    else if (event.target.type === 'search' && query.value.trim())
      choose(options.value[0]);
    else {
      close();
      emit('advance', input.value);
    }
  }
  if (event.key === 'Tab' && event.target.type !== 'search') close();
};
</script>

<template>
  <span
    class="relative inline-grid grid-cols-[minmax(0,1fr)] w-max max-w-full items-start rounded-md border border-solid px-1 align-baseline whitespace-normal"
    :class="[
      pending
        ? attempted
          ? 'border-n-ruby-9 bg-n-ruby-3 ring-1 ring-n-ruby-9'
          : 'border-n-ruby-7 bg-n-ruby-3 hover:border-n-ruby-8 focus-within:border-n-ruby-9'
        : 'border-n-brand/30 bg-n-brand/10 hover:border-n-brand/50 focus-within:border-n-brand/60',
    ]"
    @focusout="
      !$event.currentTarget.contains($event.relatedTarget) &&
        (close(), emit('leave'))
    "
  >
    <span
      aria-hidden="true"
      class="invisible col-start-1 row-start-1 whitespace-pre-wrap [overflow-wrap:anywhere] leading-5"
    >
      {{ display || placeholder }}{{ ' ' }}
    </span>
    <textarea
      ref="input"
      :value="display"
      rows="1"
      cols="1"
      spellcheck="false"
      autocomplete="off"
      data-template-field
      role="combobox"
      aria-autocomplete="list"
      aria-haspopup="listbox"
      :aria-label="label"
      :aria-expanded="open"
      :aria-controls="open ? `${id}-list` : undefined"
      :aria-activedescendant="
        open && active >= 0 ? `${id}-option-${active}` : undefined
      "
      :aria-invalid="pending && attempted"
      :placeholder="placeholder"
      :title="title"
      class="reset-base col-start-1 row-start-1 !m-0 !h-full !min-h-0 w-full min-w-0 resize-none overflow-hidden whitespace-pre-wrap [overflow-wrap:anywhere] !appearance-none !rounded-none !border-0 !bg-transparent !p-0 !shadow-none ![outline:none] [font-size:inherit] [font-family:inherit] [font-weight:inherit] [font-style:inherit] [text-decoration:inherit] leading-5 text-n-slate-12"
      :class="
        pending ? 'placeholder:!text-n-ruby-11' : 'placeholder:text-n-slate-10'
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
    <span
      v-if="open"
      class="absolute z-50 w-56 max-w-[calc(100vw-6rem)] rounded-lg border border-n-weak bg-n-alpha-3 p-2 backdrop-blur-[100px] font-sans text-sm font-normal not-italic text-n-slate-12 shadow-lg"
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
      <input
        v-model="query"
        type="search"
        :aria-label="t('WHATSAPP_TEMPLATES.SEND_CENTER.SEARCH_OR_TYPE')"
        :placeholder="t('WHATSAPP_TEMPLATES.SEND_CENTER.SEARCH_OR_TYPE')"
        class="!m-0 !mb-2 !h-8 !rounded-md !border-n-weak !bg-n-alpha-2 !px-2 !py-1 !text-sm !text-n-slate-12 placeholder:!text-n-slate-10 focus:!border-n-brand focus:!ring-n-brand/30"
        @mousedown.stop
        @input="active = -1"
        @keydown="keydown"
      />
      <span
        :id="`${id}-list`"
        role="listbox"
        :aria-label="label"
        class="block max-h-40 overflow-y-auto overscroll-contain"
      >
        <span
          v-for="(option, index) in options"
          :id="`${id}-option-${index}`"
          :key="option.id"
          role="option"
          :aria-selected="active === index"
          :aria-disabled="option.disabled"
          :title="
            option.disabled
              ? t('WHATSAPP_TEMPLATES.SEND_CENTER.NO_DATA')
              : String(option.value)
          "
          class="block min-h-8 rounded px-2 py-2 whitespace-normal [overflow-wrap:anywhere]"
          :class="[
            option.disabled
              ? 'cursor-not-allowed text-n-slate-10'
              : 'cursor-pointer hover:bg-n-alpha-2',
            active === index ? 'bg-n-alpha-2' : '',
          ]"
          @click="choose(option)"
        >
          {{
            option.disabled
              ? t('WHATSAPP_TEMPLATES.SEND_CENTER.NO_DATA')
              : option.value
          }}
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
