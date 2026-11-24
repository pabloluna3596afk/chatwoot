<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { useAccount } from 'dashboard/composables/useAccount';

const props = defineProps({
  connected: Boolean,
  attributes: { type: Object, default: null },
  loading: { type: Object, required: true },
  errors: { type: Object, required: true },
});
const emit = defineEmits(['navigate', 'retryConnections', 'retryAttributes']);
const { t } = useI18n();
const { accountScopedRoute } = useAccount();
const attributeConflicts = computed(() =>
  Object.entries(props.attributes?.results || {})
    .filter(([, result]) => result.status === 'conflict')
    .map(([key, result]) => ({ key, ...result }))
);
const attributeType = type =>
  t(`ATTRIBUTES_MGMT.ATTRIBUTE_TYPES.${type.toUpperCase()}`);
const rows = ['calendarios', 'mensajes', 'invitacion'];
</script>

<template>
  <section
    class="divide-y divide-n-weak rounded-xl border border-n-weak bg-n-card px-4"
  >
    <div class="flex flex-wrap items-center justify-between gap-3 py-4">
      <div class="min-w-0">
        <h3 class="text-body-main font-medium text-n-slate-12">
          {{ $t('INTEGRATION_SETTINGS.CALENDARS.GOOGLE') }}
        </h3>
        <Spinner v-if="loading.connections" />
        <p v-else role="status" class="text-body-main text-n-slate-11">
          {{
            $t(
              errors.connections
                ? 'INTEGRATION_SETTINGS.CALENDARS.LOAD_ERROR'
                : connected
                  ? 'CITAS_PANEL.CONNECTED'
                  : 'CITAS_PANEL.DISCONNECTED'
            )
          }}
        </p>
      </div>
      <Button
        v-if="errors.connections"
        intent="secondary"
        :label="$t('CALENDAR_ACTIVATION_KIT.RELOAD')"
        @click="emit('retryConnections')"
      />
      <RouterLink
        :to="accountScopedRoute('settings_integrations_calendars')"
        class="text-body-main text-n-blue-11 underline"
      >
        {{
          $t(
            connected
              ? 'CITAS_SETTINGS.MANAGE_CONNECTION'
              : 'CITAS_PANEL.RECONNECT'
          )
        }}
      </RouterLink>
    </div>
    <div
      v-for="row in rows"
      :key="row"
      class="flex flex-wrap items-center justify-between gap-3 py-4"
    >
      <div class="min-w-0 flex-1">
        <h3 class="text-body-main font-medium text-n-slate-12">
          {{ $t(`CITAS_PANEL.TABS.${row}`) }}
        </h3>
      </div>
      <Button
        intent="secondary"
        :label="
          $t('CITAS_PANEL.VIEW', { section: $t(`CITAS_PANEL.TABS.${row}`) })
        "
        @click="emit('navigate', row)"
      />
    </div>
    <div
      class="flex flex-col gap-2 py-4"
      data-testid="appointment-attributes-status"
    >
      <h3 class="text-body-main font-medium text-n-slate-12">
        {{ $t('CITAS_PANEL.ATTRIBUTES.TITLE') }}
      </h3>
      <Spinner v-if="loading.attributes" />
      <p
        v-else-if="errors.attributes"
        role="status"
        class="text-body-main text-n-slate-11"
      >
        {{ $t('CITAS_PANEL.SECTION_ERROR') }}
        <Button
          intent="secondary"
          :label="$t('CALENDAR_ACTIVATION_KIT.RELOAD')"
          @click="emit('retryAttributes')"
        />
      </p>
      <template v-else>
        <p class="text-body-main text-n-slate-11">
          {{
            !attributes || attributes.keys === null
              ? $t('CITAS_PANEL.ATTRIBUTES.NOT_PREPARED')
              : $t(
                  'CITAS_PANEL.ATTRIBUTES.ACTIVE',
                  attributes.enabled_keys.length
                )
          }}
        </p>
        <p
          v-for="conflict in attributeConflicts"
          :key="conflict.key"
          role="alert"
          class="text-body-main text-n-amber-11 break-words"
        >
          {{
            $t('CITAS_PANEL.ATTRIBUTES.CONFLICT', {
              key: conflict.key,
              actual: attributeType(conflict.actual_type),
              expected: attributeType(conflict.expected_type),
            })
          }}
        </p>
        <RouterLink
          v-if="attributeConflicts.length"
          :to="accountScopedRoute('attributes_list')"
          class="self-start text-body-main text-n-blue-11 underline"
        >
          {{ $t('CITAS_PANEL.ATTRIBUTES.MANAGE') }}
        </RouterLink>
      </template>
    </div>
  </section>
</template>
