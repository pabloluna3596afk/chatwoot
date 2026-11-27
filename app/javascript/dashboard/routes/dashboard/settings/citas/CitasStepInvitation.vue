<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import CitasStepRow from './CitasStepRow.vue';
import CalendarInvitationSettings from './CalendarInvitationSettings.vue';

const props = defineProps({ expanded: Boolean, disabled: Boolean });
const emit = defineEmits(['toggle', 'dirty']);
const { t } = useI18n();
const isDefault = ref(true);
const hasState = ref(false);
const value = computed(() => {
  if (props.disabled || !hasState.value) return '';
  return isDefault.value
    ? t('CITAS_SCREEN.INVITATION_DEFAULT')
    : t('CITAS_SCREEN.INVITATION_CUSTOM');
});
const onState = state => {
  isDefault.value = state.usingDefault;
  hasState.value = true;
};
</script>

<template>
  <CitasStepRow
    icon="3"
    :title="$t('CITAS_SCREEN.STEP_INVITATION')"
    :value="value"
    :expanded="expanded"
    :disabled="disabled"
    data-testid="citas-invitation-step"
  >
    <template #actions="{ contentId }">
      <Button
        intent="tertiary"
        size="sm"
        :disabled="disabled"
        :label="expanded ? $t('CITAS_SCREEN.CLOSE') : $t('CITAS_SCREEN.EDIT')"
        :aria-expanded="expanded"
        :aria-controls="contentId"
        @click="emit('toggle')"
      />
    </template>
    <p v-if="disabled" class="m-0 text-body-main text-n-slate-11">
      {{ $t('CITAS_SCREEN.AVAILABLE_WITH_GOOGLE') }}
    </p>
    <CalendarInvitationSettings
      v-else
      @dirty="emit('dirty', $event)"
      @state="onState"
    />
  </CitasStepRow>
</template>
