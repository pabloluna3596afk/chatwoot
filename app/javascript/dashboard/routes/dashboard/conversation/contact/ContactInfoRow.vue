<script setup>
import { ref, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import EmojiOrIcon from 'shared/components/EmojiOrIcon.vue';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import NextButton from 'dashboard/components-next/button/Button.vue';
import InlineInput from 'dashboard/components-next/inline-input/InlineInput.vue';

const props = defineProps({
  href: {
    type: String,
    default: '',
  },
  icon: {
    type: String,
    required: true,
  },
  emoji: {
    type: String,
    required: true,
  },
  // Phosphor/UnoCSS class (e.g. i-ph-identification-card) — preferred when set
  iconClass: {
    type: String,
    default: '',
  },
  value: {
    type: String,
    default: '',
  },
  showCopy: {
    type: Boolean,
    default: false,
  },
  editable: {
    type: Boolean,
    default: false,
  },
  title: {
    type: String,
    default: '',
  },
});
const emit = defineEmits(['update']);
const { t } = useI18n();
const isEditing = ref(false);
const editValue = ref('');
const editInput = ref(null);
const onCopy = async event => {
  event.preventDefault();
  await copyTextToClipboard(props.value);
  useAlert(t('CONTACT_PANEL.COPY_SUCCESSFUL'));
};
const startEditing = () => {
  if (!props.editable) return;
  editValue.value = props.value || '';
  isEditing.value = true;
  nextTick(() => editInput.value?.focus());
};
const saveEdit = () => {
  if (!isEditing.value) return;
  isEditing.value = false;
  const trimmed = editValue.value.trim();
  if (trimmed !== (props.value || '')) emit('update', trimmed);
};
const cancelEdit = () => {
  isEditing.value = false;
};
</script>

<template>
  <div class="group/row w-full h-10 px-3">
    <!-- Inline edit mode -->
    <div v-if="isEditing" class="flex h-full w-full min-w-0 items-center gap-2">
      <span
        v-if="iconClass"
        class="flex-shrink-0 size-3.5 text-n-slate-10"
        :class="iconClass"
      />
      <EmojiOrIcon
        v-else
        :icon="icon"
        :emoji="emoji"
        icon-size="14"
        class="flex-shrink-0"
      />
      <InlineInput
        ref="editInput"
        v-model="editValue"
        :placeholder="title"
        @enter-press="saveEdit"
        @escape-press="cancelEdit"
        @blur="saveEdit"
      />
    </div>

    <!-- Read mode with link -->
    <a
      v-else-if="href"
      :href="href"
      class="flex h-full min-w-0 items-center gap-2 text-n-slate-11 hover:underline"
    >
      <span
        v-if="iconClass"
        class="flex-shrink-0 size-3.5 text-n-slate-10"
        :class="iconClass"
      />
      <EmojiOrIcon
        v-else
        :icon="icon"
        :emoji="emoji"
        icon-size="14"
        class="flex-shrink-0"
      />
      <span
        v-if="value"
        class="overflow-hidden text-sm whitespace-nowrap text-ellipsis"
        :title="value"
      >
        {{ value }}
      </span>
      <button
        v-else-if="editable"
        type="button"
        class="p-0 text-sm text-n-slate-10 bg-transparent border-0 cursor-pointer hover:text-n-slate-12"
        @click.prevent="startEditing"
      >
        {{ $t('CONTACT_PANEL.ADD_FIELD', { field: title }) }}
      </button>
      <span v-else class="text-sm text-n-slate-11">
        {{ $t('CONTACT_PANEL.NOT_AVAILABLE') }}
      </span>
      <NextButton
        v-if="showCopy && value"
        ghost
        xs
        slate
        :title="$t('CONTACT_PANEL.COPY_LABEL')"
        :aria-label="$t('CONTACT_PANEL.COPY_LABEL')"
        icon="i-lucide-clipboard"
        @click="onCopy"
      />
      <NextButton
        v-if="editable"
        ghost
        xs
        slate
        class="[@media(hover:hover)]:opacity-0 [@media(hover:hover)]:group-hover/row:opacity-100 transition-opacity"
        :title="$t('CONTACT_PANEL.CLICK_TO_EDIT')"
        :aria-label="$t('CONTACT_PANEL.CLICK_TO_EDIT')"
        icon="i-lucide-pencil"
        @click.prevent="startEditing"
      />
    </a>

    <!-- Read mode without link -->
    <div v-else class="flex h-full min-w-0 items-center gap-2 text-n-slate-11">
      <span
        v-if="iconClass"
        class="flex-shrink-0 size-3.5 text-n-slate-10"
        :class="iconClass"
      />
      <EmojiOrIcon
        v-else
        :icon="icon"
        :emoji="emoji"
        icon-size="14"
        class="flex-shrink-0"
      />
      <span
        v-if="value"
        v-dompurify-html="value"
        class="overflow-hidden text-sm whitespace-nowrap text-ellipsis"
      />
      <button
        v-else-if="editable"
        type="button"
        class="p-0 text-sm text-n-slate-10 bg-transparent border-0 cursor-pointer hover:text-n-slate-12"
        @click.prevent="startEditing"
      >
        {{ $t('CONTACT_PANEL.ADD_FIELD', { field: title }) }}
      </button>
      <span v-else class="text-sm text-n-slate-11">
        {{ $t('CONTACT_PANEL.NOT_AVAILABLE') }}
      </span>
      <NextButton
        v-if="showCopy && value"
        ghost
        xs
        slate
        :title="$t('CONTACT_PANEL.COPY_LABEL')"
        :aria-label="$t('CONTACT_PANEL.COPY_LABEL')"
        icon="i-lucide-clipboard"
        @click="onCopy"
      />
      <NextButton
        v-if="editable"
        ghost
        xs
        slate
        class="[@media(hover:hover)]:opacity-0 [@media(hover:hover)]:group-hover/row:opacity-100 transition-opacity"
        :title="$t('CONTACT_PANEL.CLICK_TO_EDIT')"
        :aria-label="$t('CONTACT_PANEL.CLICK_TO_EDIT')"
        icon="i-lucide-pencil"
        @click="startEditing"
      />
    </div>
  </div>
</template>
