<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import RadioCard from 'dashboard/components-next/radioCard/RadioCard.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  collectAnswers,
  evaluateVisibility,
  validateAnswers,
} from 'shared/helpers/flowAnswers';
import { FILE_TYPES, TEXT_TYPES } from './flowDefinition';
import FlowPhoneFrame from './FlowPhoneFrame.vue';
import FlowPreviewResult from './FlowPreviewResult.vue';

const props = defineProps({
  definition: { type: Object, required: true },
  flowName: { type: String, required: true },
  attributes: { type: Array, default: () => [] },
});
const emit = defineEmits(['edit']);
const { t } = useI18n();
const screenIndex = ref(0);
const answers = ref({});
const errors = ref({});
const completed = ref(false);
const root = ref(null);
const screen = computed(() => props.definition.screens[screenIndex.value]);
const blocks = computed(() =>
  screen.value.blocks.filter(block => evaluateVisibility(block, answers.value))
);
const collected = computed(() =>
  collectAnswers(props.definition, answers.value)
);
const fieldId = block => `flow-preview-${block.key}`;
const message = block =>
  errors.value[block.key]
    ? t(`WHATSAPP_FLOWS.SIMULATOR.ERRORS.${errors.value[block.key]}`)
    : '';
const focusHeading = () =>
  nextTick(() => {
    const scroll = root.value.querySelector(
      '[data-testid="flow-phone-scroll"]'
    );
    scroll.scrollTop = 0;
    root.value
      .querySelector(
        '[data-testid="flow-preview-heading"], [data-testid="flow-result-heading"]'
      )
      ?.focus();
  });
const reset = () => {
  answers.value = {};
  errors.value = {};
  screenIndex.value = 0;
  completed.value = false;
  focusHeading();
};
const updateAnswer = (block, value) => {
  answers.value = collectAnswers(props.definition, {
    ...answers.value,
    [block.key]: value,
  });
  delete errors.value[block.key];
};
const toggleChoice = (block, id, checked) => {
  const selected = answers.value[block.key] || [];
  updateAnswer(
    block,
    checked ? [...selected, id] : selected.filter(value => value !== id)
  );
};
const addFile = block =>
  updateAnswer(block, [
    ...(answers.value[block.key] || []),
    {
      file_name: t('WHATSAPP_FLOWS.SIMULATOR.TEST_FILE'),
      mime_type: block.type === 'photo' ? 'image/png' : 'application/pdf',
      id: 'simulated',
    },
  ]);
const advance = () => {
  errors.value = validateAnswers(screen.value, collected.value);
  const invalid = Object.keys(errors.value)[0];
  if (invalid) {
    nextTick(() =>
      root.value
        .querySelector(
          `[data-field="${invalid}"] input, [data-field="${invalid}"] textarea, [data-field="${invalid}"] button`
        )
        ?.focus()
    );
    return;
  }
  if (screenIndex.value < props.definition.screens.length - 1)
    screenIndex.value += 1;
  else completed.value = true;
  focusHeading();
};
watch(() => props.definition, reset, { deep: true });
</script>

<template>
  <div
    ref="root"
    class="flex flex-col items-center gap-2"
    data-testid="flow-simulator"
  >
    <FlowPhoneFrame
      :title="screen.title"
      :screen-index="screenIndex"
      :screen-count="definition.screens.length"
    >
      <FlowPreviewResult
        v-if="completed"
        :flow-name="flowName"
        :definition="definition"
        :answers="collected"
        :attributes="attributes"
        @reset="reset"
        @edit="emit('edit')"
      />
      <form
        v-else
        class="flex flex-col flex-1 gap-4 p-4"
        novalidate
        @submit.prevent="advance"
      >
        <h3
          tabindex="-1"
          class="text-heading-3"
          data-testid="flow-preview-heading"
        >
          {{ screen.title }}
        </h3>
        <div
          v-for="(block, index) in blocks"
          :key="block.key || index"
          :data-field="block.key"
          :role="block.key ? 'group' : undefined"
          :aria-describedby="block.key ? `${fieldId(block)}-help` : undefined"
          :aria-invalid="block.key ? !!message(block) : undefined"
        >
          <p
            v-if="TEXT_TYPES.includes(block.type)"
            :class="{
              'text-base font-bold': block.type === 'heading',
              'text-sm font-semibold': block.type === 'subheading',
              'text-sm': block.type === 'text',
              'text-xs text-n-slate-11': block.type === 'caption',
            }"
            class="whitespace-pre-wrap break-words"
          >
            {{ block.text }}
          </p>
          <Input
            v-else-if="['short_text', 'date'].includes(block.type)"
            :id="fieldId(block)"
            :model-value="answers[block.key] ?? ''"
            :type="
              block.type === 'date'
                ? 'date'
                : block.input === 'phone'
                  ? 'tel'
                  : block.input || 'text'
            "
            :label="`${block.label}${block.required ? ' *' : ''}`"
            :message="message(block) || block.helper"
            :message-type="message(block) ? 'error' : 'info'"
            :aria-invalid="!!message(block)"
            :aria-required="block.required"
            :aria-describedby="`${fieldId(block)}-help`"
            @update:model-value="updateAnswer(block, $event)"
          />
          <TextArea
            v-else-if="block.type === 'long_text'"
            :id="fieldId(block)"
            :model-value="answers[block.key] || ''"
            :label="`${block.label}${block.required ? ' *' : ''}`"
            :max-length="-1"
            :message="message(block) || block.helper"
            :message-type="message(block) ? 'error' : 'info'"
            :aria-invalid="!!message(block)"
            :aria-required="block.required"
            @update:model-value="updateAnswer(block, $event)"
          />
          <div v-else-if="block.type === 'dropdown'">
            <p :id="fieldId(block)" class="mb-1.5 text-heading-3">
              {{ block.label }}<span v-if="block.required"> *</span>
            </p>
            <ComboBox
              :model-value="answers[block.key] || ''"
              :options="
                block.options.map(option => ({
                  value: option.id,
                  label: option.title,
                }))
              "
              :aria-label="block.label"
              :message="message(block) || block.helper"
              :has-error="!!message(block)"
              @update:model-value="updateAnswer(block, $event)"
            />
          </div>
          <fieldset
            v-else-if="['radio', 'checkbox', 'optin'].includes(block.type)"
            class="min-w-0"
            :aria-describedby="`${fieldId(block)}-help`"
          >
            <legend class="mb-1.5 text-heading-3">
              {{ block.label }}<span v-if="block.required"> *</span>
            </legend>
            <div v-if="block.type === 'radio'" class="grid gap-2">
              <RadioCard
                v-for="option in block.options"
                :id="`${fieldId(block)}-${option.id}`"
                :key="option.id"
                :name="fieldId(block)"
                :label="option.title"
                description=""
                :is-active="answers[block.key] === option.id"
                class="!p-2 [&_h3]:font-normal [&_p:empty]:hidden"
                @select="updateAnswer(block, option.id)"
              />
            </div>
            <div v-else-if="block.type === 'checkbox'" class="grid gap-2">
              <label
                v-for="option in block.options"
                :key="option.id"
                class="flex items-center gap-2 text-sm"
              >
                <Checkbox
                  :model-value="(answers[block.key] || []).includes(option.id)"
                  :aria-label="option.title"
                  @update:model-value="toggleChoice(block, option.id, $event)"
                />{{ option.title }}
              </label>
            </div>
            <label v-else class="flex items-center gap-2 text-sm">
              <Checkbox
                :model-value="answers[block.key] || false"
                :aria-label="block.label"
                @update:model-value="updateAnswer(block, $event)"
              />
              <span>{{ $t('WHATSAPP_FLOWS.SIMULATOR.ACCEPT') }}</span>
            </label>
            <p
              class="mt-1 text-xs"
              :class="message(block) ? 'text-n-ruby-9' : 'text-n-slate-11'"
              aria-live="polite"
            >
              {{ message(block) || block.helper }}
            </p>
          </fieldset>
          <div v-else-if="FILE_TYPES.includes(block.type)">
            <p class="mb-1.5 text-heading-3">
              {{ block.label }}<span v-if="block.required"> *</span>
            </p>
            <Button
              type="button"
              size="sm"
              variant="faded"
              color="slate"
              :label="$t('WHATSAPP_FLOWS.SIMULATOR.ADD_TEST_FILE')"
              :icon="
                block.type === 'photo' ? 'i-lucide-image' : 'i-lucide-file-text'
              "
              :disabled="
                (answers[block.key] || []).length >= (block.max_files || 1)
              "
              @click="addFile(block)"
            />
            <div
              v-for="(file, fileIndex) in answers[block.key]"
              :key="fileIndex"
              class="flex items-center gap-1 mt-2 p-2 text-xs rounded bg-n-alpha-2"
            >
              <span>{{ file.file_name }}</span
              ><Button
                type="button"
                size="sm"
                variant="ghost"
                color="slate"
                icon="i-lucide-x"
                :aria-label="$t('WHATSAPP_FLOWS.SIMULATOR.REMOVE_FILE')"
                @click="
                  updateAnswer(
                    block,
                    answers[block.key].filter((_, i) => i !== fileIndex)
                  )
                "
              />
            </div>
            <p
              class="mt-1 text-xs"
              :class="message(block) ? 'text-n-ruby-9' : 'text-n-slate-11'"
              aria-live="polite"
            >
              {{ message(block) || block.helper }}
            </p>
          </div>
          <span
            v-if="block.key"
            :id="`${fieldId(block)}-help`"
            class="sr-only"
            aria-live="polite"
            >{{ message(block) || block.helper }}</span
          >
        </div>
        <Button
          type="submit"
          color="teal"
          class="w-full mt-auto shrink-0"
          :label="
            screen.button ||
            $t(
              screenIndex === definition.screens.length - 1
                ? 'WHATSAPP_FLOWS.EDITOR.BUTTON_LAST'
                : 'WHATSAPP_FLOWS.EDITOR.BUTTON_NEXT'
            )
          "
          data-testid="flow-preview-next"
        />
      </form>
    </FlowPhoneFrame>
    <p class="text-xs text-center text-n-slate-11">
      {{ $t('WHATSAPP_FLOWS.SIMULATOR.NOTE') }}
    </p>
    <Button
      variant="ghost"
      color="slate"
      size="sm"
      :label="$t('WHATSAPP_FLOWS.SIMULATOR.RESET')"
      data-testid="flow-preview-reset"
      @click="reset"
    />
  </div>
</template>
