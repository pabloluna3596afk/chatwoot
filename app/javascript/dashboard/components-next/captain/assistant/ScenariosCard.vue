<script setup>
import { computed, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useToggle, useElementSize } from '@vueuse/core';
import { useVuelidate } from '@vuelidate/core';
import { required, minLength } from '@vuelidate/validators';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Editor from 'dashboard/components-next/Editor/Editor.vue';
import CardLayout from 'dashboard/components-next/CardLayout.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Policy from 'dashboard/components/policy.vue';

const props = defineProps({
  // Return true only after the mutation succeeds; events cannot be awaited.
  onUpdate: { type: Function, required: true },
  id: {
    type: Number,
    required: true,
  },
  title: {
    type: String,
    required: true,
  },
  description: {
    type: String,
    required: true,
  },
  instruction: {
    type: String,
    required: true,
  },
  tools: {
    type: Array,
    default: () => [],
  },
  enabled: {
    type: Boolean,
    default: true,
  },
  isUpdating: {
    type: Boolean,
    default: false,
  },
  selectable: {
    type: Boolean,
    default: false,
  },
  isSelected: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['select', 'hover', 'delete', 'toggle']);

const { t } = useI18n();
const { formatMessage } = useMessageFormatter();

const modelValue = computed({
  get: () => props.isSelected,
  set: () => emit('select', props.id),
});

const enabledState = computed({
  get: () => props.enabled,
  set: enabled => emit('toggle', { id: props.id, enabled }),
});

const statusLabel = computed(() =>
  props.enabled
    ? t('CAPTAIN.ASSISTANTS.SCENARIOS.STATUS.ENABLED')
    : t('CAPTAIN.ASSISTANTS.SCENARIOS.STATUS.DISABLED')
);

const state = reactive({
  id: '',
  title: '',
  description: '',
  instruction: '',
});

const instructionContentRef = ref();

const [isEditing, toggleEditing] = useToggle();
const [isInstructionExpanded, toggleInstructionExpanded] = useToggle();

const { height: contentHeight } = useElementSize(instructionContentRef);
const needsOverlay = computed(() => contentHeight.value > 160);

const startEdit = () => {
  Object.assign(state, {
    id: props.id,
    title: props.title,
    description: props.description,
    instruction: props.instruction,
    tools: props.tools,
  });
  toggleEditing(true);
};

const rules = {
  title: { required, minLength: minLength(1) },
  description: { required },
  instruction: { required },
};

const v$ = useVuelidate(rules, state);

const titleError = computed(() =>
  v$.value.title.$error
    ? t('CAPTAIN.ASSISTANTS.SCENARIOS.ADD.NEW.FORM.TITLE.ERROR')
    : ''
);

const descriptionError = computed(() =>
  v$.value.description.$error
    ? t('CAPTAIN.ASSISTANTS.SCENARIOS.ADD.NEW.FORM.DESCRIPTION.ERROR')
    : ''
);

const isSaving = ref(false);

const onClickUpdate = async () => {
  v$.value.$touch();
  if (v$.value.$invalid) return;
  if (isSaving.value) return;
  isSaving.value = true;
  try {
    if (await props.onUpdate({ ...state })) toggleEditing(false);
  } finally {
    isSaving.value = false;
  }
};

const instructionError = computed(() =>
  v$.value.instruction.$error
    ? t('CAPTAIN.ASSISTANTS.SCENARIOS.ADD.NEW.FORM.INSTRUCTION.ERROR')
    : ''
);

const onEscapeEdit = event => {
  if (!isEditing.value) return;
  event.preventDefault();
  event.stopPropagation();
  toggleEditing(false);
};

const LINK_INSTRUCTION_CLASS =
  '[&_a[href^="tool://"]]:text-n-iris-11 [&_a:not([href^="tool://"])]:text-n-slate-12 [&_a]:pointer-events-none [&_a]:cursor-default';
</script>

<template>
  <CardLayout
    selectable
    class="group relative [&>div]:!py-4"
    :class="{
      '[&>div]:ltr:!pr-4 [&>div]:rtl:!pl-4': !isEditing,
      '[&>div]:ltr:!pr-10 [&>div]:rtl:!pl-10': isEditing,
    }"
    layout="row"
    @keydown.esc="onEscapeEdit"
    @mouseenter="emit('hover', true)"
    @mouseleave="emit('hover', false)"
  >
    <div
      v-show="!isEditing"
      class="absolute top-[1.125rem] ltr:left-3 rtl:right-3 z-10 transition-opacity"
      :class="{
        'opacity-0 group-hover:opacity-100 group-focus-within:opacity-100 max-sm:opacity-100':
          !isSelected && !selectable,
        'opacity-100': selectable || isSelected,
      }"
    >
      <Checkbox
        v-model="modelValue"
        :aria-label="
          t('CAPTAIN.ASSISTANTS.SCENARIOS.SELECT_SCENARIO', { title })
        "
      />
    </div>

    <div v-if="!isEditing" class="flex flex-col w-full">
      <div class="flex items-start justify-between w-full gap-2">
        <div class="flex flex-col items-start">
          <span class="text-sm text-n-slate-12 font-medium">{{ title }}</span>
          <span class="text-sm text-n-slate-11 mt-2">
            {{ description }}
          </span>
        </div>
        <div class="flex items-center gap-2">
          <span class="text-xs text-n-slate-11">
            {{ statusLabel }}
          </span>
          <Policy
            as="span"
            :permissions="['administrator']"
            class="inline-flex items-center"
          >
            <Switch
              v-model="enabledState"
              :disabled="isUpdating"
              :aria-label="
                t('CAPTAIN.ASSISTANTS.SCENARIOS.STATUS.TOGGLE', { title })
              "
              :class="{ 'opacity-50 cursor-not-allowed': isUpdating }"
            />
          </Policy>
          <span class="w-px h-4 bg-n-weak" />
          <!-- <Button label="Test" slate xs ghost class="!text-sm" />
          <span class="w-px h-4 bg-n-weak" /> -->
          <Button
            icon="i-lucide-pen"
            :aria-label="
              t('CAPTAIN.ASSISTANTS.SCENARIOS.EDIT_SCENARIO', { title })
            "
            slate
            xs
            ghost
            @click="startEdit"
          />
          <span class="w-px h-4 bg-n-weak" />
          <Button
            icon="i-lucide-trash"
            :aria-label="
              t('CAPTAIN.ASSISTANTS.SCENARIOS.DELETE_SCENARIO', { title })
            "
            slate
            xs
            ghost
            @click="emit('delete', id)"
          />
        </div>
      </div>

      <div
        class="relative overflow-hidden transition-all duration-300 ease-in-out group/expandable"
        :class="{ 'cursor-pointer': needsOverlay }"
        :style="{
          maxHeight: isInstructionExpanded ? `${contentHeight}px` : '10rem',
        }"
        @click="needsOverlay ? toggleInstructionExpanded() : null"
      >
        <div :id="`scenario-instruction-${id}`" ref="instructionContentRef">
          <p
            v-dompurify-html:toolLinks="formatMessage(instruction, false)"
            class="text-sm text-n-slate-12 py-4 mb-0 prose prose-sm min-w-0 break-words max-w-none"
            :class="LINK_INSTRUCTION_CLASS"
          />
        </div>

        <div
          class="absolute bottom-0 w-full flex items-end justify-center text-xs text-n-slate-11 bg-gradient-to-t h-40 from-n-solid-2 via-n-solid-2 via-10% to-transparent transition-all duration-500 ease-in-out px-2 py-1 rounded pointer-events-none"
          :class="{
            'visible opacity-100': !isInstructionExpanded,
            'invisible opacity-0': isInstructionExpanded || !needsOverlay,
          }"
        >
          <Icon
            icon="i-lucide-chevron-down"
            class="text-n-slate-7 mb-4 size-4 group-hover/expandable:text-n-slate-11 transition-colors duration-200"
          />
        </div>
        <Button
          v-if="needsOverlay"
          :label="
            t(
              isInstructionExpanded
                ? 'CAPTAIN.ASSISTANTS.SCENARIOS.SHOW_LESS'
                : 'CAPTAIN.ASSISTANTS.SCENARIOS.SHOW_MORE'
            )
          "
          :aria-expanded="isInstructionExpanded"
          :aria-controls="`scenario-instruction-${id}`"
          type="button"
          class="absolute bottom-2 start-1/2 z-10 -translate-x-1/2"
          ghost
          xs
          slate
          @click.stop="toggleInstructionExpanded()"
        />
      </div>
      <span
        v-if="tools?.length"
        class="text-sm text-n-slate-11 font-medium mb-1"
      >
        {{ t('CAPTAIN.ASSISTANTS.SCENARIOS.ADD.SUGGESTED.TOOLS_USED') }}
        {{ tools?.map(tool => `@${tool}`).join(', ') }}
      </span>
    </div>
    <div v-else class="overflow-hidden flex flex-col gap-4 w-full">
      <Input
        v-model="state.title"
        :disabled="isSaving"
        :label="t('CAPTAIN.ASSISTANTS.SCENARIOS.ADD.NEW.FORM.TITLE.LABEL')"
        :placeholder="
          t('CAPTAIN.ASSISTANTS.SCENARIOS.ADD.NEW.FORM.TITLE.PLACEHOLDER')
        "
        :message="titleError"
        :message-type="titleError ? 'error' : 'info'"
      />

      <TextArea
        v-model="state.description"
        :disabled="isSaving"
        :max-length="500"
        :label="
          t('CAPTAIN.ASSISTANTS.SCENARIOS.ADD.NEW.FORM.DESCRIPTION.LABEL')
        "
        :placeholder="
          t('CAPTAIN.ASSISTANTS.SCENARIOS.ADD.NEW.FORM.DESCRIPTION.PLACEHOLDER')
        "
        :message="descriptionError"
        :message-type="descriptionError ? 'error' : 'info'"
        show-character-count
      />
      <Editor
        v-model="state.instruction"
        :disabled="isSaving"
        :label="
          t('CAPTAIN.ASSISTANTS.SCENARIOS.ADD.NEW.FORM.INSTRUCTION.LABEL')
        "
        :placeholder="
          t('CAPTAIN.ASSISTANTS.SCENARIOS.ADD.NEW.FORM.INSTRUCTION.PLACEHOLDER')
        "
        :message="instructionError"
        :message-type="instructionError ? 'error' : 'info'"
        :show-character-count="false"
        enable-captain-tools
      />
      <div class="flex items-center gap-3">
        <Button
          faded
          slate
          sm
          :label="t('CAPTAIN.ASSISTANTS.SCENARIOS.UPDATE.CANCEL')"
          :disabled="isSaving"
          @click="toggleEditing(false)"
        />
        <Button
          sm
          :label="t('CAPTAIN.ASSISTANTS.SCENARIOS.UPDATE.UPDATE')"
          :is-loading="isSaving"
          :disabled="isSaving"
          @click="onClickUpdate"
        />
      </div>
    </div>
  </CardLayout>
</template>
