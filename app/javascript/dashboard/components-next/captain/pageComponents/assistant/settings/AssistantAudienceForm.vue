<script setup>
import { computed, ref, watch, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import RadioCard from 'dashboard/components-next/radioCard/RadioCard.vue';
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

let uid = 0;
const nextId = () => {
  uid += 1;
  return `audience-root-${uid}`;
};

const hasConditions = node =>
  node && Object.prototype.hasOwnProperty.call(node, 'conditions');

const defaultRoot = () => ({ id: nextId(), operator: 'and', conditions: [] });

const root = ref(defaultRoot());
const mode = ref(MODE.EVERYONE);
const showEmptyAudienceError = ref(false);

const conditionAttributes = node =>
  hasConditions(node)
    ? node.conditions.flatMap(conditionAttributes)
    : [node.attributeKey];

const channelWarnings = computed(() => {
  if (mode.value !== MODE.SPECIFIC || inboxFlags.value.fetchingList) return [];

  const attributes = new Set(conditionAttributes(root.value));
  const channelLabels = {
    instagram: t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.CHANNELS.INSTAGRAM'),
    messenger: t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.CHANNELS.MESSENGER'),
    web: t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.CHANNELS.WEB'),
    email: t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.CHANNELS.EMAIL'),
    whatsapp: t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.CHANNELS.WHATSAPP'),
    sms: t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.CHANNELS.SMS'),
  };
  const channels = connectedInboxes.value.map(inbox =>
    inbox.channel_type === 'Channel::TwilioSms' && inbox.medium === 'whatsapp'
      ? 'whatsapp'
      : CHANNELS[inbox.channel_type]
  );
  return Object.entries(MISSING_ATTRIBUTES).flatMap(
    ([key, missingChannels]) => {
      const affected = [
        ...new Set(channels.filter(c => missingChannels.includes(c))),
      ];
      if (!attributes.has(key) || !affected.length) return [];

      return [
        {
          key,
          text: t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.CHANNEL_WARNING', {
            attribute: filterTypes.value.find(type => type.attributeKey === key)
              .label,
            channels: new Intl.ListFormat(locale?.value, {
              type: 'conjunction',
            }).format(affected.map(channel => channelLabels[channel])),
          }),
        },
      ];
    }
  );
});

const findOption = (filterType, value) =>
  filterType?.options?.find(option => String(option.id) === String(value));

const hydrateValues = (leaf, filterType) => {
  const raw = Array.isArray(leaf.values) ? leaf.values : [leaf.values];
  const inputType = filterType?.inputType;
  if (inputType === 'multiSelect') {
    return raw.map(
      value => findOption(filterType, value) ?? { id: value, name: value }
    );
  }
  if (['searchSelect', 'booleanSelect'].includes(inputType)) {
    return findOption(filterType, raw[0]) ?? { id: raw[0], name: raw[0] };
  }
  return raw[0] ?? '';
};

const hydrateNode = node => {
  if (hasConditions(node)) {
    return {
      id: nextId(),
      operator: node.operator || 'and',
      conditions: (node.conditions || []).map(hydrateNode),
    };
  }

  const filterType = filterTypes.value.find(
    type => type.attributeKey === node.attribute_key
  );
  return {
    id: nextId(),
    attributeKey: node.attribute_key,
    filterOperator: node.filter_operator,
    values: hydrateValues(node, filterType),
    attributeModel: filterType?.attributeModel || 'standard',
  };
};

const hydrateRoot = audience => {
  if (!audience) return defaultRoot();
  const hydrated = hydrateNode(audience);
  return hasConditions(hydrated)
    ? hydrated
    : { id: nextId(), operator: 'and', conditions: [hydrated] };
};

const serializeValues = values => {
  if (Array.isArray(values)) {
    return values[0]?.id ? values.map(value => value.id) : values;
  }
  if (values && typeof values === 'object') {
    return [values.id];
  }
  if (values === '' || values === null || values === undefined) {
    return [];
  }
  return [values];
};

const serializeNode = node => {
  if (hasConditions(node)) {
    return {
      operator: node.operator,
      conditions: node.conditions.map(serializeNode),
    };
  }
  return {
    attribute_key: node.attributeKey,
    filter_operator: node.filterOperator,
    values: serializeValues(node.values),
  };
};

const groupRef = useTemplateRef('groupRef');

const handleSubmit = () => {
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
    <div class="flex flex-col gap-3">
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
    </div>
    <Banner
      v-for="warning in channelWarnings"
      :key="warning.key"
      color="amber"
      role="status"
    >
      {{ warning.text }}
    </Banner>
    <div>
      <Button
        :label="t('CAPTAIN.ASSISTANTS.FORM.UPDATE')"
        @click="handleSubmit"
      />
    </div>
  </div>
</template>
