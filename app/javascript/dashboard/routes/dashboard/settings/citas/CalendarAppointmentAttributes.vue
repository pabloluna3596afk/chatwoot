<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import CalendarAPI from 'dashboard/api/integrations/calendar';
import Button from 'dashboard/components-next/button/Button.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Label from 'dashboard/components-next/label/Label.vue';

const ATTRIBUTES = [
  { key: 'ultima_cita', type: 'datetime' },
  { key: 'proxima_cita', type: 'datetime' },
  { key: 'proxima_cita_titulo', type: 'text' },
  { key: 'total_citas', type: 'number' },
];
const STATUS_COLORS = { created: 'teal', reused: 'blue', conflict: 'amber' };
const { t } = useI18n();
const store = useStore();
const selected = ref(ATTRIBUTES.map(attribute => attribute.key));
const saved = ref(null);
const results = ref({});
const loading = ref(true);
const loadFailed = ref(false);
const saving = ref(false);
const dirty = computed(
  () => saved.value === null || selected.value.join() !== saved.value.join()
);
const hasConflicts = computed(() =>
  Object.values(results.value).some(result => result.status === 'conflict')
);
const canSave = computed(
  () =>
    !loading.value &&
    !loadFailed.value &&
    !saving.value &&
    (dirty.value || hasConflicts.value)
);
const apply = data => {
  selected.value = data.keys ?? ATTRIBUTES.map(attribute => attribute.key);
  saved.value = data.keys === null ? null : [...data.keys];
  results.value = data.results;
};
const toggle = (key, checked) => {
  const keys = checked
    ? [...selected.value, key]
    : selected.value.filter(value => value !== key);
  selected.value = ATTRIBUTES.map(attribute => attribute.key).filter(value =>
    keys.includes(value)
  );
};
const typeLabel = type =>
  t(`ATTRIBUTES_MGMT.ATTRIBUTE_TYPES.${type.toUpperCase()}`);
const conflictDetail = result =>
  t('CALENDAR_APPOINTMENT_ATTRIBUTES.CONFLICT_DETAIL', {
    expected: typeLabel(result.expected_type),
    actual: typeLabel(result.actual_type),
  });
const load = async () => {
  try {
    const { data } = await CalendarAPI.getAppointmentAttributes();
    apply(data);
  } catch {
    loadFailed.value = true;
    useAlert(t('CALENDAR_APPOINTMENT_ATTRIBUTES.LOAD_ERROR'));
  } finally {
    loading.value = false;
  }
};
const save = async () => {
  saving.value = true;
  try {
    const { data } = await CalendarAPI.updateAppointmentAttributes(
      selected.value
    );
    apply(data);
    await store.dispatch('attributes/get');
    useAlert(t('CALENDAR_APPOINTMENT_ATTRIBUTES.SAVED'));
  } catch (error) {
    useAlert(
      error.response?.data?.error ||
        t('CALENDAR_APPOINTMENT_ATTRIBUTES.SAVE_ERROR')
    );
  } finally {
    saving.value = false;
  }
};
onMounted(load);
</script>

<template>
  <section
    class="flex flex-col gap-4 p-4 border rounded-xl border-n-weak"
    data-testid="appointment-attributes"
  >
    <div>
      <h3 class="text-heading-1 text-n-slate-12">
        {{ $t('CALENDAR_APPOINTMENT_ATTRIBUTES.TITLE') }}
      </h3>
      <p class="mt-1 text-body-main text-n-slate-11">
        {{ $t('CALENDAR_APPOINTMENT_ATTRIBUTES.DESCRIPTION') }}
      </p>
    </div>
    <div class="flex flex-col gap-3">
      <div
        v-for="attribute in ATTRIBUTES"
        :key="attribute.key"
        class="flex flex-wrap items-center gap-2"
      >
        <label class="flex items-center gap-2 text-body-main text-n-slate-12">
          <Checkbox
            :model-value="selected.includes(attribute.key)"
            :disabled="loading || loadFailed || saving"
            :data-testid="`appointment-attribute-${attribute.key}`"
            @update:model-value="toggle(attribute.key, $event)"
          />
          {{
            $t(
              `CALENDAR_APPOINTMENT_ATTRIBUTES.ATTRIBUTES.${attribute.key}.NAME`
            )
          }}
        </label>
        <button
          v-tooltip.top="
            $t(
              `CALENDAR_APPOINTMENT_ATTRIBUTES.ATTRIBUTES.${attribute.key}.HELP`
            )
          "
          type="button"
          class="i-lucide-info size-4 text-n-slate-11"
          :aria-label="
            $t(
              `CALENDAR_APPOINTMENT_ATTRIBUTES.ATTRIBUTES.${attribute.key}.HELP`
            )
          "
        />
        <Label :label="typeLabel(attribute.type)" compact />
        <span class="text-xs text-n-slate-11">{{ attribute.key }}</span>
        <Label
          v-if="results[attribute.key]"
          :label="
            $t(
              `CALENDAR_APPOINTMENT_ATTRIBUTES.RESULT.${results[attribute.key].status}`
            )
          "
          :color="STATUS_COLORS[results[attribute.key].status]"
          :data-testid="`appointment-result-${attribute.key}`"
          compact
          role="status"
        />
        <p
          v-if="results[attribute.key]?.status === 'conflict'"
          class="basis-full text-body-main text-n-amber-11"
        >
          {{ conflictDetail(results[attribute.key]) }}
        </p>
      </div>
    </div>
    <p class="text-body-main text-n-slate-11">
      {{ $t('CALENDAR_APPOINTMENT_ATTRIBUTES.DISABLE_HINT') }}
    </p>
    <div>
      <Button
        type="button"
        :label="$t('CALENDAR_APPOINTMENT_ATTRIBUTES.UPDATE')"
        :disabled="!canSave"
        :is-loading="saving"
        data-testid="appointment-attributes-save"
        @click="save"
      />
    </div>
  </section>
</template>
