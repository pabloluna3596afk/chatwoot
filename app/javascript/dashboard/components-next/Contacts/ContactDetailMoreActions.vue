<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import MenuPopover from 'dashboard/components-next/dropdown-menu/MenuPopover.vue';
import ConfirmContactDeleteDialog from 'dashboard/components-next/Contacts/ContactsForm/ConfirmContactDeleteDialog.vue';
import ContactMergeDialog from 'dashboard/components-next/Contacts/ContactMergeDialog.vue';
import { usePolicy } from 'dashboard/composables/usePolicy';

defineProps({
  selectedContact: {
    type: Object,
    default: null,
  },
});

const emit = defineEmits(['goToContactsList']);

const { t } = useI18n();
const { checkPermissions } = usePolicy();

const showActionsDropdown = ref(false);
const confirmDeleteContactDialogRef = ref(null);
const contactMergeDialogRef = ref(null);

const isAdmin = computed(() => checkPermissions(['administrator']));

const menuItems = computed(() => {
  const items = [
    {
      label: t('CONTACTS_LAYOUT.DETAILS.MORE_ACTIONS.MERGE'),
      action: 'merge',
      value: 'merge',
      icon: 'i-lucide-git-merge',
    },
  ];

  if (isAdmin.value) {
    items.push({
      label: t('CONTACTS_LAYOUT.DETAILS.MORE_ACTIONS.DELETE'),
      action: 'delete',
      value: 'delete',
      icon: 'i-lucide-trash-2',
    });
  }

  return items;
});

const handleContactAction = ({ action }) => {
  showActionsDropdown.value = false;

  if (action === 'merge') {
    contactMergeDialogRef.value?.open?.();
  } else if (action === 'delete') {
    confirmDeleteContactDialogRef.value?.dialogRef.open();
  }
};
</script>

<template>
  <div>
    <MenuPopover
      v-model:open="showActionsDropdown"
      :menu-items="menuItems"
      panel-class="w-52 max-w-[calc(100vw-2rem)]"
      :restore-focus-on-select="false"
      @action="handleContactAction($event)"
    >
      <template #trigger>
        <Button
          icon="i-lucide-ellipsis-vertical"
          color="slate"
          variant="ghost"
          size="sm"
          :class="showActionsDropdown ? 'bg-n-alpha-2' : ''"
          @click="showActionsDropdown = !showActionsDropdown"
        />
      </template>
    </MenuPopover>

    <ContactMergeDialog
      ref="contactMergeDialogRef"
      :selected-contact="selectedContact"
      @go-to-contacts-list="emit('goToContactsList')"
    />

    <ConfirmContactDeleteDialog
      v-if="isAdmin"
      ref="confirmDeleteContactDialogRef"
      :selected-contact="selectedContact"
      @go-to-contacts-list="emit('goToContactsList')"
    />
  </div>
</template>
