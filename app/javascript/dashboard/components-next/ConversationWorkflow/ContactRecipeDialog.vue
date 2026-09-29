<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  useStore,
  useFunctionGetter,
  useMapGetter,
} from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import OutlinedSelectField from 'dashboard/components-next/CustomAttributes/OutlinedSelectField.vue';
import AutomationActionWhatsAppTemplateInput from 'dashboard/components/widgets/AutomationActionWhatsAppTemplateInput.vue';
import { convertToAttributeSlug } from 'dashboard/helper/commons';
import AutomationsAPI from 'dashboard/api/automation';

// One compact dialog per contact-based recipe (cumpleaños, aniversario,
// recompra, reactivar inactivos) — no wizard, no page navigation. Mirrors
// AttributeRequirementDialog.vue's "pick-or-create" attribute pattern and
// reuses AutomationActionWhatsAppTemplateInput wholesale, so the inbox +
// template + variable pickers here are the exact same UI already proven in
// the automation action editor, not a re-implementation.
const CREATE_NEW_ID = '__create_new__';
const REACH_DEBOUNCE_MS = 400;

const store = useStore();
const { t } = useI18n();

const dialogRef = ref(null);
const preset = ref(null);
const isSaving = ref(false);

const selectedAttributeId = ref(CREATE_NEW_ID);
const newAttributeName = ref('');
const selectedDayOptionId = ref('');
const templateParams = ref({});
const testModeEnabled = ref(false);
const testModeLabel = ref('');
const reachCount = ref(null);
const isLoadingReach = ref(false);
let reachDebounceTimer = null;

const needsAttribute = computed(
  () => preset.value?.dateSource === 'contact_attribute'
);

const contactDateAttributes = useFunctionGetter(
  'attributes/getAttributesByModel',
  'contact_attribute'
);

const matchingAttributes = computed(() =>
  (contactDateAttributes.value || []).filter(
    attr => attr.attribute_display_type === 'date'
  )
);

const attributeSelectOptions = computed(() => [
  {
    id: CREATE_NEW_ID,
    name: t('AUTOMATION.ATTRIBUTE_REQUIREMENT.CREATE_NEW_OPTION'),
  },
  ...matchingAttributes.value.map(attr => ({
    id: attr.attribute_key,
    name: attr.attribute_display_name,
  })),
]);

const selectedAttributeOption = computed(
  () =>
    attributeSelectOptions.value.find(
      o => o.id === selectedAttributeId.value
    ) || attributeSelectOptions.value[0]
);

const isCreatingNewAttribute = computed(
  () => needsAttribute.value && selectedAttributeId.value === CREATE_NEW_ID
);

const newAttributeKey = computed(() =>
  convertToAttributeSlug(newAttributeName.value)
);

const dayOptionLabel = option =>
  option.labelCount != null
    ? t(option.labelKey, { count: option.labelCount }, option.labelCount)
    : t(option.labelKey);

const selectedDayOption = computed(() =>
  (preset.value?.dayOptions || []).find(o => o.id === selectedDayOptionId.value)
);

const labels = useMapGetter('labels/getLabels');
const labelSelectOptions = computed(() =>
  (labels.value || []).map(label => ({ id: label.title, name: label.title }))
);

const canConfirm = computed(() => {
  if (!preset.value || !selectedDayOption.value) return false;
  if (!templateParams.value.name || !templateParams.value.inbox_id)
    return false;
  if (isCreatingNewAttribute.value) {
    return (
      newAttributeName.value.trim().length > 0 &&
      newAttributeKey.value.length > 0
    );
  }
  if (testModeEnabled.value && !testModeLabel.value) return false;
  return true;
});

// null while the schedule isn't buildable yet (no day option, no inbox
// picked, or the attribute still needs to be created — a brand-new
// attribute has no data yet, so previewing it would always read 0).
const scheduleForPreview = computed(() => {
  if (!preset.value || !selectedDayOption.value) return null;
  if (!templateParams.value.inbox_id) return null;
  if (isCreatingNewAttribute.value) return null;

  const schedule = {
    kind: 'contact_date',
    date_source: preset.value.dateSource,
    recurrence: preset.value.recurrence,
    relative_to: selectedDayOption.value.relativeTo,
    days: selectedDayOption.value.days,
    target_inbox_id: templateParams.value.inbox_id,
  };
  if (needsAttribute.value) schedule.attribute_key = selectedAttributeId.value;
  return schedule;
});

watch(
  scheduleForPreview,
  schedule => {
    clearTimeout(reachDebounceTimer);
    if (!schedule) {
      reachCount.value = null;
      return;
    }
    reachDebounceTimer = setTimeout(async () => {
      isLoadingReach.value = true;
      try {
        const { data } = await AutomationsAPI.reachPreview(schedule);
        reachCount.value = data.count;
      } catch (error) {
        reachCount.value = null;
      } finally {
        isLoadingReach.value = false;
      }
    }, REACH_DEBOUNCE_MS);
  },
  { deep: true }
);

const open = p => {
  preset.value = p;
  selectedDayOptionId.value = p.dayOptions?.[0]?.id || '';
  selectedAttributeId.value = CREATE_NEW_ID;
  newAttributeName.value = p.attributeSuggestion
    ? t(p.attributeSuggestion.attributeDisplayNameKey)
    : '';
  templateParams.value = {};
  testModeEnabled.value = false;
  testModeLabel.value = '';
  reachCount.value = null;
  dialogRef.value?.open();
};

const onCancel = () => {
  preset.value = null;
};

const onConfirm = async () => {
  isSaving.value = true;
  try {
    let attributeKey = null;
    if (needsAttribute.value) {
      if (isCreatingNewAttribute.value) {
        await store.dispatch('attributes/create', {
          attribute_display_name: newAttributeName.value.trim(),
          attribute_key: newAttributeKey.value,
          attribute_model: 'contact_attribute',
          attribute_display_type: 'date',
          category: '',
        });
        attributeKey = newAttributeKey.value;
      } else {
        attributeKey = selectedAttributeId.value;
      }
    }

    const dayOption = selectedDayOption.value;
    const schedule = {
      kind: 'contact_date',
      date_source: preset.value.dateSource,
      recurrence: preset.value.recurrence,
      relative_to: dayOption.relativeTo,
      days: dayOption.days,
      target_inbox_id: templateParams.value.inbox_id,
    };
    if (attributeKey) schedule.attribute_key = attributeKey;
    if (testModeEnabled.value && testModeLabel.value) {
      schedule.test_mode_label = testModeLabel.value;
    }

    await store.dispatch('automations/create', {
      name: t(preset.value.nameKey),
      description: t(preset.value.descriptionKey),
      event_name: 'time_triggered',
      active: true,
      schedule,
      conditions: [],
      actions: [
        {
          action_name: 'send_whatsapp_template',
          action_params: [templateParams.value],
        },
      ],
      preset_id: preset.value.id,
    });
    useAlert(t('BUSINESS_RULES.CONTACT_PRESETS.ACTIVATE_SUCCESS'));
    preset.value = null;
    dialogRef.value?.close();
  } catch (error) {
    useAlert(t('BUSINESS_RULES.CONTACT_PRESETS.ACTIVATE_ERROR'));
  } finally {
    isSaving.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    width="md"
    :title="preset ? t(preset.nameKey) : ''"
    :description="preset ? t(preset.descriptionKey) : ''"
    :confirm-button-label="t('BUSINESS_RULES.CONTACT_PRESETS.ACTIVATE')"
    :cancel-button-label="t('AUTOMATION.ATTRIBUTE_REQUIREMENT.CANCEL')"
    :is-loading="isSaving"
    :disable-confirm-button="!canConfirm"
    @confirm="onConfirm"
    @close="onCancel"
  >
    <div v-if="preset" class="flex flex-col gap-4">
      <div v-if="needsAttribute" class="flex flex-col gap-2">
        <OutlinedSelectField
          :label="t('BUSINESS_RULES.CONTACT_PRESETS.ATTRIBUTE_LABEL')"
          :options="attributeSelectOptions"
          :selected-item="selectedAttributeOption"
          @select="option => (selectedAttributeId = option.id)"
        />
        <Input
          v-if="isCreatingNewAttribute"
          v-model="newAttributeName"
          :label="t('AUTOMATION.ATTRIBUTE_REQUIREMENT.NEW_NAME_LABEL')"
          :message="
            newAttributeKey
              ? `${t('AUTOMATION.ATTRIBUTE_REQUIREMENT.KEY_PREVIEW')}: ${newAttributeKey}`
              : ''
          "
        />
      </div>

      <div class="flex flex-col gap-2">
        <label class="mb-0 text-xs font-medium text-n-slate-12">
          {{ t('BUSINESS_RULES.CONTACT_PRESETS.WHEN_LABEL') }}
        </label>
        <div class="flex flex-wrap gap-2">
          <Button
            v-for="option in preset.dayOptions"
            :key="option.id"
            sm
            :solid="selectedDayOptionId === option.id"
            :faded="selectedDayOptionId !== option.id"
            :label="dayOptionLabel(option)"
            @click="selectedDayOptionId = option.id"
          />
        </div>
      </div>

      <AutomationActionWhatsAppTemplateInput v-model="templateParams" />

      <p v-if="scheduleForPreview" class="m-0 text-xs text-n-slate-11">
        {{
          isLoadingReach
            ? t('BUSINESS_RULES.CONTACT_PRESETS.REACH_LOADING')
            : t(
                'BUSINESS_RULES.CONTACT_PRESETS.REACH_COUNT',
                { count: reachCount ?? 0 },
                reachCount ?? 0
              )
        }}
      </p>
      <p v-else-if="isCreatingNewAttribute" class="m-0 text-xs text-n-slate-11">
        {{ t('BUSINESS_RULES.CONTACT_PRESETS.REACH_UNKNOWN_NEW_ATTRIBUTE') }}
      </p>

      <div class="flex flex-col gap-2 pt-2 border-t border-n-weak">
        <div class="flex items-center gap-2">
          <Switch v-model="testModeEnabled" />
          <span class="text-xs text-n-slate-11">
            {{ t('BUSINESS_RULES.CONTACT_PRESETS.TEST_MODE') }}
          </span>
        </div>
        <OutlinedSelectField
          v-if="testModeEnabled"
          :label="t('BUSINESS_RULES.CONTACT_PRESETS.TEST_MODE_LABEL_PICKER')"
          :options="labelSelectOptions"
          :selected-item="{ id: testModeLabel, name: testModeLabel }"
          @select="option => (testModeLabel = option.id)"
        />
      </div>
    </div>
  </Dialog>
</template>
