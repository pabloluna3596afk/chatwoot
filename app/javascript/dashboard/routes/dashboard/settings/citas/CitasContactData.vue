<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CitasStepRow from './CitasStepRow.vue';

const props = defineProps({
  attributes: { type: Object, default: null },
  loading: Boolean,
  error: Boolean,
  expanded: Boolean,
});
const emit = defineEmits(['toggle', 'retry']);
const { t } = useI18n();
const { accountScopedRoute } = useAccount();
const copied = ref('');
const attributeType = type => {
  if (type === 'text') return t('ATTRIBUTES_MGMT.ATTRIBUTE_TYPES.TEXT');
  if (type === 'datetime') return t('ATTRIBUTES_MGMT.ATTRIBUTE_TYPES.DATETIME');
  return t('ATTRIBUTES_MGMT.ATTRIBUTE_TYPES.NUMBER');
};
const attributeName = key => {
  switch (key) {
    case 'ultima_cita':
      return t('CALENDAR_APPOINTMENT_ATTRIBUTES.ATTRIBUTES.ultima_cita.NAME');
    case 'proxima_cita':
      return t('CALENDAR_APPOINTMENT_ATTRIBUTES.ATTRIBUTES.proxima_cita.NAME');
    case 'proxima_cita_titulo':
      return t(
        'CALENDAR_APPOINTMENT_ATTRIBUTES.ATTRIBUTES.proxima_cita_titulo.NAME'
      );
    case 'total_citas':
      return t('CALENDAR_APPOINTMENT_ATTRIBUTES.ATTRIBUTES.total_citas.NAME');
    case 'estado_proxima_cita':
      return t(
        'CALENDAR_APPOINTMENT_ATTRIBUTES.ATTRIBUTES.estado_proxima_cita.NAME'
      );
    default:
      return t(
        'CALENDAR_APPOINTMENT_ATTRIBUTES.ATTRIBUTES.citas_canceladas.NAME'
      );
  }
};
const copiedLabel = key =>
  key === copied.value ? t('CITAS_SCREEN.COPIED') : t('CITAS_SCREEN.COPY');
const keys = computed(() => props.attributes?.enabled_keys || []);
const conflicts = computed(() =>
  Object.entries(props.attributes?.results || {}).filter(
    ([, result]) => result.status === 'conflict'
  )
);
const example = key => {
  switch (key) {
    case 'ultima_cita':
      return t('CITAS_SCREEN.EXAMPLE_ULTIMA_CITA');
    case 'proxima_cita':
      return t('CITAS_SCREEN.EXAMPLE_PROXIMA_CITA');
    case 'proxima_cita_titulo':
      return t('CITAS_SCREEN.EXAMPLE_PROXIMA_CITA_TITULO');
    case 'total_citas':
      return t('CITAS_SCREEN.EXAMPLE_TOTAL_CITAS');
    case 'estado_proxima_cita':
      return t('CITAS_SCREEN.EXAMPLE_ESTADO_PROXIMA_CITA');
    default:
      return t('CITAS_SCREEN.EXAMPLE_CITAS_CANCELADAS');
  }
};
const copy = async key => {
  try {
    await navigator.clipboard.writeText(key);
  } catch {
    const input = document.createElement('textarea');
    input.value = key;
    input.setAttribute('readonly', '');
    input.className = 'fixed -start-[9999px]';
    document.body.appendChild(input);
    input.select();
    let succeeded = false;
    try {
      succeeded = document.execCommand('copy');
    } catch {
      succeeded = false;
    }
    input.remove();
    if (!succeeded) {
      useAlert(t('CITAS_SCREEN.COPY_ERROR'));
      return;
    }
  }
  copied.value = key;
  window.setTimeout(() => {
    if (copied.value === key) copied.value = '';
  }, 1500);
};
</script>

<template>
  <CitasStepRow
    icon="plain"
    :title="$t('CITAS_SCREEN.CONTACT_DATA')"
    :value="
      loading
        ? ''
        : $t('CITAS_SCREEN.CONTACT_VALUE', keys.length, { n: keys.length })
    "
    :expanded="expanded"
    data-testid="citas-contact-data"
  >
    <template #actions="{ contentId }">
      <Button
        intent="tertiary"
        size="sm"
        :label="
          expanded ? $t('CITAS_SCREEN.HIDE_DATA') : $t('CITAS_SCREEN.VIEW_DATA')
        "
        :aria-expanded="expanded"
        :aria-controls="contentId"
        @click="emit('toggle')"
      />
    </template>
    <Spinner v-if="loading" />
    <div v-else-if="error" role="alert" class="text-body-main text-n-ruby-11">
      {{ $t('CITAS_PANEL.SECTION_ERROR') }}
      <Button
        intent="secondary"
        :label="$t('CALENDAR_ACTIVATION_KIT.RELOAD')"
        @click="emit('retry')"
      />
    </div>
    <template v-else>
      <p class="m-0 text-body-main text-n-slate-11">
        {{ $t('CITAS_SCREEN.CONTACT_HELP') }}
      </p>
      <p
        v-for="[key, result] in conflicts"
        :key="key"
        class="m-0 text-body-main text-n-amber-11"
      >
        {{
          $t('CITAS_PANEL.ATTRIBUTES.CONFLICT', {
            key: attributeName(key),
            actual: attributeType(result.actual_type),
            expected: attributeType(result.expected_type),
          })
        }}
        <RouterLink
          :to="accountScopedRoute('attributes_list')"
          class="underline"
        >
          {{ $t('CITAS_PANEL.ATTRIBUTES.MANAGE') }}
        </RouterLink>
      </p>
      <ul class="m-0 flex list-none flex-col gap-2 p-0">
        <li
          v-for="key in keys"
          :key="key"
          class="flex min-w-0 flex-wrap items-center gap-x-2 gap-y-1"
        >
          <span class="text-body-main text-n-slate-12">{{
            attributeName(key)
          }}</span>
          <code dir="ltr" class="text-body-main text-n-slate-11">{{
            key
          }}</code>
          <span class="text-body-main text-n-slate-11">{{
            $t('CITAS_SCREEN.EXAMPLE', { value: example(key) })
          }}</span>
          <Button
            intent="link"
            size="sm"
            :label="copiedLabel(key)"
            @click="copy(key)"
          />
        </li>
      </ul>
      <p class="m-0 text-body-main text-n-slate-11">
        {{ $t('CITAS_SCREEN.CONTACT_GROUP') }}
      </p>
    </template>
  </CitasStepRow>
</template>
