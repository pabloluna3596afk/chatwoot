<script setup>
import { computed, ref, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ContactsForm from 'dashboard/components-next/Contacts/ContactsForm/ContactsForm.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import SaveStateButton from 'dashboard/components-next/button/SaveStateButton.vue';

const props = defineProps({
  selectedContact: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();
const store = useStore();

const dialogRef = ref(null);
const contactsFormRef = ref(null);
const contactData = ref({});
const initialSnapshot = ref('');

const uiFlags = useMapGetter('contacts/getUIFlags');
const isUpdating = computed(() => uiFlags.value.isUpdating);
const isFormInvalid = computed(() => contactsFormRef.value?.isFormInvalid);
const currentSnapshot = () =>
  JSON.stringify(contactsFormRef.value?.state || {});
const isDirty = computed(() => currentSnapshot() !== initialSnapshot.value);

watch(
  () => props.selectedContact,
  newContact => {
    contactData.value = newContact ? { ...newContact } : {};
  },
  { immediate: true }
);

const handleFormUpdate = updatedData => {
  Object.assign(contactData.value, updatedData);
};

const open = async () => {
  contactData.value = props.selectedContact ? { ...props.selectedContact } : {};
  initialSnapshot.value = '';
  await dialogRef.value?.open?.();
  await nextTick();
  initialSnapshot.value = currentSnapshot();
};

const close = () => {
  dialogRef.value?.close?.();
};

const updateContact = async () => {
  if (!isDirty.value || isUpdating.value || isFormInvalid.value) return;
  try {
    const { customAttributes, ...basicContactData } = contactData.value;
    await store.dispatch('contacts/update', basicContactData);
    await store.dispatch(
      'contacts/fetchContactableInbox',
      props.selectedContact.id
    );
    useAlert(t('CONTACTS_LAYOUT.CARD.EDIT_DETAILS_FORM.SUCCESS_MESSAGE'));
    initialSnapshot.value = currentSnapshot();
    close();
  } catch (error) {
    useAlert(t('CONTACTS_LAYOUT.CARD.EDIT_DETAILS_FORM.ERROR_MESSAGE'));
  }
};

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    width="2xl"
    overflow-y-auto
    position="top"
    :title="t('CONTACTS_LAYOUT.CARD.EDIT_DETAILS_FORM.TITLE')"
    :show-cancel-button="false"
    :show-confirm-button="false"
    @confirm="updateContact"
  >
    <ContactsForm
      ref="contactsFormRef"
      :contact-data="contactData"
      is-details-view
      @update="handleFormUpdate"
    />
    <template #footer>
      <div class="flex w-full items-center justify-between gap-3">
        <Button
          type="button"
          :label="t('DIALOG.BUTTONS.CANCEL')"
          variant="faded"
          color="slate"
          class="w-full"
          :disabled="isUpdating"
          @click="close"
        />
        <SaveStateButton
          class="w-full"
          :dirty="isDirty"
          :loading="isUpdating"
          :invalid="isFormInvalid"
          :invalid-reason="
            isFormInvalid
              ? t('CONTACTS_LAYOUT.CARD.EDIT_DETAILS_FORM.INVALID')
              : ''
          "
          @save="updateContact"
        />
      </div>
    </template>
  </Dialog>
</template>
