<script setup>
// The screen being edited, drawn in a phone. Blocks are compact (no card, no type header) and are edited by clicking
// them here: the selected one is outlined and its settings open in the right column of the builder.
import { computed, toRaw } from 'vue';
import { useI18n } from 'vue-i18n';

import { FILE_TYPES, OPTION_TYPES, TEXT_TYPES } from './flowDefinition';
import FlowPhoneFrame from './FlowPhoneFrame.vue';

const props = defineProps({
  definition: { type: Object, required: true },
  screenIndex: { type: Number, required: true },
  selected: { type: Number, default: null },
});

const emit = defineEmits(['select']);

const { t } = useI18n();

const screen = computed(() => props.definition.screens[props.screenIndex]);
const blocks = computed(() => screen.value?.blocks || []);
const buttonLabel = computed(() => screen.value?.button?.trim() || '');
const blockKeys = new WeakMap();
let blockKeyCount = 0;
const blockKey = item => {
  const raw = toRaw(item);
  if (!blockKeys.has(raw)) {
    blockKeyCount += 1;
    blockKeys.set(raw, blockKeyCount);
  }
  return blockKeys.get(raw);
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
  <div
    class="flex flex-col items-center w-full min-w-0 gap-2"
    data-testid="flow-canvas"
  >
    <FlowPhoneFrame
      :title="screen?.title || ''"
      :screen-index="screenIndex"
      :screen-count="definition.screens.length"
    >
      <div class="flex flex-col flex-1 gap-2 p-4">
        <div
          v-if="!blocks.length"
          class="flex flex-col items-center justify-center flex-1 gap-2 px-4 py-8 text-center"
          data-testid="flow-canvas-empty"
        >
          <span class="i-lucide-layout-template size-6 text-n-slate-10" />
          <p class="m-0 text-heading-3 text-n-slate-12">
            {{ $t('WHATSAPP_FLOWS.EDITOR.EMPTY_SCREEN_TITLE') }}
          </p>
          <p class="m-0 text-sm text-n-slate-11">
            {{ $t('WHATSAPP_FLOWS.EDITOR.EMPTY_SCREEN_HINT') }}
          </p>
        </div>

        <div
          v-for="(block, index) in blocks"
          :key="blockKey(block)"
          class="px-2 py-2 border-[1.5px] rounded-xl cursor-pointer"
          :class="
            selected === index
              ? 'border-n-brand'
              : 'border-transparent hover:border-n-weak'
          "
          role="button"
          tabindex="0"
          data-testid="flow-canvas-block"
          :data-selected="selected === index"
          @click="emit('select', index)"
          @keydown.enter.self="emit('select', index)"
          @keydown.space.self.prevent="emit('select', index)"
        >
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
        </div>

        <div
          class="mt-auto py-2.5 text-sm font-bold text-center rounded-full"
          :class="
            buttonLabel
              ? 'text-white bg-[#1f9d6a]'
              : 'text-n-ruby-11 bg-n-alpha-2'
          "
          data-testid="flow-canvas-footer"
        >
          {{ buttonLabel || $t('WHATSAPP_FLOWS.ERRORS.button_required') }}
        </div>
      </div>
    </FlowPhoneFrame>
    <p class="text-xs text-center text-n-slate-11">
      {{ $t('WHATSAPP_FLOWS.EDITOR.CANVAS_HINT') }}
    </p>
  </div>
</template>
