<script setup>
import { reactive, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { required, minLength, maxLength, helpers } from '@vuelidate/validators';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Editor from 'dashboard/components-next/Editor/Editor.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

const props = defineProps({
  assistant: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['submit', 'uploadAvatar', 'deleteAvatar']);

const { t } = useI18n();

const BUSINESS_FACT_MAX_LENGTH = 300;
const businessFactFields = computed(() => [
  {
    key: 'hours',
    label: t('CAPTAIN.ASSISTANTS.BUSINESS_FACTS.HOURS.LABEL'),
    placeholder: t('CAPTAIN.ASSISTANTS.BUSINESS_FACTS.HOURS.PLACEHOLDER'),
  },
  {
    key: 'address',
    label: t('CAPTAIN.ASSISTANTS.BUSINESS_FACTS.ADDRESS.LABEL'),
    placeholder: t('CAPTAIN.ASSISTANTS.BUSINESS_FACTS.ADDRESS.PLACEHOLDER'),
  },
  {
    key: 'payment_methods',
    label: t('CAPTAIN.ASSISTANTS.BUSINESS_FACTS.PAYMENT.LABEL'),
    placeholder: t('CAPTAIN.ASSISTANTS.BUSINESS_FACTS.PAYMENT.PLACEHOLDER'),
  },
  {
    key: 'delivery',
    label: t('CAPTAIN.ASSISTANTS.BUSINESS_FACTS.DELIVERY.LABEL'),
    placeholder: t('CAPTAIN.ASSISTANTS.BUSINESS_FACTS.DELIVERY.PLACEHOLDER'),
  },
  {
    key: 'booking',
    label: t('CAPTAIN.ASSISTANTS.BUSINESS_FACTS.BOOKING.LABEL'),
    placeholder: t('CAPTAIN.ASSISTANTS.BUSINESS_FACTS.BOOKING.PLACEHOLDER'),
  },
]);

const initialState = {
  name: '',
  description: '',
  productName: '',
  businessFacts: {},
  features: {
    conversationFaqs: false,
    memories: false,
    citations: false,
    contactAttributes: false,
  },
};

const state = reactive({ ...initialState });

const requiredMessage = helpers.withMessage(
  () => t('GENERAL.VALIDATION.REQUIRED'),
  required
);
const minLengthMessage = helpers.withMessage(
  ({ $params }) => t('GENERAL.VALIDATION.MIN_LENGTH', { min: $params.min }),
  minLength(1)
);
const validationRules = {
  name: { required: requiredMessage, minLength: minLengthMessage },
  description: { required: requiredMessage, minLength: minLengthMessage },
  productName: { required: requiredMessage, minLength: minLengthMessage },
  businessFacts: Object.fromEntries(
    businessFactFields.value.map(({ key }) => [
      key,
      {
        maxLength: helpers.withMessage(
          () => t('CAPTAIN.ASSISTANTS.BUSINESS_FACTS.TOO_LONG'),
          maxLength(BUSINESS_FACT_MAX_LENGTH)
        ),
      },
    ])
  ),
};

const v$ = useVuelidate(validationRules, state);

const getErrorMessage = field => {
  return v$.value[field].$error ? v$.value[field].$errors[0].$message : '';
};

const formErrors = computed(() => ({
  name: getErrorMessage('name'),
  description: getErrorMessage('description'),
  productName: getErrorMessage('productName'),
}));

const updateStateFromAssistant = assistant => {
  const { config = {} } = assistant;
  state.name = assistant.name;
  state.description = assistant.description;
  state.productName = config.product_name;
  state.businessFacts = Object.fromEntries(
    businessFactFields.value.map(({ key }) => [
      key,
      config.business_facts?.[key] ?? '',
    ])
  );
  state.features = {
    conversationFaqs: config.feature_faq || false,
    memories: config.feature_memory || false,
    citations: config.feature_citation || false,
    contactAttributes: config.feature_contact_attributes || false,
  };
};

const handleBasicInfoUpdate = async () => {
  const result = await Promise.all([
    v$.value.name.$validate(),
    v$.value.description.$validate(),
    v$.value.productName.$validate(),
    v$.value.businessFacts.$validate(),
  ]).then(results => results.every(Boolean));
  if (!result) return;

  const payload = {
    name: state.name,
    description: state.description,
    config: {
      ...props.assistant.config,
      product_name: state.productName,
      business_facts: { ...state.businessFacts },
      feature_faq: state.features.conversationFaqs,
      feature_memory: state.features.memories,
      feature_citation: state.features.citations,
      feature_contact_attributes: state.features.contactAttributes,
    },
  };

  emit('submit', payload);
};

watch(
  () => props.assistant,
  newAssistant => {
    if (newAssistant) updateStateFromAssistant(newAssistant);
  },
  { immediate: true }
);
</script>

<template>
  <div class="flex flex-col gap-6">
    <div class="flex flex-col gap-2">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('CAPTAIN.ASSISTANTS.FORM.AVATAR.LABEL') }}
      </span>
      <div class="flex items-center gap-4">
        <Avatar
          :src="assistant.avatar_url"
          :name="state.name"
          :size="68"
          allow-upload
          @upload="emit('uploadAvatar', $event)"
          @delete="emit('deleteAvatar')"
        />
        <span class="text-sm text-n-slate-11">
          {{ t('CAPTAIN.ASSISTANTS.FORM.AVATAR.DESCRIPTION') }}
        </span>
      </div>
    </div>

    <Input
      v-model="state.name"
      :label="t('CAPTAIN.ASSISTANTS.FORM.NAME.LABEL')"
      :placeholder="t('CAPTAIN.ASSISTANTS.FORM.NAME.PLACEHOLDER')"
      :message="formErrors.name"
      :message-type="formErrors.name ? 'error' : 'info'"
    />

    <Input
      v-model="state.productName"
      :label="t('CAPTAIN.ASSISTANTS.FORM.PRODUCT_NAME.LABEL')"
      :placeholder="t('CAPTAIN.ASSISTANTS.FORM.PRODUCT_NAME.PLACEHOLDER')"
      :message="formErrors.productName"
      :message-type="formErrors.productName ? 'error' : 'info'"
    />

    <Editor
      v-model="state.description"
      :max-length="500"
      :label="t('CAPTAIN.ASSISTANTS.FORM.DESCRIPTION.LABEL')"
      :placeholder="t('CAPTAIN.ASSISTANTS.FORM.DESCRIPTION.PLACEHOLDER')"
      :message="formErrors.description"
      :message-type="formErrors.description ? 'error' : 'info'"
      class="z-0"
    />

    <section class="flex flex-col gap-4">
      <div class="flex flex-col gap-2">
        <h6 class="text-base font-medium text-n-slate-12">
          {{ t('CAPTAIN.ASSISTANTS.BUSINESS_FACTS.TITLE') }}
        </h6>
        <span class="text-sm text-n-slate-11">
          {{
            t('CAPTAIN.ASSISTANTS.BUSINESS_FACTS.DESCRIPTION', {
              assistantName: state.name,
            })
          }}
        </span>
      </div>
      <TextArea
        v-for="{ key, label, placeholder } in businessFactFields"
        :id="`business-fact-${key}`"
        :key="key"
        v-model="state.businessFacts[key]"
        :label="label"
        :placeholder="placeholder"
        :max-length="BUSINESS_FACT_MAX_LENGTH"
        show-character-count
        :message="
          v$.businessFacts[key].$error
            ? t('CAPTAIN.ASSISTANTS.BUSINESS_FACTS.TOO_LONG')
            : ''
        "
        :message-type="v$.businessFacts[key].$error ? 'error' : 'info'"
      />
    </section>

    <div class="flex flex-col gap-2">
      <label class="text-sm font-medium text-n-slate-12">
        {{ t('CAPTAIN.ASSISTANTS.FORM.FEATURES.TITLE') }}
      </label>
      <div class="flex flex-col gap-2">
        <label class="flex items-center gap-2 max-md:min-h-11">
          <input v-model="state.features.conversationFaqs" type="checkbox" />
          {{ t('CAPTAIN.ASSISTANTS.FORM.FEATURES.ALLOW_CONVERSATION_FAQS') }}
        </label>
        <label class="flex items-center gap-2 max-md:min-h-11">
          <input v-model="state.features.memories" type="checkbox" />
          {{ t('CAPTAIN.ASSISTANTS.FORM.FEATURES.ALLOW_MEMORIES') }}
        </label>
        <label class="flex items-center gap-2 max-md:min-h-11">
          <input v-model="state.features.citations" type="checkbox" />
          {{ t('CAPTAIN.ASSISTANTS.FORM.FEATURES.ALLOW_CITATIONS') }}
        </label>
        <label class="flex items-center gap-2 max-md:min-h-11">
          <input v-model="state.features.contactAttributes" type="checkbox" />
          {{ t('CAPTAIN.ASSISTANTS.FORM.FEATURES.ALLOW_CONTACT_ATTRIBUTES') }}
        </label>
      </div>
    </div>

    <div>
      <Button
        :label="t('CAPTAIN.ASSISTANTS.FORM.UPDATE')"
        @click="handleBasicInfoUpdate"
      />
    </div>
  </div>
</template>
