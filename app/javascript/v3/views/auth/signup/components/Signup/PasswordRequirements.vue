<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  password: { type: String, default: '' },
});
const MIN_PASSWORD_LENGTH = 6;
const SPECIAL_CHAR_REGEX = /[!@#$%^&*()_+\-=[\]{}|'"/\\.,`<>:;?~]/;

const { t } = useI18n();

const requirements = computed(() => {
  const password = props.password || '';
  return [
    {
      id: 'length',
      met: password.length >= MIN_PASSWORD_LENGTH,
      label: t('REGISTER.PASSWORD.REQUIREMENTS_LENGTH', {
        min: MIN_PASSWORD_LENGTH,
      }),
    },
    {
      id: 'uppercase',
      met: /[A-Z]/.test(password),
      label: t('REGISTER.PASSWORD.REQUIREMENTS_UPPERCASE'),
    },
    {
      id: 'lowercase',
      met: /[a-z]/.test(password),
      label: t('REGISTER.PASSWORD.REQUIREMENTS_LOWERCASE'),
    },
    {
      id: 'number',
      met: /[0-9]/.test(password),
      label: t('REGISTER.PASSWORD.REQUIREMENTS_NUMBER'),
    },
    {
      id: 'special',
      met: SPECIAL_CHAR_REGEX.test(password),
      label: t('REGISTER.PASSWORD.REQUIREMENTS_SPECIAL'),
    },
  ];
});
</script>

<template>
  <div class="mt-3 w-full text-xs">
    <ul role="list" class="grid grid-cols-1 gap-1.5 sm:grid-cols-2">
      <li
        v-for="item in requirements"
        :key="item.id"
        class="flex gap-1.5 items-start"
      >
        <Icon
          class="flex-none w-3 mt-0.5"
          aria-hidden="true"
          :icon="item.met ? 'i-lucide-circle-check-big' : 'i-lucide-circle'"
          :class="item.met ? 'text-n-teal-10' : 'text-n-slate-10'"
        />
        <span :class="item.met ? 'text-n-slate-11' : 'text-n-slate-10'">
          {{ item.label }}
        </span>
      </li>
    </ul>
  </div>
</template>
