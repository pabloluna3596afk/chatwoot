<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useFunctionGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import OutlinedSelectField from 'dashboard/components-next/CustomAttributes/OutlinedSelectField.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import { convertToAttributeSlug } from 'dashboard/helper/commons';

// A preset that needs a custom attribute (e.g. a "date of sale" for a
// post-purchase follow-up) must never create it silently — the admin picks
// an attribute that already exists, or names a new one, before the rule is
// created. Resolves with the attribute_key to use, or null if cancelled.
const CREATE_NEW_ID = '__create_new__';

const store = useStore();
const { t } = useI18n();

const dialogRef = ref(null);
const requirement = ref(null);
const attributeModel = computed(() => requirement.value?.attributeModel);
const existingAttributes = useFunctionGetter(
  'attributes/getAttributesByModel',
  attributeModel
);

const selectedId = ref(CREATE_NEW_ID);
const newDisplayName = ref('');
const isSaving = ref(false);
let resolveFn = null;

const matchingExisting = computed(() =>
  (existingAttributes.value || []).filter(
    attr =>
      attr.attribute_display_type === requirement.value?.attributeDisplayType
  )
);

const selectOptions = computed(() => [
  {
    id: CREATE_NEW_ID,
    name: t('AUTOMATION.ATTRIBUTE_REQUIREMENT.CREATE_NEW_OPTION'),
  },
  ...matchingExisting.value.map(attr => ({
    id: attr.attribute_key,
    name: attr.attribute_display_name,
  })),
]);

const selectedOption = computed(
  () =>
    selectOptions.value.find(option => option.id === selectedId.value) ||
    selectOptions.value[0]
);

const isCreatingNew = computed(() => selectedId.value === CREATE_NEW_ID);

const newAttributeKey = computed(() =>
  convertToAttributeSlug(newDisplayName.value)
);

const canConfirm = computed(() => {
  if (!isCreatingNew.value) return true;
  return (
    newDisplayName.value.trim().length > 0 && newAttributeKey.value.length > 0
  );
});

// Resolves with the attribute_key to use, or null if the admin cancelled.
const resolve = req =>
  new Promise(res => {
    requirement.value = req;
    resolveFn = res;
    const preExisting = matchingExisting.value.find(
      attr => attr.attribute_key === req.attributeKey
    );
    selectedId.value = preExisting ? preExisting.attribute_key : CREATE_NEW_ID;
    newDisplayName.value = req.attributeDisplayName;
    dialogRef.value?.open();
  });

// Dialog.close() always emits 'close' (native <dialog> semantics), and that
// event is wired to onCancel below — so calling .close() here re-enters
// onCancel -> finish(null) -> .close() again, forever. Guard on resolveFn
// already being null so only the first call does anything.
const finish = value => {
  if (!resolveFn) return;
  resolveFn(value);
  resolveFn = null;
  dialogRef.value?.close();
};

const onCancel = () => finish(null);

const onConfirm = async () => {
  if (!isCreatingNew.value) {
    finish(selectedId.value);
    return;
  }
  isSaving.value = true;
  try {
    await store.dispatch('attributes/create', {
      attribute_display_name: newDisplayName.value.trim(),
      attribute_key: newAttributeKey.value,
      attribute_model: requirement.value.attributeModel,
      attribute_display_type: requirement.value.attributeDisplayType,
      category: requirement.value.category || '',
    });
    finish(newAttributeKey.value);
  } catch (error) {
    useAlert(t('AUTOMATION.ATTRIBUTE_REQUIREMENT.CREATE_ERROR'));
  } finally {
    isSaving.value = false;
  }
};

defineExpose({ resolve });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    :title="t('AUTOMATION.ATTRIBUTE_REQUIREMENT.TITLE')"
    :description="
      requirement
        ? t('AUTOMATION.ATTRIBUTE_REQUIREMENT.DESCRIPTION', {
            name: requirement.attributeDisplayName,
          })
        : ''
    "
    :confirm-button-label="t('AUTOMATION.ATTRIBUTE_REQUIREMENT.CONFIRM')"
    :cancel-button-label="t('AUTOMATION.ATTRIBUTE_REQUIREMENT.CANCEL')"
    :is-loading="isSaving"
    :disable-confirm-button="!canConfirm"
    @confirm="onConfirm"
    @close="onCancel"
  >
    <div class="flex flex-col gap-4">
      <OutlinedSelectField
        :label="t('AUTOMATION.ATTRIBUTE_REQUIREMENT.SELECT_LABEL')"
        :options="selectOptions"
        :selected-item="selectedOption"
        @select="option => (selectedId = option.id)"
      />
      <Input
        v-if="isCreatingNew"
        v-model="newDisplayName"
        :label="t('AUTOMATION.ATTRIBUTE_REQUIREMENT.NEW_NAME_LABEL')"
        :message="
          newAttributeKey
            ? `${t('AUTOMATION.ATTRIBUTE_REQUIREMENT.KEY_PREVIEW')}: ${newAttributeKey}`
            : ''
        "
      />
    </div>
  </Dialog>
</template>
