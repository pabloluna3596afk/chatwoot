<script setup>
import { computed, ref } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import CardLayout from 'dashboard/components-next/CardLayout.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import InlineInput from 'dashboard/components-next/inline-input/InlineInput.vue';

const props = defineProps({
  // Return true only after the mutation succeeds; events cannot be awaited.
  onEdit: { type: Function, required: true },
  id: {
    type: Number,
    required: true,
  },
  content: {
    type: String,
    required: true,
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

const emit = defineEmits(['select', 'hover', 'delete']);

const modelValue = computed({
  get: () => props.isSelected,
  set: () => emit('select', props.id),
});

const isEditing = ref(false);
const editedContent = ref(props.content);

const isSaving = ref(false);

const startEdit = () => {
  isEditing.value = true;
  editedContent.value = props.content;
};

const saveEdit = async () => {
  if (isSaving.value || !editedContent.value.trim()) return;
  isSaving.value = true;
  try {
    if (await props.onEdit({ id: props.id, content: editedContent.value })) {
      isEditing.value = false;
    }
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <CardLayout
    selectable
    class="relative [&>div]:!py-5 [&>div]:ltr:!pr-4 [&>div]:rtl:!pl-4"
    layout="row"
    @mouseenter="emit('hover', true)"
    @mouseleave="emit('hover', false)"
  >
    <div v-show="selectable" class="absolute top-6 ltr:left-3 rtl:right-3">
      <Checkbox
        v-model="modelValue"
        :aria-label="$t('GENERAL.ACCESSIBILITY.SELECT_RULE', { content })"
      />
    </div>
    <InlineInput
      v-if="isEditing"
      v-model="editedContent"
      focus-on-mount
      :disabled="isSaving"
      @keyup.enter="saveEdit"
    />
    <span v-else class="flex items-center gap-2 text-sm text-n-slate-12">
      {{ content }}
    </span>
    <div class="flex items-center gap-2">
      <Button
        v-if="isEditing"
        :label="$t('DIALOG.BUTTONS.CANCEL')"
        slate
        xs
        ghost
        :disabled="isSaving"
        @click="isEditing = false"
      />
      <Button
        :icon="isEditing ? 'i-lucide-check' : 'i-lucide-pen'"
        :aria-label="
          isEditing
            ? $t('DIALOG.BUTTONS.CONFIRM')
            : $t('CAPTAIN.ASSISTANTS.SCENARIOS.UPDATE.UPDATE')
        "
        slate
        xs
        ghost
        :disabled="isSaving"
        @click="isEditing ? saveEdit() : startEdit()"
      />
      <span class="w-px h-4 bg-n-weak" />
      <Button
        icon="i-lucide-trash"
        slate
        xs
        ghost
        :disabled="isSaving"
        @click="emit('delete', id)"
      />
    </div>
  </CardLayout>
</template>
