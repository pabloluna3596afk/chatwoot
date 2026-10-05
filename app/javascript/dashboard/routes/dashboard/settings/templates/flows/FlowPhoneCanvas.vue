<script setup>
// The screen being edited, drawn in a phone. Blocks are compact (no card, no type header) and are edited by clicking
// them here: the selected one is outlined and its settings open in the right column of the builder.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import { FILE_TYPES, OPTION_TYPES, TEXT_TYPES } from './flowDefinition';

const props = defineProps({
  definition: { type: Object, required: true },
  screenIndex: { type: Number, required: true },
  selected: { type: Number, default: null },
});

const emit = defineEmits(['select', 'remove', 'move']);

const { t } = useI18n();

const screen = computed(() => props.definition.screens[props.screenIndex]);
const blocks = computed(() => screen.value?.blocks || []);
const isLast = computed(
  () => props.screenIndex >= props.definition.screens.length - 1
);

const answers = computed(() =>
  props.definition.screens.flatMap(item =>
    (item.blocks || []).filter(block => block.key)
  )
);
const optionTitle = (key, id) => {
  const block = answers.value.find(item => item.key === key);
  return block?.options?.find(option => option.id === id)?.title || id;
};
const questionOf = key =>
  answers.value.find(item => item.key === key)?.label || key;

const conditionText = block => {
  const condition = block.visible_when;
  if (!condition?.key) return '';
  return t('WHATSAPP_FLOWS.EDITOR.ONLY_IF', {
    question: questionOf(condition.key),
    op: condition.op === 'not_equals' ? '≠' : '=',
    value: optionTitle(condition.key, condition.value),
  });
};

const placeholder = block =>
  ({
    dropdown: t('WHATSAPP_FLOWS.PREVIEW.PICK_ONE'),
    date: 'dd / mm / aaaa',
    long_text: '…',
  })[block.type] || '';
const isText = block => TEXT_TYPES.includes(block.type);
const hasOptions = block =>
  OPTION_TYPES.includes(block.type) && block.type !== 'dropdown';
const isFile = block => FILE_TYPES.includes(block.type);
</script>

<template>
  <div class="flex flex-col items-center gap-2" data-testid="flow-canvas">
    <div
      class="w-full max-w-[21rem] overflow-hidden border-8 border-slate-800 rounded-[2rem] bg-[#e8dfd2] dark:bg-[#1b2630]"
    >
      <div
        class="flex justify-between px-4 py-2.5 text-sm font-semibold text-white bg-[#1f9d6a]"
      >
        <span class="truncate">{{ screen?.title }}</span>
        <span>{{ screenIndex + 1 }} / {{ definition.screens.length }}</span>
      </div>
      <div
        class="flex flex-col gap-2 p-4 mt-8 min-h-[25rem] rounded-t-[1.1rem] bg-n-solid-1 text-n-slate-12"
      >
        <h3 class="m-0 text-base font-semibold">{{ screen?.title }}</h3>

        <div
          v-for="(block, index) in blocks"
          :key="index"
          class="relative px-2 py-2 border-[1.5px] rounded-xl cursor-pointer group"
          :class="
            selected === index
              ? 'border-n-brand bg-n-brand/10'
              : 'border-transparent hover:border-n-weak'
          "
          role="button"
          tabindex="0"
          data-testid="flow-canvas-block"
          :data-selected="selected === index"
          @click="emit('select', index)"
          @keydown.enter.self="emit('select', index)"
        >
          <span
            v-if="block.visible_when"
            class="inline-block px-2 mb-1 text-[11px] rounded-full bg-n-amber-3 text-n-amber-11"
            data-testid="flow-canvas-cond"
          >
            {{ conditionText(block) }}
          </span>

          <p
            v-if="block.type === 'heading'"
            class="m-0 text-base font-bold break-words"
          >
            {{ block.text || '…' }}
          </p>
          <p
            v-else-if="block.type === 'subheading'"
            class="m-0 text-sm font-semibold break-words"
          >
            {{ block.text || '…' }}
          </p>
          <p
            v-else-if="block.type === 'text'"
            class="m-0 text-sm break-words whitespace-pre-wrap"
          >
            {{ block.text || '…' }}
          </p>
          <p
            v-else-if="block.type === 'caption'"
            class="m-0 text-xs break-words text-n-slate-11"
          >
            {{ block.text || '…' }}
          </p>

          <div
            v-else-if="block.type === 'optin'"
            class="flex items-center gap-2 text-sm text-n-slate-11"
          >
            <span class="border-[1.5px] rounded size-3.5 border-n-slate-10" />
            {{ block.label }}<span v-if="block.required"> *</span>
          </div>

          <template v-else-if="!isText(block)">
            <span class="block mb-1 text-xs text-n-slate-11">
              {{ block.label }}<span v-if="block.required"> *</span>
            </span>
            <template v-if="hasOptions(block)">
              <div
                v-for="option in block.options"
                :key="option.id"
                class="flex items-center gap-2 py-0.5 text-sm text-n-slate-11"
              >
                <span
                  class="border-[1.5px] size-3.5 border-n-slate-10"
                  :class="
                    block.type === 'checkbox' ? 'rounded' : 'rounded-full'
                  "
                />
                {{ option.title }}
              </div>
            </template>
            <div
              v-else
              class="flex items-center gap-1.5 px-3 py-2 min-h-9 text-sm border rounded-[10px] border-n-weak bg-n-solid-2 text-n-slate-10"
            >
              <span
                v-if="isFile(block)"
                :class="
                  block.type === 'photo'
                    ? 'i-lucide-image'
                    : 'i-lucide-file-text'
                "
                class="size-4"
              />
              {{ placeholder(block) }}
            </div>
          </template>

          <div
            v-if="selected === index"
            class="absolute flex items-center gap-0.5 px-1 border rounded-md end-2 -top-3 bg-n-solid-1 border-n-weak"
          >
            <button
              type="button"
              class="p-0.5 rounded text-n-slate-11 hover:bg-n-alpha-2 disabled:opacity-30"
              :disabled="index === 0"
              :aria-label="$t('WHATSAPP_FLOWS.EDITOR.MOVE_UP')"
              data-testid="flow-canvas-up"
              @click.stop="emit('move', index, -1)"
            >
              <span class="i-lucide-arrow-up size-3.5" />
            </button>
            <button
              type="button"
              class="p-0.5 rounded text-n-slate-11 hover:bg-n-alpha-2 disabled:opacity-30"
              :disabled="index === blocks.length - 1"
              :aria-label="$t('WHATSAPP_FLOWS.EDITOR.MOVE_DOWN')"
              data-testid="flow-canvas-down"
              @click.stop="emit('move', index, 1)"
            >
              <span class="i-lucide-arrow-down size-3.5" />
            </button>
            <button
              type="button"
              class="p-0.5 rounded text-n-slate-11 hover:bg-n-alpha-2"
              :aria-label="$t('WHATSAPP_FLOWS.EDITOR.REMOVE_BLOCK')"
              data-testid="flow-canvas-remove"
              @click.stop="emit('remove', index)"
            >
              <span class="i-lucide-x size-3.5" />
            </button>
          </div>
        </div>

        <slot />

        <div
          class="mt-auto py-2.5 text-sm font-bold text-center text-white rounded-full bg-[#1f9d6a]"
        >
          {{
            screen?.button ||
            (isLast
              ? $t('WHATSAPP_FLOWS.EDITOR.BUTTON_LAST')
              : $t('WHATSAPP_FLOWS.EDITOR.BUTTON_NEXT'))
          }}
        </div>
      </div>
    </div>
    <p class="text-xs text-center text-n-slate-11">
      {{ $t('WHATSAPP_FLOWS.EDITOR.CANVAS_HINT') }}
    </p>
  </div>
</template>
