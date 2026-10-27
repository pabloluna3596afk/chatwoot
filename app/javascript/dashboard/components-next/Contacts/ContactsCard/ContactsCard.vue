<script setup>
import { ref, computed, onMounted, nextTick, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import CardLayout from 'dashboard/components-next/CardLayout.vue';
import ContactsForm from 'dashboard/components-next/Contacts/ContactsForm/ContactsForm.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import SaveStateButton from 'dashboard/components-next/button/SaveStateButton.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Flag from 'dashboard/components-next/flag/Flag.vue';
import ConfirmContactDeleteDialog from 'dashboard/components-next/Contacts/ContactsForm/ConfirmContactDeleteDialog.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import FeaturedAttributeBadges from 'dashboard/components-next/FeaturedAttributes/FeaturedAttributeBadges.vue';
import { useFeaturedAttributes } from 'dashboard/composables/useFeaturedAttributes';
import { usePolicy } from 'dashboard/composables/usePolicy';
import countries from 'shared/constants/countries';

const props = defineProps({
  id: { type: Number, required: true },
  name: { type: String, default: '' },
  email: { type: String, default: '' },
  documentNumber: { type: String, default: '' },
  companyId: { type: [Number, String], default: '' },
  additionalAttributes: { type: Object, default: () => ({}) },
  customAttributes: { type: Object, default: () => ({}) },
  phoneNumber: { type: String, default: '' },
  thumbnail: { type: String, default: '' },
  availabilityStatus: { type: String, default: null },
  isExpanded: { type: Boolean, default: false },
  isUpdating: { type: Boolean, default: false },
  selectable: { type: Boolean, default: false },
  isSelected: { type: Boolean, default: false },
});

const emit = defineEmits([
  'toggle',
  'updateContact',
  'showContact',
  'select',
  'avatarHover',
]);

const { t } = useI18n();

const contactRecord = computed(() => ({
  custom_attributes: props.customAttributes,
}));
const { featuredBadges } = useFeaturedAttributes(
  'contact_attribute',
  contactRecord
);

const contactsFormRef = ref(null);
const confirmDeleteContactDialogRef = ref(null);
const { checkPermissions } = usePolicy();
const canDeleteContact = computed(() => checkPermissions(['administrator']));

const getInitialContactData = () => ({
  id: props.id,
  name: props.name,
  email: props.email,
  documentNumber: props.documentNumber,
  companyId: props.companyId,
  phoneNumber: props.phoneNumber,
  additionalAttributes: props.additionalAttributes,
});

const contactData = ref(getInitialContactData());
const snapshotForm = () => JSON.stringify(contactsFormRef.value?.state || {});
const initialContactSnapshot = ref('');
const isDirty = computed(() => snapshotForm() !== initialContactSnapshot.value);
const resetSnapshot = async () => {
  await nextTick();
  initialContactSnapshot.value = snapshotForm();
};
onMounted(resetSnapshot);
watch(() => props.isExpanded, resetSnapshot);

const isFormInvalid = computed(() => contactsFormRef.value?.isFormInvalid);

const countriesMap = computed(() => {
  return countries.reduce((acc, country) => {
    acc[country.id] = country;
    return acc;
  }, {});
});

const countryDetails = computed(() => {
  const attributes = props.additionalAttributes || {};
  const { country, countryCode, city } = attributes;

  if (!country && !countryCode) return null;

  const activeCountry =
    countriesMap.value[country] || countriesMap.value[countryCode];

  if (!activeCountry) return null;

  return {
    countryCode: activeCountry.id,
    city: city ? `${city},` : null,
    name: activeCountry.name,
  };
});

const formattedLocation = computed(() => {
  if (!countryDetails.value) return '';

  return [countryDetails.value.city, countryDetails.value.name]
    .filter(Boolean)
    .join(' ');
});

const handleFormUpdate = updatedData => {
  Object.assign(contactData.value, updatedData);
};

const handleUpdateContact = () => {
  emit('updateContact', contactData.value, () => {
    initialContactSnapshot.value = snapshotForm();
  });
};

const onClickExpand = () => {
  emit('toggle');
  contactData.value = getInitialContactData();
};

const onClickViewDetails = () => emit('showContact', props.id);

const openConfirmDeleteContactDialog = () => {
  confirmDeleteContactDialogRef.value?.dialogRef.open();
};

const toggleSelect = checked => {
  emit('select', checked);
};

const handleAvatarHover = isHovered => {
  emit('avatarHover', isHovered);
};

const handleAvatarClick = () => {
  toggleSelect(!props.isSelected);
};
</script>

<template>
  <div class="relative">
    <CardLayout
      :key="id"
      layout="col"
      padding="compact"
      class="min-w-0 dark:bg-n-solid-3 cursor-pointer"
      :class="{
        'outline-n-weak !bg-n-slate-3 dark:!bg-n-solid-3': isSelected,
      }"
      @click="onClickExpand"
    >
      <div class="flex items-start w-full min-w-0 gap-3">
        <div
          class="relative shrink-0"
          @click.stop="handleAvatarClick"
          @mouseenter="handleAvatarHover(true)"
          @mouseleave="handleAvatarHover(false)"
        >
          <Avatar
            :name="name"
            :src="thumbnail"
            :size="42"
            :status="availabilityStatus"
            hide-offline-status
          >
            <template v-if="selectable" #overlay="{ size }">
              <label
                class="absolute inset-0 z-10 flex cursor-pointer items-center justify-center rounded-full border border-n-slate-8 backdrop-blur-[2px] dark:border-n-slate-7"
                :style="{ width: `${size}px`, height: `${size}px` }"
                :title="
                  t('CONTACTS_BULK_ACTIONS.SELECT_CONTACT_ACCESSIBILITY', {
                    name,
                  })
                "
                @click.stop
              >
                <Checkbox
                  :model-value="isSelected"
                  :aria-label="
                    t('CONTACTS_BULK_ACTIONS.SELECT_CONTACT_ACCESSIBILITY', {
                      name,
                    })
                  "
                  class="[&>span]:!border-n-slate-8 [&>span]:!bg-n-surface-1 [&>input:checked+span]:!border-n-brand [&>input:checked+span]:!bg-n-brand dark:[&>span]:!border-n-slate-7 dark:[&>span]:!bg-n-solid-3 dark:[&>input:checked+span]:!border-n-brand dark:[&>input:checked+span]:!bg-n-brand"
                  @change="event => toggleSelect(event.target.checked)"
                />
              </label>
            </template>
          </Avatar>
        </div>
        <div class="flex flex-col gap-1 flex-1 min-w-0">
          <div class="flex flex-col min-w-0">
            <span
              :title="name"
              class="text-base font-medium truncate text-n-slate-12"
            >
              {{ name }}
            </span>
            <span
              v-if="email"
              :title="email"
              class="text-sm truncate text-n-slate-11"
            >
              {{ email }}
            </span>
            <span
              v-if="phoneNumber"
              :title="phoneNumber"
              class="text-sm truncate text-n-slate-11"
            >
              {{ phoneNumber }}
            </span>
          </div>
          <div class="flex flex-wrap items-center gap-1.5 min-w-0">
            <span
              v-if="additionalAttributes?.companyName"
              class="inline-flex min-w-0 items-center gap-1 rounded-md bg-n-alpha-2 px-2 py-0.5 text-xs text-n-slate-11"
            >
              <span class="i-ph-building-light size-3.5 shrink-0" />
              <span class="truncate">{{
                additionalAttributes.companyName
              }}</span>
            </span>
            <span
              v-if="countryDetails"
              class="inline-flex min-w-0 items-center gap-1 rounded-md bg-n-alpha-2 px-2 py-0.5 text-xs text-n-slate-11"
            >
              <Flag
                :country="countryDetails.countryCode"
                class="size-3.5 shrink-0"
              />
              <span class="truncate">{{ formattedLocation }}</span>
            </span>
            <span
              v-if="documentNumber"
              :title="documentNumber"
              class="max-w-full truncate rounded-md bg-n-alpha-2 px-2 py-0.5 text-xs text-n-slate-11"
            >
              {{ documentNumber }}
            </span>
          </div>
          <FeaturedAttributeBadges :badges="featuredBadges" emphasized />
        </div>
      </div>

      <template #after>
        <div
          class="transition-all duration-500 ease-in-out grid overflow-hidden"
          :class="
            isExpanded
              ? 'grid-rows-[1fr] opacity-100'
              : 'grid-rows-[0fr] opacity-0'
          "
        >
          <div class="overflow-hidden">
            <div
              class="flex flex-col gap-6 p-4 border-t border-n-strong"
              @click.stop
            >
              <div class="flex w-full items-center justify-between gap-2">
                <div class="flex min-w-0 items-center gap-2">
                  <Button
                    :label="t('CONTACTS_LAYOUT.CARD.OPEN')"
                    size="sm"
                    variant="outline"
                    color="slate"
                    @click="onClickViewDetails"
                  />
                  <Button
                    v-if="canDeleteContact"
                    :label="t('CONTACTS_LAYOUT.CARD.DELETE')"
                    :title="t('CONTACTS_LAYOUT.DETAILS.DELETE_CONTACT')"
                    :aria-label="t('CONTACTS_LAYOUT.DETAILS.DELETE_CONTACT')"
                    icon="i-lucide-trash-2"
                    size="sm"
                    variant="outline"
                    color="ruby"
                    class="[&>span:nth-child(2)]:hidden md:[&>span:nth-child(2)]:inline-flex"
                    @click="openConfirmDeleteContactDialog"
                  />
                </div>
                <SaveStateButton
                  :dirty="isDirty"
                  :loading="isUpdating"
                  :invalid="isFormInvalid"
                  :label-clean="t('GENERAL.SAVE_STATE.SAVE')"
                  :invalid-reason="
                    isFormInvalid
                      ? t('CONTACTS_LAYOUT.CARD.EDIT_DETAILS_FORM.INVALID')
                      : ''
                  "
                  @save="handleUpdateContact"
                />
              </div>
              <ContactsForm
                :key="`${id}-${isExpanded}`"
                ref="contactsFormRef"
                :contact-data="contactData"
                @update="handleFormUpdate"
              />
            </div>
            <ConfirmContactDeleteDialog
              v-if="canDeleteContact"
              ref="confirmDeleteContactDialogRef"
              :selected-contact="{ id: props.id, name: props.name }"
            />
          </div>
        </div>
      </template>
    </CardLayout>
  </div>
</template>
