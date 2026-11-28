<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import FormInput from 'dashboard/components-next/input/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import { useVuelidate } from '@vuelidate/core';
import {
  required,
  requiredIf,
  minLength,
  email as emailValidator,
} from '@vuelidate/validators';

const props = defineProps({
  name: { type: String, default: '' },
  email: { type: String, default: '' },
  displayName: { type: String, default: '' },
  emailEnabled: { type: Boolean, default: false },
});
const emit = defineEmits(['updateUser']);
const { t } = useI18n();
const userName = ref(props.name);
const userDisplayName = ref(props.displayName);
const userEmail = ref(props.email);
const currentPassword = ref('');
const isEmailChanged = computed(
  () =>
    props.emailEnabled &&
    userEmail.value.trim().toLowerCase() !== props.email.toLowerCase()
);
const rules = computed(() => ({
  userName: { required, minLength: minLength(1) },
  userDisplayName: {},
  userEmail: { required, email: emailValidator },
  currentPassword: { required: requiredIf(isEmailChanged.value) },
}));
const v$ = useVuelidate(rules, {
  userName,
  userDisplayName,
  userEmail,
  currentPassword,
});

watch(
  () => props.name,
  value => {
    userName.value = value;
  }
);
watch(
  () => props.displayName,
  value => {
    userDisplayName.value = value;
  }
);
watch(
  () => props.email,
  value => {
    userEmail.value = value;
  }
);
watch(isEmailChanged, () => {
  currentPassword.value = '';
  v$.value.currentPassword.$reset();
});

const updateUser = () => {
  v$.value.$touch();
  if (v$.value.$invalid) {
    useAlert(t('PROFILE_SETTINGS.FORM.ERROR'));
    return;
  }
  emit('updateUser', {
    name: userName.value,
    displayName: userDisplayName.value,
    email: userEmail.value,
    currentPassword: isEmailChanged.value ? currentPassword.value : undefined,
  });
};
</script>

<template>
  <form class="flex flex-col gap-4" @submit.prevent="updateUser">
    <FormInput
      v-model="userName"
      class="sm:!gap-0 sm:pb-0.5 sm:[&>label]:!mb-0"
      custom-input-class="!rounded-xl !py-1.5 !h-10"
      :message-type="v$.userName.$error ? 'error' : 'info'"
      :label="$t('PROFILE_SETTINGS.FORM.NAME.LABEL')"
      :placeholder="$t('PROFILE_SETTINGS.FORM.NAME.PLACEHOLDER')"
      :message="`${
        v$.userName.$error ? $t('PROFILE_SETTINGS.FORM.NAME.ERROR') : ''
      }`"
      @input="v$.userName.$touch"
      @blur="v$.userName.$touch"
    />
    <FormInput
      v-model="userDisplayName"
      class="sm:!gap-0 sm:pb-0.5 sm:[&>label]:!mb-0"
      custom-input-class="!rounded-xl !py-1.5 !h-10"
      :message-type="v$.userDisplayName.$error ? 'error' : 'info'"
      :label="$t('PROFILE_SETTINGS.FORM.DISPLAY_NAME.LABEL')"
      :placeholder="$t('PROFILE_SETTINGS.FORM.DISPLAY_NAME.PLACEHOLDER')"
      :message="`${
        v$.userDisplayName.$error
          ? $t('PROFILE_SETTINGS.FORM.DISPLAY_NAME.ERROR')
          : ''
      }`"
      @input="v$.userDisplayName.$touch"
      @blur="v$.userDisplayName.$touch"
    />
    <FormInput
      v-if="emailEnabled"
      v-model="userEmail"
      class="sm:!gap-0 sm:pb-0.5 sm:[&>label]:!mb-0"
      custom-input-class="!rounded-xl !py-1.5 !h-10"
      :message-type="v$.userEmail.$error ? 'error' : 'info'"
      :label="$t('PROFILE_SETTINGS.FORM.EMAIL.LABEL')"
      :placeholder="$t('PROFILE_SETTINGS.FORM.EMAIL.PLACEHOLDER')"
      :message="`${
        v$.userEmail.$error ? $t('PROFILE_SETTINGS.FORM.EMAIL.ERROR') : ''
      }`"
      @input="v$.userEmail.$touch"
      @blur="v$.userEmail.$touch"
    />
    <FormInput
      v-if="isEmailChanged"
      v-model="currentPassword"
      type="password"
      autocomplete="current-password"
      class="sm:!gap-0 sm:pb-0.5 sm:[&>label]:!mb-0"
      custom-input-class="!rounded-xl !py-1.5 !h-10"
      :message-type="v$.currentPassword.$error ? 'error' : 'info'"
      :label="$t('PROFILE_SETTINGS.FORM.CURRENT_PASSWORD.LABEL')"
      :placeholder="$t('PROFILE_SETTINGS.FORM.CURRENT_PASSWORD.PLACEHOLDER')"
      :message="
        v$.currentPassword.$error
          ? $t('PROFILE_SETTINGS.FORM.CURRENT_PASSWORD.ERROR')
          : ''
      "
      @input="v$.currentPassword.$touch"
      @blur="v$.currentPassword.$touch"
    />
    <div>
      <NextButton type="submit" :label="$t('PROFILE_SETTINGS.BTN_TEXT')" />
    </div>
  </form>
</template>
