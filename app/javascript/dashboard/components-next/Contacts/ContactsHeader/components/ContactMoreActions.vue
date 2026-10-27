<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import MenuPopover from 'dashboard/components-next/dropdown-menu/MenuPopover.vue';
import { usePolicy } from 'dashboard/composables/usePolicy';
import { useAccount } from 'dashboard/composables/useAccount';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const emit = defineEmits(['add', 'import', 'export']);

const { t } = useI18n();
const { checkPermissions } = usePolicy();
const { isCloudFeatureEnabled } = useAccount();

// Importing is not a download, so it stays available even when the super admin
// has turned customer data downloads off for this account.
const canExportContacts = computed(
  () =>
    checkPermissions(['administrator', 'contact_manage']) &&
    isCloudFeatureEnabled(FEATURE_FLAGS.CUSTOMER_DATA_EXPORT)
);

const contactMenuItems = computed(() => [
  {
    label: t('CONTACTS_LAYOUT.HEADER.ACTIONS.CONTACT_CREATION.ADD_CONTACT'),
    action: 'add',
    value: 'add',
    icon: 'i-lucide-plus',
  },
  ...(canExportContacts.value
    ? [
        {
          label: t(
            'CONTACTS_LAYOUT.HEADER.ACTIONS.CONTACT_CREATION.EXPORT_CONTACT'
          ),
          action: 'export',
          value: 'export',
          icon: 'i-lucide-upload',
        },
      ]
    : []),
  ...(checkPermissions(['administrator', 'contact_manage'])
    ? [
        {
          label: t(
            'CONTACTS_LAYOUT.HEADER.ACTIONS.CONTACT_CREATION.IMPORT_CONTACT'
          ),
          action: 'import',
          value: 'import',
          icon: 'i-lucide-download',
        },
      ]
    : []),
]);
const showActionsDropdown = ref(false);

const handleContactAction = ({ action }) => {
  if (action === 'add') {
    emit('add');
  } else if (action === 'import') {
    emit('import');
  } else if (action === 'export') {
    emit('export');
  }
};
</script>

<template>
  <MenuPopover
    v-model:open="showActionsDropdown"
    :menu-items="contactMenuItems"
    :label="t('CONTACTS_LAYOUT.HEADER.ACTIONS.CONTACT_CREATION.ADD_CONTACT')"
    panel-class="w-52 max-w-[calc(100vw-2rem)]"
    @action="handleContactAction"
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
</template>
