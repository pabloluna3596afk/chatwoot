<script setup>
import AuthSplitLayout from '../../../components/Auth/AuthSplitLayout.vue';
import SignupForm from './components/Signup/Form.vue';
</script>

<template>
  <AuthSplitLayout
    :title="$t('REGISTER.MARKETING.TITLE')"
    :subtitle="$t('REGISTER.MARKETING.SUBTITLE')"
  >
    <header class="mb-8 text-center">
      <h2 class="text-3xl font-bold tracking-tight text-n-slate-12 xl:text-4xl">
        {{ $t('REGISTER.TITLE') }}
      </h2>
      <p class="mt-3 text-sm text-n-slate-11">
        {{ $t('REGISTER.HAVE_AN_ACCOUNT') }}
        <router-link
          to="/app/login"
          class="font-medium text-n-brand hover:underline focus-visible:underline"
        >
          {{ $t('REGISTER.SIGN_IN') }}
        </router-link>
      </p>
    </header>
    <SignupForm />
  </AuthSplitLayout>
</template>
