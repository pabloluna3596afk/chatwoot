<script setup>
// The form as it looks in a phone, and usable: the answers are filled in, a block with a condition shows or hides with
// them and the button goes to the next screen. It reads the ChatHub definition itself (not Meta's Flow JSON), so the
// same view can render the form inside the CRM. The look follows WhatsApp's; Meta's own preview of a published form
// is the final word (the layout is slightly different on the real device).
import { computed, reactive, ref, watch } from 'vue';
import { FILE_TYPES, isVisible, OPTION_TYPES } from './flowDefinition';

const props = defineProps({
  definition: { type: Object, required: true },
});

const screenIndex = ref(0);
const done = ref(false);
const answers = reactive({});

const screens = computed(() => props.definition.screens || []);
const screen = computed(() => screens.value[screenIndex.value] || null);
const isLast = computed(() => screenIndex.value >= screens.value.length - 1);
const blocks = computed(() =>
  (screen.value?.blocks || []).filter(block => isVisible(block, answers))
);

// Editing can remove the screen the preview is on.
watch(
  () => screens.value.length,
  length => {
    if (screenIndex.value > length - 1)
      screenIndex.value = Math.max(0, length - 1);
  }
);

const toggle = (key, id) => {
  const list = Array.isArray(answers[key]) ? [...answers[key]] : [];
  const position = list.indexOf(id);
  if (position >= 0) list.splice(position, 1);
  else list.push(id);
  answers[key] = list;
};

const submit = () => {
  if (isLast.value) done.value = true;
  else screenIndex.value += 1;
};

const back = () => {
  if (done.value) done.value = false;
  else if (screenIndex.value > 0) screenIndex.value -= 1;
};

const restart = () => {
  Object.keys(answers).forEach(key => delete answers[key]);
  screenIndex.value = 0;
  done.value = false;
};

const answeredList = computed(() =>
  Object.entries(answers)
    .filter(
      ([, value]) => value !== '' && value !== false && value?.length !== 0
    )
    .map(
      ([key, value]) =>
        `${key}: ${Array.isArray(value) ? value.join(', ') : value}`
    )
);

const goTo = index => {
  done.value = false;
  screenIndex.value = index;
};

defineExpose({ goTo, restart, screenIndex });

const isFile = block => FILE_TYPES.includes(block.type);
const hasOptions = block => OPTION_TYPES.includes(block.type);
const inputType = block =>
  ({ email: 'email', phone: 'tel', number: 'number' })[block.input] || 'text';
</script>

<template>
  <div class="flex flex-col items-center gap-3" data-testid="flow-preview">
    <div
      class="w-[19rem] overflow-hidden text-slate-900 bg-white border-8 border-slate-800 rounded-[2rem] shadow-lg"
    >
      <div class="flex items-center gap-2 px-3 py-3 bg-slate-100">
        <button
          type="button"
          class="p-1 rounded-full hover:bg-slate-200"
          :class="{ invisible: !done && screenIndex === 0 }"
          data-testid="flow-preview-back"
          @click="back"
        >
          <span class="i-lucide-arrow-left size-4" />
        </button>
        <span class="flex-1 text-sm font-medium text-center truncate">
          {{ done ? $t('WHATSAPP_FLOWS.PREVIEW.DONE_TITLE') : screen?.title }}
        </span>
        <span class="i-lucide-x size-4 text-slate-500" />
      </div>

      <div class="h-[27rem] overflow-y-auto">
        <div
          v-if="done"
          class="flex flex-col items-center gap-3 p-6 text-center"
          data-testid="flow-preview-done"
        >
          <span class="i-lucide-circle-check size-10 text-[#00a884]" />
          <p class="text-sm font-medium">
            {{ $t('WHATSAPP_FLOWS.PREVIEW.DONE_BODY') }}
          </p>
          <ul class="w-full text-xs text-left break-words text-slate-600">
            <li v-for="line in answeredList" :key="line">{{ line }}</li>
          </ul>
          <button
            type="button"
            class="text-sm font-medium text-[#008069]"
            @click="restart"
          >
            {{ $t('WHATSAPP_FLOWS.PREVIEW.RESTART') }}
          </button>
        </div>

        <div v-else-if="screen" class="flex flex-col gap-3 p-4">
          <template v-for="(block, index) in blocks" :key="index">
            <h3
              v-if="block.type === 'heading'"
              class="text-lg font-semibold leading-snug"
            >
              {{ block.text }}
            </h3>
            <h4
              v-else-if="block.type === 'subheading'"
              class="text-base font-medium"
            >
              {{ block.text }}
            </h4>
            <p
              v-else-if="block.type === 'text'"
              class="text-sm whitespace-pre-wrap"
            >
              {{ block.text }}
            </p>
            <p
              v-else-if="block.type === 'caption'"
              class="text-xs text-slate-500"
            >
              {{ block.text }}
            </p>

            <label
              v-else-if="block.type === 'short_text'"
              class="flex flex-col gap-1 text-xs text-slate-500"
            >
              <span>
                {{ block.label }}<span v-if="block.required"> *</span>
              </span>
              <input
                v-model="answers[block.key]"
                :type="inputType(block)"
                class="px-3 py-2 text-sm bg-white border rounded-lg text-slate-900 border-slate-300"
              />
              <span v-if="block.helper">{{ block.helper }}</span>
            </label>

            <label
              v-else-if="block.type === 'long_text'"
              class="flex flex-col gap-1 text-xs text-slate-500"
            >
              <span>
                {{ block.label }}<span v-if="block.required"> *</span>
              </span>
              <textarea
                v-model="answers[block.key]"
                rows="3"
                class="px-3 py-2 text-sm bg-white border rounded-lg text-slate-900 border-slate-300"
              />
              <span v-if="block.helper">{{ block.helper }}</span>
            </label>

            <label
              v-else-if="block.type === 'date'"
              class="flex flex-col gap-1 text-xs text-slate-500"
            >
              <span>
                {{ block.label }}<span v-if="block.required"> *</span>
              </span>
              <input
                v-model="answers[block.key]"
                type="date"
                class="px-3 py-2 text-sm bg-white border rounded-lg text-slate-900 border-slate-300"
              />
            </label>

            <label
              v-else-if="block.type === 'dropdown'"
              class="flex flex-col gap-1 text-xs text-slate-500"
            >
              <span>
                {{ block.label }}<span v-if="block.required"> *</span>
              </span>
              <select
                v-model="answers[block.key]"
                class="px-3 py-2 text-sm bg-white border rounded-lg text-slate-900 border-slate-300"
              >
                <option value="" />
                <option
                  v-for="option in block.options"
                  :key="option.id"
                  :value="option.id"
                >
                  {{ option.title }}
                </option>
              </select>
            </label>

            <fieldset
              v-else-if="block.type === 'radio' || block.type === 'checkbox'"
              class="flex flex-col gap-2"
            >
              <legend class="mb-1 text-xs text-slate-500">
                {{ block.label }}<span v-if="block.required"> *</span>
              </legend>
              <label
                v-for="option in block.options"
                :key="option.id"
                class="flex items-center gap-2 text-sm"
              >
                <input
                  v-if="block.type === 'radio'"
                  v-model="answers[block.key]"
                  type="radio"
                  :name="`preview-${block.key}`"
                  :value="option.id"
                />
                <input
                  v-else
                  type="checkbox"
                  :checked="(answers[block.key] || []).includes(option.id)"
                  @change="toggle(block.key, option.id)"
                />
                {{ option.title }}
              </label>
            </fieldset>

            <label
              v-else-if="block.type === 'optin'"
              class="flex items-start gap-2 text-sm"
            >
              <input
                v-model="answers[block.key]"
                type="checkbox"
                class="mt-0.5"
              />
              {{ block.label }}
            </label>

            <div v-else-if="isFile(block)" class="flex flex-col gap-1">
              <span class="text-xs text-slate-500">
                {{ block.label }}<span v-if="block.required"> *</span>
              </span>
              <div
                class="flex items-center justify-center gap-2 px-3 py-4 text-sm border border-dashed rounded-lg text-slate-500 border-slate-300"
              >
                <span
                  :class="
                    block.type === 'photo'
                      ? 'i-lucide-image'
                      : 'i-lucide-file-text'
                  "
                  class="size-4"
                />
                {{
                  block.type === 'photo'
                    ? $t('WHATSAPP_FLOWS.PREVIEW.ADD_PHOTO')
                    : $t('WHATSAPP_FLOWS.PREVIEW.ADD_DOCUMENT')
                }}
              </div>
              <span v-if="block.helper" class="text-xs text-slate-500">
                {{ block.helper }}
              </span>
            </div>

            <span v-else-if="hasOptions(block)" />
          </template>
        </div>
      </div>

      <div v-if="!done && screen" class="p-3 border-t border-slate-100">
        <button
          type="button"
          class="w-full py-2.5 text-sm font-medium text-white rounded-full bg-[#00a884]"
          data-testid="flow-preview-footer"
          @click="submit"
        >
          {{ screen.button || $t('WHATSAPP_FLOWS.PREVIEW.DEFAULT_BUTTON') }}
        </button>
      </div>
    </div>

    <div
      v-if="screens.length > 1 && !done"
      class="flex items-center gap-1.5"
      data-testid="flow-preview-dots"
    >
      <button
        v-for="(item, index) in screens"
        :key="index"
        type="button"
        class="rounded-full size-2"
        :class="index === screenIndex ? 'bg-n-brand' : 'bg-n-slate-6'"
        :aria-label="item.title || String(index + 1)"
        @click="goTo(index)"
      />
    </div>
  </div>
</template>
