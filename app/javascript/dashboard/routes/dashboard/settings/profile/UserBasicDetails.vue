<script>
import { useAlert } from 'dashboard/composables';
import FormInput from 'dashboard/components-next/input/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import { useVuelidate } from '@vuelidate/core';
import { required, minLength, email } from '@vuelidate/validators';
export default {
  components: {
    NextButton,
    FormInput,
  },
  props: {
    name: {
      type: String,
      default: '',
    },
    email: {
      type: String,
      default: '',
    },
    displayName: {
      type: String,
      default: '',
    },
    emailEnabled: {
      type: Boolean,
      default: false,
    },
  },
  emits: ['updateUser'],
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    return {
      userName: this.name,
      userDisplayName: this.displayName,
      userEmail: this.email,
    };
  },
  validations: {
    userName: {
      required,
      minLength: minLength(1),
    },
    userDisplayName: {},
    userEmail: {
      required,
      email,
    },
  },
  watch: {
    name: {
      handler(value) {
        this.userName = value;
      },
      immediate: true,
    },
    displayName: {
      handler(value) {
        this.userDisplayName = value;
      },
      immediate: true,
    },
    email: {
      handler(value) {
        this.userEmail = value;
      },
      immediate: true,
    },
  },
  methods: {
    async updateUser() {
      this.v$.$touch();
      if (this.v$.$invalid) {
        useAlert(this.$t('PROFILE_SETTINGS.FORM.ERROR'));
        return;
      }
      this.$emit('updateUser', {
        name: this.userName,
        displayName: this.userDisplayName,
        email: this.userEmail,
      });
    },
  },
};
</script>

<template>
  <form class="flex flex-col gap-4" @submit.prevent="updateUser('profile')">
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
    <div>
      <NextButton type="submit" :label="$t('PROFILE_SETTINGS.BTN_TEXT')" />
    </div>
  </form>
</template>
