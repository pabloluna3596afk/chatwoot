<script setup>
import { useAlert } from 'dashboard/composables';
import {
  DuplicateContactException,
  ExceptionWithMessage,
} from 'shared/helpers/CustomErrors';
import { dynamicTime } from 'shared/helpers/timeHelper';
import { useAdmin } from 'dashboard/composables/useAdmin';
import ContactInfoRow from './ContactInfoRow.vue';
import ViewAllConversations from './ViewAllConversations.vue';
import Avatar from 'next/avatar/Avatar.vue';
import SocialIcons from './SocialIcons.vue';
import EditContact from './EditContact.vue';
import ContactMergeDialog from 'dashboard/components-next/Contacts/ContactMergeDialog.vue';
import ConfirmContactDeleteDialog from 'dashboard/components-next/Contacts/ContactsForm/ConfirmContactDeleteDialog.vue';
import ComposeConversation from 'dashboard/components-next/NewConversation/ComposeConversation.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import MenuPopover from 'dashboard/components-next/dropdown-menu/MenuPopover.vue';
import VoiceCallButton from 'dashboard/components-next/Contacts/VoiceCallButton.vue';
import InlineInput from 'dashboard/components-next/inline-input/InlineInput.vue';
import ContactAssigneeSelector from 'dashboard/components-next/Contacts/ContactAssigneeSelector.vue';
import FeaturedAttributeBadges from 'dashboard/components-next/FeaturedAttributes/FeaturedAttributeBadges.vue';
import { useFeaturedAttributes } from 'dashboard/composables/useFeaturedAttributes';
import { computed, toRef, ref, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import {
  isAConversationRoute,
  isAInboxViewRoute,
  getConversationDashboardRoute,
} from 'dashboard/helper/routeHelpers';
import { useStore } from 'vuex';

const props = defineProps({
  contact: { type: Object, default: () => ({}) },
  showAvatar: { type: Boolean, default: true },
});
const emit = defineEmits(['panelClose']);
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();
const { isAdmin } = useAdmin();
const contactRef = toRef(props, 'contact');
const currentChat = computed(() => store.getters.getSelectedChat);
const uiFlags = computed(() => store.getters['contacts/getUIFlags']);
const { featuredBadges: featuredContactBadges } = useFeaturedAttributes(
  'contact_attribute',
  contactRef
);
const { featuredBadges: featuredConversationBadges } = useFeaturedAttributes(
  'conversation_attribute',
  currentChat
);
const showEditModal = ref(false);
const isEditingName = ref(false);
const editName = ref('');
const showHeaderMenu = ref(false);
const nameInput = ref(null);
const mergeDialog = ref(null);
const deleteDialog = ref(null);

const headerMenuItems = computed(() => {
  const items = [
    {
      action: 'profile',
      value: 'profile',
      label: t('CONTACT_PANEL.VIEW_PROFILE'),
      icon: 'i-lucide-external-link',
    },
    {
      action: 'edit',
      value: 'edit',
      label: t('EDIT_CONTACT.BUTTON_LABEL'),
      icon: 'i-lucide-pencil',
    },
  ];
  if (props.contact.created_at) {
    items.push({
      action: 'created',
      value: 'created',
      label: `${t('CONTACT_PANEL.CREATED_AT_LABEL')} ${dynamicTime(props.contact.created_at)}`,
      icon: 'i-lucide-info',
    });
  }
  items.push({
    action: 'merge',
    value: 'merge',
    label: t('CONTACT_PANEL.MERGE_CONTACT'),
    icon: 'i-lucide-git-merge',
    disabled: uiFlags.value.isMerging,
  });
  if (isAdmin.value) {
    items.push({
      action: 'delete',
      value: 'delete',
      label: t('DELETE_CONTACT.BUTTON_LABEL'),
      icon: 'i-lucide-trash-2',
      disabled: uiFlags.value.isDeleting,
    });
  }
  return items;
});

const contactProfileLink = computed(() => {
  return `/app/accounts/${route.params.accountId}/contacts/${props.contact.id}`;
});

const additionalAttributes = computed(() => {
  return (
    props.contact.additionalAttributes ||
    props.contact.additional_attributes ||
    {}
  );
});

const phoneNumber = computed(() => {
  const phone = props.contact.phoneNumber || props.contact.phone_number || '';
  if (phone) return phone;

  const sender = currentChat.value?.meta?.sender || {};
  return (
    sender.phone_number || sender.phoneNumber || props.contact.identifier || ''
  );
});

const documentNumber = computed(() => {
  return props.contact.documentNumber || props.contact.document_number || '';
});

const findCountryFlag = (countryCode, cityAndCountry) => {
  try {
    if (!countryCode) {
      return `${cityAndCountry} ðŸŒŽ`;
    }

    const code = countryCode?.toLowerCase();
    return `${cityAndCountry} <span class="fi fi-${code} size-3.5"></span>`;
  } catch (error) {
    return '';
  }
};

const location = computed(() => {
  const {
    country = '',
    city = '',
    country_code: countryCodeSnake,
    countryCode,
  } = additionalAttributes.value;
  const resolvedCountryCode = countryCodeSnake || countryCode;
  const cityAndCountry = [city, country].filter(item => !!item).join(', ');

  if (!cityAndCountry) {
    return '';
  }
  return findCountryFlag(resolvedCountryCode, cityAndCountry);
});

const socialProfiles = computed(() => {
  const {
    social_profiles: socialProfilesSnake,
    socialProfiles: socialProfilesCamel,
    screen_name: twitterScreenNameSnake,
    screenName: twitterScreenNameCamel,
    social_telegram_user_name: telegramUsernameSnake,
    socialTelegramUserName: telegramUsernameCamel,
  } = additionalAttributes.value;
  const profiles = socialProfilesCamel || socialProfilesSnake || {};
  const twitterScreenName = twitterScreenNameCamel || twitterScreenNameSnake;

  const telegram =
    profiles.telegram || telegramUsernameCamel || telegramUsernameSnake || '';
  const twitter = profiles?.twitter || twitterScreenName || '';

  return {
    ...(profiles || {}),
    twitter,
    telegram,
  };
});

const whatsappUsername = computed(() => {
  const username =
    socialProfiles.value.whatsapp ||
    additionalAttributes.value.social_whatsapp_user_name ||
    '';

  return username.toString().replace(/^@+/, '');
});

const formattedWhatsappUsername = computed(() => {
  return whatsappUsername.value ? `@${whatsappUsername.value}` : '';
});

watch(
  () => props.contact.id,
  id => {
    store.dispatch('contacts/fetchContactableInbox', id);
  },
  { immediate: true }
);

const toggleEditModal = () => {
  showEditModal.value = !showEditModal.value;
};

const onHeaderMenuAction = ({ action }) => {
  showHeaderMenu.value = false;
  if (action === 'profile') {
    window.open(contactProfileLink.value, '_blank', 'noopener,noreferrer');
  } else if (action === 'edit') {
    toggleEditModal();
  } else if (action === 'merge') {
    mergeDialog.value.open();
  } else if (action === 'delete' && isAdmin.value) {
    deleteDialog.value.dialogRef.open();
  }
};

const startEditingName = () => {
  editName.value = props.contact.name || '';
  isEditingName.value = true;
  nextTick(() => {
    nameInput.value?.focus();
  });
};

const updateContactField = async attrs => {
  const contactId = props.contact.id;
  try {
    await store.dispatch('contacts/update', {
      id: contactId,
      ...attrs,
    });
    useAlert(t('CONTACT_FORM.SUCCESS_MESSAGE'));
    await store.dispatch('contacts/fetchContactableInbox', contactId);
  } catch (error) {
    if (error instanceof DuplicateContactException) {
      const detail = error.contactErrorDetail;
      if (detail) {
        useAlert(detail);
      } else {
        const invalidAttrs = Array.isArray(error.data) ? error.data : [];
        if (invalidAttrs.includes('email')) {
          useAlert(t('CONTACT_FORM.FORM.EMAIL_ADDRESS.DUPLICATE'));
        } else if (invalidAttrs.includes('phone_number')) {
          useAlert(t('CONTACT_FORM.FORM.PHONE_NUMBER.DUPLICATE'));
        } else {
          useAlert(t('CONTACT_FORM.ERROR_MESSAGE'));
        }
      }
    } else if (error instanceof ExceptionWithMessage) {
      useAlert(error.data);
    } else {
      useAlert(error.message || t('CONTACT_FORM.ERROR_MESSAGE'));
    }
  }
};

const saveNameEdit = () => {
  if (!isEditingName.value) return;
  isEditingName.value = false;
  const trimmed = editName.value.trim();
  if (trimmed && trimmed !== props.contact.name) {
    updateContactField({ name: trimmed });
  }
};

const cancelNameEdit = () => {
  isEditingName.value = false;
};

const onFieldUpdate = (field, value) => {
  updateContactField({ [field]: value });
};

const onContactRemoved = () => {
  emit('panelClose');
  let name = 'contacts_dashboard';
  if (isAConversationRoute(route.name)) {
    name = getConversationDashboardRoute(route.name);
  } else if (isAInboxViewRoute(route.name)) {
    name = 'inbox_view';
  }
  router.push({ name });
};
</script>

<template>
  <div class="relative items-center w-full px-3 py-2">
    <div class="flex flex-col w-full gap-1 text-left rtl:text-right">
      <div class="flex flex-row items-start gap-2.5 w-full min-w-0">
        <Avatar
          v-if="showAvatar"
          :src="contact.thumbnail"
          :name="contact.name"
          :status="contact.availability_status"
          :size="48"
          hide-offline-status
          class="flex-shrink-0"
        />
        <div class="flex flex-col gap-0.5 min-w-0 flex-1 justify-center">
          <div class="flex items-start gap-2 min-w-0">
            <InlineInput
              v-if="isEditingName"
              ref="nameInput"
              v-model="editName"
              custom-input-class="!text-base !font-medium !w-auto max-w-full [field-sizing:content]"
              class="!w-fit min-w-0"
              @enter-press="saveNameEdit"
              @escape-press="cancelNameEdit"
              @blur="saveNameEdit"
            />
            <h3
              v-else-if="showAvatar"
              class="group/name flex-1 min-w-0 my-0 text-base font-medium break-words text-n-slate-12 cursor-pointer hover:text-n-slate-12/80"
              :title="$t('CONTACT_PANEL.CLICK_TO_EDIT')"
              @click="startEditingName"
            >
              {{ contact.name }}
              <span
                class="i-lucide-pencil text-xs text-n-slate-10 [@media(hover:hover)]:opacity-0 [@media(hover:hover)]:group-hover/name:opacity-100 transition-opacity ml-1 align-middle"
              />
            </h3>
            <div class="flex items-center flex-shrink-0 gap-1">
              <ComposeConversation :contact-id="String(contact.id)">
                <template #trigger>
                  <NextButton
                    v-tooltip.top-end="$t('CONTACT_PANEL.NEW_MESSAGE')"
                    :aria-label="$t('CONTACT_PANEL.NEW_MESSAGE')"
                    :title="$t('CONTACT_PANEL.NEW_MESSAGE')"
                    icon="i-ph-chat-circle-dots"
                    slate
                    faded
                    xs
                  />
                </template>
              </ComposeConversation>
              <ViewAllConversations :contact="contact" />
              <VoiceCallButton
                :phone="phoneNumber"
                :contact-id="contact.id"
                :conversation-id="currentChat?.id"
                icon="i-lucide-phone"
                size="xs"
                faded
                slate
                :tooltip-label="$t('CONTACT_PANEL.CALL')"
              />
              <MenuPopover
                v-model:open="showHeaderMenu"
                :menu-items="headerMenuItems"
                :label="$t('CONTACT_PANEL.MORE_ACTIONS')"
                :restore-focus-on-select="false"
                @action="onHeaderMenuAction"
              >
                <template #trigger>
                  <NextButton
                    :aria-label="$t('CONTACT_PANEL.MORE_ACTIONS')"
                    :title="$t('CONTACT_PANEL.MORE_ACTIONS')"
                    :aria-expanded="showHeaderMenu"
                    aria-haspopup="dialog"
                    icon="i-lucide-ellipsis-vertical"
                    slate
                    ghost
                    xs
                    data-testid="contact-header-menu"
                    @click="showHeaderMenu = !showHeaderMenu"
                  />
                </template>
              </MenuPopover>
            </div>
          </div>
        </div>
      </div>

      <ContactInfoRow
        :href="phoneNumber ? `tel:${phoneNumber}` : ''"
        :value="phoneNumber"
        icon="call"
        emoji="📞"
        :title="$t('CONTACT_PANEL.PHONE_NUMBER')"
        show-copy
        editable
        @update="value => onFieldUpdate('phone_number', value)"
      />

      <p v-if="additionalAttributes.description" class="break-words mb-0.5">
        {{ additionalAttributes.description }}
      </p>
      <div class="flex flex-col items-start w-full gap-1.5">
        <ContactInfoRow
          :value="documentNumber"
          icon="contact-identify"
          icon-class="i-ph-identification-card"
          emoji="🪪"
          :title="$t('CONTACT_PANEL.DOCUMENT_NUMBER')"
          show-copy
          editable
          @update="value => onFieldUpdate('document_number', value)"
        />
        <ContactInfoRow
          :href="contact.email ? `mailto:${contact.email}` : ''"
          :value="contact.email"
          icon="mail"
          emoji="✉️"
          :title="$t('CONTACT_PANEL.EMAIL_ADDRESS')"
          show-copy
          editable
          @update="value => onFieldUpdate('email', value)"
        />
        <ContactInfoRow
          v-if="formattedWhatsappUsername"
          :value="formattedWhatsappUsername"
          icon="brand-whatsapp"
          emoji="💬"
          :title="$t('CONTACT_PANEL.WHATSAPP_USERNAME')"
          show-copy
        />
        <ContactInfoRow
          v-if="contact.identifier"
          :value="contact.identifier"
          icon="contact-identify"
          emoji="🪪"
          :title="$t('CONTACT_PANEL.IDENTIFIER')"
        />
        <ContactInfoRow
          :value="additionalAttributes.company_name"
          icon="building-bank"
          emoji="🏢"
          :title="$t('CONTACT_PANEL.COMPANY')"
          editable
          @update="
            value =>
              updateContactField({
                additional_attributes: {
                  ...additionalAttributes,
                  company_name: value,
                },
              })
          "
        />
        <ContactInfoRow
          v-if="location || additionalAttributes.location"
          :value="location || additionalAttributes.location"
          icon="map"
          emoji="🌍"
          :title="$t('CONTACT_PANEL.LOCATION')"
        />
        <SocialIcons :social-profiles="socialProfiles" />
        <div
          v-if="
            featuredContactBadges.length || featuredConversationBadges.length
          "
          class="flex flex-col gap-1 mt-1"
        >
          <FeaturedAttributeBadges
            v-if="featuredContactBadges.length"
            :badges="featuredContactBadges"
            variant="contact"
          />
          <FeaturedAttributeBadges
            v-if="featuredConversationBadges.length"
            :badges="featuredConversationBadges"
            variant="conversation"
          />
        </div>
        <ContactAssigneeSelector
          v-if="contact.id"
          :contact="contact"
          class="mt-1"
        />
      </div>
      <ContactMergeDialog
        ref="mergeDialog"
        content-class="!px-0 [&>div:last-child]:flex-col sm:[&>div:last-child]:flex-row"
        :selected-contact="contact"
        @go-to-contacts-list="onContactRemoved"
      />
      <ConfirmContactDeleteDialog
        v-if="isAdmin"
        ref="deleteDialog"
        :selected-contact="contact"
        @go-to-contacts-list="onContactRemoved"
      />
      <EditContact
        :show="showEditModal"
        :contact="contact"
        @cancel="toggleEditModal"
      />
    </div>
  </div>
</template>
