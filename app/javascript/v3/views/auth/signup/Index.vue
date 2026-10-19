<script setup>
import AuthSplitLayout from '../../../components/Auth/AuthSplitLayout.vue';
import SignupForm from './components/Signup/Form.vue';
import AuthStepHeader from '../../../components/Auth/AuthStepHeader.vue';
import { AUTH_LINK_CLASS } from '../../../components/Auth/authStyles';
</script>

<template>
  <AuthSplitLayout
    :title="$t('REGISTER.MARKETING.TITLE')"
    :subtitle="$t('REGISTER.MARKETING.SUBTITLE')"
    onboarding
  >
    <AuthStepHeader
      :title="$t('REGISTER.TITLE')"
      :step-name="$t('REGISTER.TITLE')"
      :current="1"
    >
      {{ $t('REGISTER.HAVE_AN_ACCOUNT') }}
      <router-link to="/app/login" :class="AUTH_LINK_CLASS">
        {{ $t('REGISTER.SIGN_IN') }}
      </router-link>
    </AuthStepHeader>
    <SignupForm />
  </AuthSplitLayout>
</template>
