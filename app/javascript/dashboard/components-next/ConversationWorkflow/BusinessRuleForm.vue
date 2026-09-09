<script setup>
import { computed, reactive, ref, watch, nextTick, h, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  useStore,
  useMapGetter,
  useStoreGetters,
} from 'dashboard/composables/store';
import { useOperators } from 'dashboard/components-next/filter/operators';
import ConditionRow from 'dashboard/components-next/filter/ConditionRow.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import useAutomationValues from 'dashboard/composables/useAutomationValues';
import {
  GUARD_RULE_TYPES,
  emptyConfigForType,
  emptyCondition,
} from 'dashboard/components-next/ConversationWorkflow/businessRulesConstants';
import AttributeRequirementPicker from 'dashboard/components-next/ConversationWorkflow/AttributeRequirementPicker.vue';
import AttributeScopeSwitch from 'dashboard/components-next/ConversationWorkflow/AttributeScopeSwitch.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Input from 'dashboard/components-next/Input/Input.vue';
import OutlinedSelectField from 'dashboard/components-next/CustomAttributes/OutlinedSelectField.vue';
import { AUTOMATIONS } from 'dashboard/routes/dashboard/settings/automation/constants';
import {
  generateCustomAttributeTypes,
  generateCustomAttributes,
  getAttributes,
} from 'dashboard/helper/automationHelper';

const props = defineProps({
  modelValue: {
    type: Object,
    default: null,
  },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const store = useStore();
const getters = useStoreGetters();
const { operators } = useOperators();
const { getConditionDropdownValues } = useAutomationValues();
const labels = useMapGetter('labels/getLabels');
const conversationAttributes = useMapGetter(
  'attributes/getConversationAttributes'
);
const contactAttributes = useMapGetter('attributes/getContactAttributes');

const STATUS_OPTIONS = ['open', 'resolved', 'pending', 'snoozed'];
const INPUT_TYPE_MAP = {
  multi_select: 'multiSelect',
  search_select: 'searchSelect',
  plain_text: 'plainText',
  comma_separated_plain_text: 'plainText',
  date: 'date',
  datetime: 'datetime',
};
const MESSAGE_KEYS = new Set([
  'message_type',
  'content',
  'private_note',
  'email',
]);

const syncing = ref(false);

const draft = reactive({
  id: null,
  name: '',
  type: GUARD_RULE_TYPES[0],
  enabled: true,
  preset_id: null,
  conditions: [],
  config: emptyConfigForType(GUARD_RULE_TYPES[0]),
});

const ensureArrays = () => {
  [
    'attribute_keys',
    'contact_attribute_keys',
    'attribute_category_keys',
    'contact_attribute_category_keys',
    'require_attribute_keys',
    'require_contact_attribute_keys',
    'require_attribute_category_keys',
    'require_contact_attribute_category_keys',
    'when_values',
    'statuses',
  ].forEach(key => {
    if (!Array.isArray(draft.config[key])) draft.config[key] = [];
  });
  if (!Array.isArray(draft.conditions)) draft.conditions = [];
};

const hydrateLegacyWhenCondition = config => {
  if (!config?.when_attribute) return [];
  const customAttributeType =
    config.when_attribute_model === 'contact'
      ? 'contact_attribute'
      : 'conversation_attribute';
  return [
    {
      attribute_key: config.when_attribute,
      filter_operator: 'equal_to',
      values: Array.isArray(config.when_values) ? [...config.when_values] : [],
      query_operator: null,
      custom_attribute_type: customAttributeType,
    },
  ];
};

const applyModel = value => {
  if (!value) return;
  syncing.value = true;
  draft.id = value.id;
  draft.name = value.name || '';
  draft.type = value.type || GUARD_RULE_TYPES[0];
  draft.enabled = value.enabled !== false;
  draft.preset_id = value.preset_id ?? null;
  draft.config = {
    ...emptyConfigForType(draft.type),
    ...(value.config || {}),
  };
  const incomingConditions = Array.isArray(value.conditions)
    ? JSON.parse(JSON.stringify(value.conditions))
    : [];
  let nextConditions = [];
  if (incomingConditions.length > 0) {
    nextConditions = incomingConditions;
  } else if (draft.type === 'if_attribute_then_require') {
    nextConditions = hydrateLegacyWhenCondition(draft.config);
  }
  draft.conditions = nextConditions;
  ensureArrays();
  nextTick(() => {
    syncing.value = false;
  });
};

watch(
  () => props.modelValue,
  value => applyModel(value),
  { immediate: true, deep: true }
);

watch(
  draft,
  () => {
    if (syncing.value) return;
    emit('update:modelValue', {
      id: draft.id,
      name: draft.name,
      type: draft.type,
      enabled: draft.enabled,
      preset_id: draft.preset_id,
      conditions: draft.conditions.map(condition => ({ ...condition })),
      config: { ...draft.config },
    });
  },
  { deep: true }
);

onMounted(() => {
  store.dispatch('attributes/get');
  store.dispatch('labels/get');
  store.dispatch('agents/get');
  store.dispatch('teams/get');
  store.dispatch('inboxes/get');
});

const automationTypes = computed(() => {
  const types = JSON.parse(JSON.stringify(AUTOMATIONS));
  const conversationCustomAttributesRaw = getters[
    'attributes/getAttributesByModel'
  ].value('conversation_attribute');
  const contactCustomAttributesRaw =
    getters['attributes/getAttributesByModel'].value('contact_attribute');
  const manifested = generateCustomAttributes(
    generateCustomAttributeTypes(
      conversationCustomAttributesRaw,
      'conversation_attribute'
    ),
    generateCustomAttributeTypes(
      contactCustomAttributesRaw,
      'contact_attribute'
    ),
    t('AUTOMATION.CONDITION.CONVERSATION_CUSTOM_ATTR_LABEL'),
    t('AUTOMATION.CONDITION.CONTACT_CUSTOM_ATTR_LABEL')
  );
  const base = (types.conversation_updated?.conditions || []).filter(
    attr => !MESSAGE_KEYS.has(attr.key)
  );
  types.conversation_updated.conditions = [...base, ...manifested].filter(
    attr => !attr.filterOperators?.some(op => op.value === 'attribute_changed')
  );
  return types;
});

const filterTypes = computed(() => {
  const attributes = getAttributes(
    automationTypes.value,
    'conversation_updated'
  ).map(attribute => {
    const skipTranslation =
      attribute.customAttributeType === 'conversation_attribute' ||
      attribute.customAttributeType === 'contact_attribute' ||
      attribute.disabled;
    return {
      ...attribute,
      name: skipTranslation
        ? attribute.name
        : t(`AUTOMATION.ATTRIBUTES.${attribute.name}`),
    };
  });

  return attributes.map(attr => {
    if (attr.disabled) {
      return { value: attr.key, label: attr.name, disabled: true };
    }
    const mappedInputType = INPUT_TYPE_MAP[attr.inputType] || 'plainText';
    const options = getConditionDropdownValues(attr.key) || [];
    const filterOperators = (attr.filterOperators || [])
      .filter(op => op.value !== 'attribute_changed')
      .map(op => {
        const enriched = operators.value[op.value];
        if (enriched) return enriched;
        return {
          value: op.value,
          label: t(`FILTER.OPERATOR_LABELS.${op.value}`),
          hasInput: true,
          inputOverride: null,
          icon: h('span', { class: 'i-ph-equals-bold !text-n-blue-11' }),
        };
      });

    return {
      attributeKey: attr.key,
      value: attr.key,
      attributeName: attr.name,
      label: attr.name,
      inputType: mappedInputType,
      options,
      filterOperators,
      dataType: 'text',
      attributeModel: attr.customAttributeType || 'standard',
    };
  });
});

const labelOptions = computed(() =>
  (labels.value || []).map(label => ({
    value: label.title,
    label: label.title,
  }))
);

const typeLabel = type => t(`BUSINESS_RULES.TYPES.${type}`);
const typeHelp = computed(() => t(`BUSINESS_RULES.TYPE_HELP.${draft.type}`));

const attributeScope = ref('conversation');

const onTypeChange = type => {
  draft.type = type;
  draft.preset_id = null;
  draft.config = emptyConfigForType(type);
  draft.conditions =
    type === 'if_attribute_then_require' ? [emptyCondition()] : [];
  ensureArrays();
  attributeScope.value = 'conversation';
};

const requireAttributesScopeCounts = computed(() => ({
  conversation:
    (draft.config.attribute_keys?.length || 0) +
    (draft.config.attribute_category_keys?.length || 0),
  contact:
    (draft.config.contact_attribute_keys?.length || 0) +
    (draft.config.contact_attribute_category_keys?.length || 0),
}));

const ifAttributeThenRequireScopeCounts = computed(() => ({
  conversation:
    (draft.config.require_attribute_keys?.length || 0) +
    (draft.config.require_attribute_category_keys?.length || 0),
  contact:
    (draft.config.require_contact_attribute_keys?.length || 0) +
    (draft.config.require_contact_attribute_category_keys?.length || 0),
}));

const appendCondition = () => {
  if (!draft.conditions.length) {
    draft.conditions.push(emptyCondition());
    return;
  }
  const last = draft.conditions[draft.conditions.length - 1];
  if (!last.query_operator) last.query_operator = 'and';
  draft.conditions.push(emptyCondition());
};

const removeCondition = index => {
  draft.conditions.splice(index, 1);
  if (draft.conditions.length === 1) {
    draft.conditions[0].query_operator = null;
  }
};

const statusModel = computed({
  get: () => draft.config.status || draft.config.on_status || 'resolved',
  set: value => {
    if (draft.type === 'if_attribute_then_require') {
      draft.config.on_status = value;
    } else {
      draft.config.status = value;
    }
  },
});

const statusesMulti = computed({
  get: () => draft.config.statuses || [],
  set: value => {
    draft.config.statuses = value;
  },
});

const toggleStatusInList = status => {
  const list = [...(draft.config.statuses || [])];
  const idx = list.indexOf(status);
  if (idx >= 0) list.splice(idx, 1);
  else list.push(status);
  draft.config.statuses = list;
};

const typeSelectOptions = computed(() =>
  GUARD_RULE_TYPES.map(type => ({ id: type, name: typeLabel(type) }))
);
const typeSelectedItem = computed(() => ({
  id: draft.type,
  name: typeLabel(draft.type),
}));
const onTypeSelect = item => {
  if (item) onTypeChange(item.id);
};

const statusSelectOptions = computed(() =>
  STATUS_OPTIONS.map(status => ({
    id: status,
    name: t(`BUSINESS_RULES.STATUSES.${status}`),
  }))
);
const statusSelectedItem = computed(() => ({
  id: statusModel.value,
  name: t(`BUSINESS_RULES.STATUSES.${statusModel.value}`),
}));
const onStatusSelect = item => {
  if (item) statusModel.value = item.id;
};

const reasonAttributeOptions = computed(() => [
  { id: '', name: t('BUSINESS_RULES.FIELDS.NONE') },
  ...conversationAttributes.value
    .filter(a => !a.formula)
    .map(attr => ({ id: attr.attributeKey, name: attr.attributeDisplayName })),
]);
const reasonAttributeSelectedItem = computed(() => {
  const key = draft.config.reason_attribute_key;
  return (
    reasonAttributeOptions.value.find(o => o.id === key) ||
    reasonAttributeOptions.value[0]
  );
});
const onReasonAttributeSelect = item => {
  draft.config.reason_attribute_key = item ? item.id : '';
};

const labelSelectOptions = computed(() => [
  { id: '', name: t('BUSINESS_RULES.FIELDS.NONE') },
  ...labelOptions.value.map(opt => ({ id: opt.value, name: opt.label })),
]);
const labelSelectedItem = computed(() => {
  const key = draft.config.label;
  return (
    labelSelectOptions.value.find(o => o.id === key) ||
    labelSelectOptions.value[0]
  );
});
const onLabelSelect = item => {
  draft.config.label = item ? item.id : '';
};
</script>

<template>
  <div class="flex flex-col gap-4">
    <p class="m-0 text-sm text-n-slate-11">
      {{ $t('BUSINESS_RULES.FORM_HELP') }}
    </p>

    <Input
      v-model="draft.name"
      :label="$t('BUSINESS_RULES.FIELDS.NAME')"
      :placeholder="$t('BUSINESS_RULES.FIELDS.NAME_PLACEHOLDER')"
    />

    <div class="flex items-center gap-2">
      <Switch v-model="draft.enabled" />
      <span class="text-xs text-n-slate-11">
        {{ $t('BUSINESS_RULES.FIELDS.ENABLED') }}
      </span>
    </div>

    <OutlinedSelectField
      :label="$t('BUSINESS_RULES.FIELDS.TYPE')"
      :options="typeSelectOptions"
      :selected-item="typeSelectedItem"
      :show-search="false"
      @select="onTypeSelect"
    />
    <p class="m-0 -mt-2 text-xs text-n-slate-11">
      {{ typeHelp }}
    </p>

    <section class="flex flex-col gap-2">
      <p class="m-0 text-xs font-medium text-n-slate-12">
        {{ $t('BUSINESS_RULES.FIELDS.CONDITIONS') }}
      </p>
      <p class="m-0 text-xs text-n-slate-11">
        {{ $t('BUSINESS_RULES.FIELDS.CONDITIONS_HELP') }}
      </p>
      <ul
        class="m-0 grid list-none gap-4 rounded-xl p-3 outline outline-1 -outline-offset-1 outline-n-weak"
      >
        <template v-for="(condition, i) in draft.conditions" :key="i">
          <ConditionRow
            v-if="i === 0"
            v-model:attribute-key="draft.conditions[i].attribute_key"
            v-model:filter-operator="draft.conditions[i].filter_operator"
            v-model:values="draft.conditions[i].values"
            :filter-types="filterTypes"
            :show-query-operator="false"
            @remove="removeCondition(i)"
          />
          <ConditionRow
            v-else
            v-model:attribute-key="draft.conditions[i].attribute_key"
            v-model:filter-operator="draft.conditions[i].filter_operator"
            v-model:query-operator="draft.conditions[i - 1].query_operator"
            v-model:values="draft.conditions[i].values"
            :filter-types="filterTypes"
            show-query-operator
            @remove="removeCondition(i)"
          />
        </template>
        <div>
          <Button
            type="button"
            icon="i-lucide-plus"
            blue
            faded
            sm
            :label="$t('BUSINESS_RULES.FIELDS.ADD_CONDITION')"
            @click="appendCondition"
          />
        </div>
      </ul>
    </section>

    <section class="flex flex-col gap-3">
      <p class="m-0 text-xs font-medium text-n-slate-12">
        {{ $t('BUSINESS_RULES.FIELDS.EFFECT') }}
      </p>

      <template
        v-if="
          draft.type === 'require_attributes_on_status' ||
          draft.type === 'if_attribute_then_require' ||
          draft.type === 'forbid_status_if' ||
          draft.type === 'require_assignee_on_status'
        "
      >
        <OutlinedSelectField
          :label="$t('BUSINESS_RULES.FIELDS.STATUS')"
          :options="statusSelectOptions"
          :selected-item="statusSelectedItem"
          :show-search="false"
          @select="onStatusSelect"
        />
      </template>

      <template v-if="draft.type === 'require_attributes_on_status'">
        <p class="m-0 text-xs text-n-slate-11">
          {{ $t('BUSINESS_RULES.FIELDS.ATTRIBUTES_HELP') }}
        </p>
        <AttributeScopeSwitch
          v-model="attributeScope"
          :conversation-count="requireAttributesScopeCounts.conversation"
          :contact-count="requireAttributesScopeCounts.contact"
        />
        <AttributeRequirementPicker
          v-if="attributeScope === 'conversation'"
          :attributes="conversationAttributes"
          :selected-keys="draft.config.attribute_keys"
          :selected-categories="draft.config.attribute_category_keys"
          :empty-label="$t('BUSINESS_RULES.NO_ATTRIBUTES')"
          @update:selected-keys="draft.config.attribute_keys = $event"
          @update:selected-categories="
            draft.config.attribute_category_keys = $event
          "
        />
        <AttributeRequirementPicker
          v-else
          :attributes="contactAttributes"
          :selected-keys="draft.config.contact_attribute_keys"
          :selected-categories="draft.config.contact_attribute_category_keys"
          :empty-label="$t('BUSINESS_RULES.NO_CONTACT_ATTRIBUTES')"
          @update:selected-keys="draft.config.contact_attribute_keys = $event"
          @update:selected-categories="
            draft.config.contact_attribute_category_keys = $event
          "
        />
      </template>

      <template v-else-if="draft.type === 'if_attribute_then_require'">
        <p class="m-0 text-xs text-n-slate-11">
          {{ $t('BUSINESS_RULES.FIELDS.REQUIRE_ATTRIBUTES') }}
        </p>
        <AttributeScopeSwitch
          v-model="attributeScope"
          :conversation-count="ifAttributeThenRequireScopeCounts.conversation"
          :contact-count="ifAttributeThenRequireScopeCounts.contact"
        />
        <AttributeRequirementPicker
          v-if="attributeScope === 'conversation'"
          :attributes="conversationAttributes"
          :selected-keys="draft.config.require_attribute_keys"
          :selected-categories="draft.config.require_attribute_category_keys"
          :empty-label="$t('BUSINESS_RULES.NO_ATTRIBUTES')"
          @update:selected-keys="draft.config.require_attribute_keys = $event"
          @update:selected-categories="
            draft.config.require_attribute_category_keys = $event
          "
        />
        <AttributeRequirementPicker
          v-else
          :attributes="contactAttributes"
          :selected-keys="draft.config.require_contact_attribute_keys"
          :selected-categories="
            draft.config.require_contact_attribute_category_keys
          "
          :empty-label="$t('BUSINESS_RULES.NO_CONTACT_ATTRIBUTES')"
          @update:selected-keys="
            draft.config.require_contact_attribute_keys = $event
          "
          @update:selected-categories="
            draft.config.require_contact_attribute_category_keys = $event
          "
        />
      </template>

      <template v-else-if="draft.type === 'require_reason_on_status'">
        <div>
          <p class="mb-1 text-xs text-n-slate-11">
            {{ $t('BUSINESS_RULES.FIELDS.STATUSES') }}
          </p>
          <div class="flex flex-wrap gap-3">
            <div
              v-for="status in STATUS_OPTIONS"
              :key="status"
              class="flex items-center gap-2"
            >
              <Switch
                :model-value="statusesMulti.includes(status)"
                @update:model-value="toggleStatusInList(status)"
              />
              <span class="text-sm text-n-slate-12">
                {{ $t(`BUSINESS_RULES.STATUSES.${status}`) }}
              </span>
            </div>
          </div>
        </div>
        <div class="flex items-center gap-2">
          <Switch v-model="draft.config.require_private_note" />
          <span class="text-xs text-n-slate-11">
            {{ $t('BUSINESS_RULES.FIELDS.REQUIRE_PRIVATE_NOTE') }}
          </span>
        </div>
        <OutlinedSelectField
          :label="$t('BUSINESS_RULES.FIELDS.REASON_ATTRIBUTE')"
          :options="reasonAttributeOptions"
          :selected-item="reasonAttributeSelectedItem"
          @select="onReasonAttributeSelect"
        />
      </template>

      <template v-else-if="draft.type === 'forbid_status_if'">
        <OutlinedSelectField
          :label="$t('BUSINESS_RULES.FIELDS.LABEL')"
          :options="labelSelectOptions"
          :selected-item="labelSelectedItem"
          @select="onLabelSelect"
        />
      </template>

      <template v-else-if="draft.type === 'require_assignee_on_status'">
        <div class="flex items-center gap-2">
          <Switch v-model="draft.config.require_team_or_agent" />
          <span class="text-xs text-n-slate-11">
            {{ $t('BUSINESS_RULES.FIELDS.REQUIRE_TEAM_OR_AGENT') }}
          </span>
        </div>
      </template>
    </section>
  </div>
</template>
