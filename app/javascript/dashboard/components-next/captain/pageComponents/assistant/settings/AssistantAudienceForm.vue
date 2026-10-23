<script setup>
import { computed, ref, watch, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import RadioCard from 'dashboard/components-next/radioCard/RadioCard.vue';
import { useAdmin } from 'dashboard/composables/useAdmin';
import InboxAudienceCard from './audience/InboxAudienceCard.vue';
import { useAudienceTree } from './audience/useAudienceTree';
import AudienceGroup from './audience/AudienceGroup.vue';
import { useAudienceFilterTypes } from './audience/useAudienceFilterTypes.js';

const props = defineProps({
  assistant: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['submit']);

const { t, locale } = useI18n();
const { filterTypes } = useAudienceFilterTypes();
const store = useStore();
const { isAdmin } = useAdmin();
const connectedInboxes = useMapGetter('captainInboxes/getRecords');
const inboxFlags = useMapGetter('captainInboxes/getUIFlags');

const CHANNELS = {
  'Channel::Instagram': 'instagram',
  'Channel::FacebookPage': 'messenger',
  'Channel::WebWidget': 'web',
  'Channel::Email': 'email',
  'Channel::Whatsapp': 'whatsapp',
  'Channel::Sms': 'sms',
  'Channel::TwilioSms': 'sms',
};
const MISSING_ATTRIBUTES = {
  phone_number: ['instagram', 'messenger', 'web', 'email'],
  email: ['whatsapp', 'sms', 'instagram', 'messenger'],
};

watch(
  () => props.assistant.id,
  id => {
    if (id) store.dispatch('captainInboxes/get', { assistantId: id });
  },
  { immediate: true }
);

const MODE = {
  EVERYONE: 'everyone',
  SPECIFIC: 'specific',
};

const { defaultRoot, hydrateRoot, serializeNode } =
  useAudienceTree(filterTypes);
const hasConditions = node =>
  node && Object.prototype.hasOwnProperty.call(node, 'conditions');

const root = ref(defaultRoot());
const mode = ref(MODE.EVERYONE);
const showEmptyAudienceError = ref(false);

const conditionAttributes = node =>
  hasConditions(node)
    ? node.conditions.flatMap(conditionAttributes)
    : [node.attributeKey];

const channelLabels = computed(() => ({
  instagram: t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.CHANNELS.INSTAGRAM'),
  messenger: t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.CHANNELS.MESSENGER'),
  web: t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.CHANNELS.WEB'),
  email: t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.CHANNELS.EMAIL'),
  whatsapp: t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.CHANNELS.WHATSAPP'),
  sms: t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.CHANNELS.SMS'),
}));
const channelForInbox = inbox =>
  inbox.channel_type === 'Channel::TwilioSms' && inbox.medium === 'whatsapp'
    ? 'whatsapp'
    : CHANNELS[inbox.channel_type];
const warningText = (key, channels) =>
  t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.CHANNEL_WARNING', {
    attribute: filterTypes.value.find(type => type.attributeKey === key).label,
    channels: new Intl.ListFormat(locale?.value, {
      type: 'conjunction',
    }).format(channels.map(channel => channelLabels.value[channel])),
  });

const channelWarnings = computed(() => {
  if (mode.value !== MODE.SPECIFIC || inboxFlags.value.fetchingList) return [];

  const attributes = new Set(conditionAttributes(root.value));
  const channels = connectedInboxes.value
    .filter(inbox => inbox.audience_mode === 'inherit')
    .map(channelForInbox);
  return Object.entries(MISSING_ATTRIBUTES).flatMap(
    ([key, missingChannels]) => {
      const affected = [
        ...new Set(channels.filter(c => missingChannels.includes(c))),
      ];
      if (!attributes.has(key) || !affected.length) return [];

      return [
        {
          key,
          channels: affected,
          text: warningText(key, affected),
        },
      ];
    }
  );
});

const inboxWarnings = inbox => {
  const channel = channelForInbox(inbox);
  return channelWarnings.value
    .filter(warning => warning.channels.includes(channel))
    .map(warning => warningText(warning.key, [channel]));
};

const groupRef = useTemplateRef('groupRef');

const handleSubmit = () => {
  if (!isAdmin.value) return;
  const isSpecific = mode.value === MODE.SPECIFIC;
  if (isSpecific && !root.value.conditions.length) {
    showEmptyAudienceError.value = true;
    return;
  }

  showEmptyAudienceError.value = false;
  if (isSpecific && !groupRef.value.validate()) return;

  const audience =
    isSpecific && root.value.conditions.length
      ? serializeNode(root.value)
      : null;

  emit('submit', {
    config: {
      ...props.assistant.config,
      audience,
    },
  });
};

watch(
  () => props.assistant,
  newAssistant => {
    if (!newAssistant) return;
    const audience = newAssistant.config?.audience;
    root.value = hydrateRoot(audience);
    mode.value = audience ? MODE.SPECIFIC : MODE.EVERYONE;
  },
  { immediate: true }
);

watch(
  () => root.value.conditions.length,
  () => {
    showEmptyAudienceError.value = false;
  }
);
</script>

<template>
  <div class="flex flex-col gap-4">
    <div>
      <h2 class="text-heading-3 text-n-slate-12">
        {{ t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX.BASE') }}
      </h2>
      <p class="text-body-main text-n-slate-11">
        {{ t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX.BASE_HELP') }}
      </p>
    </div>
    <fieldset :disabled="!isAdmin" class="min-w-0 flex flex-col gap-3">
      <RadioCard
        :id="MODE.EVERYONE"
        :label="t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.EVERYONE.LABEL')"
        :description="t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.EVERYONE.DESC')"
        :is-active="mode === MODE.EVERYONE"
        @select="mode = MODE.EVERYONE"
      />
      <RadioCard
        :id="MODE.SPECIFIC"
        :label="t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.SPECIFIC.LABEL')"
        :description="t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.SPECIFIC.DESC')"
        :is-active="mode === MODE.SPECIFIC"
        @select="mode = MODE.SPECIFIC"
      >
        <AudienceGroup
          v-if="mode === MODE.SPECIFIC"
          ref="groupRef"
          v-model="root"
          is-root
          class="w-full mt-2"
          :filter-types="filterTypes"
        />
        <p v-if="showEmptyAudienceError" class="mt-2 text-sm text-n-ruby-11">
          {{ t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.EMPTY_ERROR') }}
        </p>
      </RadioCard>
    </fieldset>
    <Banner
      v-for="warning in channelWarnings"
      :key="warning.key"
      color="amber"
      role="status"
    >
      {{ warning.text }}
    </Banner>
    <div v-if="isAdmin">
      <Button
        :label="t('CAPTAIN.ASSISTANTS.FORM.UPDATE')"
        @click="handleSubmit"
      />
    </div>
    <h2 class="text-heading-3 text-n-slate-12">
      {{ t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX.TITLE') }}
    </h2>
    <InboxAudienceCard
      v-for="inbox in inboxFlags.fetchingList ? [] : connectedInboxes"
      :key="`${assistant.id}-${inbox.id}`"
      :inbox="inbox"
      :assistant-id="assistant.id"
      :can-edit="isAdmin"
      :filter-types="filterTypes"
      :warnings="inboxWarnings(inbox)"
    />
  </div>
</template>
