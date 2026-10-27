<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';

import CardLayout from 'dashboard/components-next/CardLayout.vue';
import ContactsForm from 'dashboard/components-next/Contacts/ContactsForm/ContactsForm.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Flag from 'dashboard/components-next/flag/Flag.vue';
import ContactDeleteSection from 'dashboard/components-next/Contacts/ContactsCard/ContactDeleteSection.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import FeaturedAttributeBadges from 'dashboard/components-next/FeaturedAttributes/FeaturedAttributeBadges.vue';
import { useFeaturedAttributes } from 'dashboard/composables/useFeaturedAttributes';
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
  emit('updateContact', contactData.value);
};

const onClickExpand = () => {
  emit('toggle');
  contactData.value = getInitialContactData();
};

const onClickViewDetails = () => emit('showContact', props.id);

const toggleSelect = checked => {
  emit('select', checked);
};

const handleAvatarHover = isHovered => {
  emit('avatarHover', isHovered);
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
          @click.stop
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
                class="flex items-center justify-center rounded-full cursor-pointer absolute inset-0 z-10 backdrop-blur-[2px] border border-n-weak"
                :style="{ width: `${size}px`, height: `${size}px` }"
                @click.stop
              >
                <Checkbox
                  :model-value="isSelected"
                  :aria-label="
                    t('GENERAL.ACCESSIBILITY.SELECT_CONTACT', { name })
                  "
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
              <Button
                :label="t('CONTACTS_LAYOUT.CARD.EXPAND')"
                size="sm"
                variant="outline"
                color="slate"
                class="self-start min-h-11"
                @click="onClickViewDetails"
              />
              <ContactsForm
                ref="contactsFormRef"
                :contact-data="contactData"
                @update="handleFormUpdate"
              />
              <div>
                <Button
                  :label="
                    t('CONTACTS_LAYOUT.CARD.EDIT_DETAILS_FORM.UPDATE_BUTTON')
                  "
                  size="sm"
                  class="min-h-11"
                  :is-loading="isUpdating"
                  :disabled="isUpdating || isFormInvalid"
                  @click.stop="handleUpdateContact"
                />
              </div>
            </div>
            <ContactDeleteSection
              :selected-contact="{
                id: props.id,
                name: props.name,
              }"
            />
          </div>
        </div>
      </template>
    </CardLayout>
  </div>
</template>
