<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import InfoChip from 'dashboard/components-next/ListCard/InfoChip.vue';
import ListCard from 'dashboard/components-next/ListCard/ListCard.vue';

const props = defineProps({
  macro: {
    type: Object,
    required: true,
  },
  canManagePublicMacros: {
    type: Boolean,
    default: true,
  },
  isDuplicating: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['delete', 'duplicate', 'edit']);
const { t } = useI18n();

const createdByName = computed(() => {
  const createdBy = props.macro.created_by;
  if (!createdBy) return '';
  return createdBy.available_name ?? createdBy.email ?? '';
});

const visibilityLabel = computed(() => {
  if (props.macro.visibility === 'global') {
    return t('MACROS.EDITOR.VISIBILITY.GLOBAL.LABEL');
  }
  return t('MACROS.EDITOR.VISIBILITY.PERSONAL.LABEL');
});

const canManageMacro = computed(
  () => props.canManagePublicMacros || props.macro.visibility !== 'global'
);

const editLabel = computed(() =>
  canManageMacro.value ? t('MACROS.EDIT.TOOLTIP') : t('MACROS.VIEW.TOOLTIP')
);

const menuItems = computed(() => [
  {
    action: 'edit',
    label: editLabel.value,
    icon: 'i-lucide-pencil',
  },
  {
    action: 'duplicate',
    label: props.isDuplicating
      ? t('MACROS.DUPLICATE.PROGRESS')
      : t('MACROS.DUPLICATE.TOOLTIP'),
    icon: props.isDuplicating ? 'i-lucide-loader-circle' : 'i-woot-clone',
    disabled: props.isDuplicating,
  },
  ...(canManageMacro.value
    ? [
        {
          action: 'delete',
          label: t('MACROS.DELETE.TOOLTIP'),
          icon: 'i-lucide-trash',
        },
      ]
    : []),
]);

const handleAction = ({ action }) => {
  if (action === 'edit') emit('edit');
  if (action === 'duplicate') emit('duplicate');
  if (action === 'delete') emit('delete');
};
</script>

<template>
  <ListCard
    :title="macro.name"
    :subtitle="createdByName"
    :menu-items="menuItems"
    @action="handleAction"
  >
    <template v-if="macro.created_by" #avatar>
      <Avatar :name="createdByName" :size="40" rounded-full />
    </template>
    <template #chips>
      <InfoChip>{{ visibilityLabel }}</InfoChip>
      <InfoChip v-if="macro.folder">{{ macro.folder }}</InfoChip>
      <InfoChip v-if="isDuplicating">
        <span class="i-lucide-loader-circle me-1 size-3.5 animate-spin" />
        {{ $t('MACROS.DUPLICATE.PROGRESS') }}
      </InfoChip>
    </template>
  </ListCard>
</template>
