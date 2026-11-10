<script setup>
import { computed, nextTick, ref, watch, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useTemplateBindings } from 'dashboard/composables/useTemplateBindings';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import WhatsappFlowsAPI from 'dashboard/api/whatsappFlows';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import SendCenterFilters from './SendCenterFilters.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import WhatsAppTemplateParser from '../WhatsAppTemplateParser.vue';
import ContentTemplateParser from 'dashboard/components-next/content-templates/ContentTemplateParser.vue';
import FlowDetail from './FlowDetail.vue';
import EditableBody from './EditableBody.vue';
import CategoryChip from './CategoryChip.vue';
import { lastSendCenterTab } from './session';
import ChatPreview from './ChatPreview.vue';
import WhatsAppText from './WhatsAppText';
import { useSystemVariables } from './useSystemVariables';
import {
  bodySegments,
  supportsFlows,
  usesContentTemplates,
  sendCenterIcon,
  templateReason,
  flowReason,
  flowState,
  TEMPLATE_CATEGORIES,
  TEMPLATE_STATUSES,
  FLOW_STATUSES,
  templateFieldLabel,
} from './helpers';

const props = defineProps({
  show: { type: Boolean, default: false },
  inbox: { type: Object, required: true },
  conversationId: { type: Number, required: true },
  canReply: { type: Boolean, required: true },
  templates: { type: Array, default: () => [] },
  sendTemplate: { type: Function, required: true },
});
const emit = defineEmits(['close']);
const { t, te } = useI18n();
const prefix = 'WHATSAPP_TEMPLATES.SEND_CENTER';
const store = useStore();
const { defaultValues, bindings } = useTemplateBindings('message');
const chat = useMapGetter('getSelectedChat');
const agent = useMapGetter('getCurrentUser');
const resolveContext = computed(() => ({
  contact: chat.value?.meta?.sender,
  conversation: chat.value,
  agent: agent.value,
}));
const { options: systemVariables, status: variablesStatus } =
  useSystemVariables(
    bindings,
    resolveContext,
    computed(() => props.inbox.id)
  );
const dialog = ref(null);
const parser = ref(null);
const editableBody = ref(null);
const editableHeader = ref(null);
const centerBody = ref(null);
const fieldHint = ref('');
const sendButton = ref(null);
const attempted = ref(false);
const flowDetail = ref(null);
const flows = ref([]);
const serverCanReply = ref(true);
const isSending = ref(false);
const isRefreshing = ref(false);
const error = ref('');
const flowError = ref('');
const tab = ref(0);
const newTabState = () => ({
  query: '',
  category: 'ALL',
  status: 'ALL',
  selectedKey: '',
});
const tabStates = ref([newTabState(), newTabState()]);
const activeState = computed(() => tabStates.value[tab.value]);
const query = computed({
  get: () => activeState.value.query,
  set: value => {
    activeState.value.query = value;
  },
});
const category = computed({
  get: () => activeState.value.category,
  set: value => {
    activeState.value.category = value;
  },
});
const status = computed({
  get: () => activeState.value.status,
  set: value => {
    activeState.value.status = value;
  },
});
const selectedKey = computed({
  get: () => activeState.value.selectedKey,
  set: value => {
    activeState.value.selectedKey = value;
  },
});
watch(selectedKey, () => {
  fieldHint.value = '';
});
const { run, abort, isPending } = useAbortableRequest();
const activeLoading = computed(
  () => isRefreshing.value || (tab.value === 1 && isPending.value)
);
const hasFlows = computed(() => supportsFlows(props.inbox));
const content = computed(() => usesContentTemplates(props.inbox));
const tabs = computed(() => [
  { label: t(`${prefix}.TEMPLATES`), index: 0 },
  ...(hasFlows.value ? [{ label: t(`${prefix}.FLOWS`), index: 1 }] : []),
]);
const statusLabel = value =>
  t(`${prefix}.STATUS.${te(`${prefix}.STATUS.${value}`) ? value : 'UNKNOWN'}`);
const reasonLabel = value =>
  t(
    `${prefix}.REASONS.${te(`${prefix}.REASONS.${value}`) ? value : 'unavailable'}`
  );
const categoryLabel = value =>
  t(
    `${prefix}.CATEGORY.${TEMPLATE_CATEGORIES.includes(value) ? value : 'UNKNOWN'}`
  );
const rows = computed(() =>
  [
    ...props.templates.map(template => ({
      key: `template:${template.name || template.friendly_name}:${template.language}`,
      type: 'template',
      name: template.name || template.friendly_name,
      status: template.status?.toUpperCase() || 'UNKNOWN',
      categories: [`template:${template.category?.toUpperCase() || 'UNKNOWN'}`],
      reason: templateReason(template, content.value),
      data: template,
    })),
    ...flows.value.map(flow => ({
      key: `flow:${flow.id}`,
      type: 'flow',
      name: flow.name,
      status: flowState(flow),
      categories: flow.categories.map(value => `flow:${value}`),
      reason: flowReason(flow, props.canReply && serverCanReply.value),
      data: flow,
    })),
  ].sort(
    (a, b) =>
      Number(!!a.reason) - Number(!!b.reason) || a.name.localeCompare(b.name)
  )
);
const searchedRows = computed(() =>
  rows.value.filter(
    row =>
      row.type === (tab.value === 0 ? 'template' : 'flow') &&
      `${row.name} ${row.data.body || ''} ${(row.data.components || []).map(c => c.text || '').join(' ')}`
        .toLocaleLowerCase()
        .includes(query.value.toLocaleLowerCase())
  )
);
const categoryRows = computed(() =>
  searchedRows.value.filter(
    row => status.value === 'ALL' || row.status === status.value
  )
);
const statusRows = computed(() =>
  searchedRows.value.filter(
    row => category.value === 'ALL' || row.categories.includes(category.value)
  )
);
const filtered = computed(() =>
  statusRows.value.filter(
    row => status.value === 'ALL' || row.status === status.value
  )
);
const categoryCount = value =>
  categoryRows.value.filter(row => row.categories.includes(value)).length;
const statusCount = value =>
  statusRows.value.filter(row => row.status === value).length;
const selected = computed(() =>
  filtered.value.find(row => row.key === selectedKey.value)
);
const filterGroup = computed(() => (tab.value === 0 ? 'templates' : 'flows'));
const categoryGroups = computed(() => [
  {
    key: filterGroup.value,
    label: t(
      `${prefix}.${tab.value === 0 ? 'CATEGORY_GROUP' : 'FLOW_CATEGORY_GROUP'}`
    ),
  },
]);
const categoryOptions = computed(() => [
  {
    value: 'ALL',
    label: t(`${prefix}.ALL_CATEGORIES`),
    triggerLabel: t(`${prefix}.FILTER_CATEGORY`),
    count: categoryRows.value.length,
  },
  ...(tab.value === 0
    ? TEMPLATE_CATEGORIES.map(value => ({
        value: `template:${value}`,
        label: categoryLabel(value),
        count: categoryCount(`template:${value}`),
        group: 'templates',
      }))
    : [...new Set(flows.value.flatMap(flow => flow.categories))].map(value => ({
        value: `flow:${value}`,
        label: t(`WHATSAPP_FLOWS.CATEGORIES.${value}`),
        count: categoryCount(`flow:${value}`),
        group: 'flows',
      }))),
]);
const statusOptions = computed(() => [
  {
    value: 'ALL',
    label: t(`${prefix}.ALL_STATUSES`),
    triggerLabel: t(`${prefix}.FILTER_STATUS`),
    count: statusRows.value.length,
  },
  ...(tab.value === 0 ? TEMPLATE_STATUSES : FLOW_STATUSES).map(value => ({
    value,
    label: statusLabel(value),
    count: statusCount(value),
    group: filterGroup.value,
  })),
]);
const statusGroups = computed(() => [
  {
    key: filterGroup.value,
    label: t(
      `${prefix}.${tab.value === 0 ? 'STATUS_GROUP' : 'FLOW_STATUS_GROUP'}`
    ),
  },
]);
const listElement = ref(null);
const resultsLabel = computed(() => {
  const count = filtered.value.length;
  if (!count) return t(`${prefix}.NO_RESULTS`);
  if (query.value)
    return t(`${prefix}.SEARCH_RESULTS`, { count, query: query.value }, count);
  return t(
    `${prefix}.${tab.value === 0 ? 'TEMPLATE_COUNT' : 'FLOW_COUNT'}`,
    { count },
    count
  );
});
watch(
  [selectedKey, () => props.show],
  async () => {
    if (!props.show) return;
    await nextTick();
    listElement.value
      ?.querySelector('[aria-pressed="true"]')
      ?.scrollIntoView({ block: 'nearest', behavior: 'instant' });
  },
  { flush: 'post' }
);
const catalogEmpty = computed(
  () =>
    !rows.value.some(
      row => row.type === (tab.value === 0 ? 'template' : 'flow')
    )
);
const clearFilters = () => {
  query.value = '';
  category.value = 'ALL';
  status.value = 'ALL';
};
const snippet = row =>
  row.data.components?.find(c => c.type === 'BODY')?.text ||
  row.data.body ||
  row.name;
const fieldLabel = (key, index = 0) =>
  templateFieldLabel(
    key,
    index,
    bindings.value,
    selected.value?.data.variable_bindings,
    t
  );
const missingLabel = computed(() => {
  const field = parser.value?.missingField;
  if (!field) return '';
  if (field.section === 'body')
    return fieldLabel(
      field.key,
      Object.keys(
        content.value
          ? parser.value.processedParams
          : parser.value.processedParams.body || {}
      ).indexOf(field.key)
    );
  return t(
    `${prefix}.${field.section === 'buttons' ? 'BUTTON_TEXT' : 'HEADER'}`
  );
});
const missingLabels = computed(() => {
  const labels = editableBody.value?.missingLabels || [];
  return [
    ...new Set([
      ...labels,
      ...(missingLabel.value ? [missingLabel.value] : []),
    ]),
  ];
});
const missingSummary = computed(() => {
  const missingBodyCount =
    (editableBody.value?.missingLabels.length || 0) +
    (editableHeader.value?.missingLabels.length || 0);
  if (missingBodyCount) return t(`${prefix}.MISSING_COUNT`, missingBodyCount);
  if (missingLabels.value.length)
    return t(`${prefix}.COMPLETE`, {
      field: missingLabels.value.join(' \u00b7 '),
    });
  return t(`${prefix}.CHECK_FIELDS`);
});
const focusNextData = field => {
  const fields = [
    ...field
      .closest('[data-testid="center-body"]')
      .querySelectorAll('[data-template-field]'),
  ];
  const next = fields[fields.indexOf(field) + 1];
  (next || sendButton.value?.$el)?.focus();
};
const languageChip = language => language.split(/[-_]/)[0].toUpperCase();
watch(selectedKey, () => {
  attempted.value = false;
});
const component = type =>
  selected.value?.data.components?.find(c => c.type === type);
const header = computed(() => component('HEADER')?.text || '');
const bodyExamples = computed(() => {
  const example = component('BODY')?.example;
  if (example?.body_text_named_params)
    return Object.fromEntries(
      example.body_text_named_params.map(item => [
        item.param_name,
        item.example,
      ])
    );
  return Object.fromEntries(
    (example?.body_text?.[0] || []).map((value, index) => [
      String(index + 1),
      value,
    ])
  );
});
const body = computed(
  () => component('BODY')?.text || selected.value?.data.body || ''
);
const footer = computed(() => component('FOOTER')?.text || '');
const buttons = computed(() =>
  (component('BUTTONS')?.buttons || []).map(button => ({
    text: button.text,
    type: button.type,
  }))
);
const headerMedia = computed(() => {
  const format = component('HEADER')?.format;
  return ['IMAGE', 'VIDEO', 'DOCUMENT', 'LOCATION'].includes(format)
    ? format
    : '';
});
const parserProps = computed(() => ({
  template: selected.value?.data,
  ...(content.value
    ? {}
    : {
        mediaInboxId: props.inbox.id,
        sendRenderedContent: props.inbox.channel_type === 'Channel::Api',
        defaultValues: defaultValues.value,
        resolveContext: resolveContext.value,
      }),
}));
// Selection replaces the field, then uses the parser's existing insertion path.
// Do not mark it as typed text: untouched variables retain server resolution.
const selectVariable = (preview, section, key, expression) => {
  const params = content.value
    ? parser.value.processedParams
    : parser.value.processedParams[section];
  params[key] = '';
  preview[section === 'header' ? 'insertHeaderVariable' : 'insertBodyVariable'](
    key,
    expression
  );
};
const canSend = computed(
  () =>
    selected.value &&
    !selected.value.reason &&
    !isSending.value &&
    (selected.value.type === 'flow'
      ? flowDetail.value?.isValid
      : parser.value && !parser.value.isFormInvalid)
);
const close = () => {
  emit('close');
};
const loadFlows = async () => {
  flowError.value = '';
  try {
    const response = await run(signal =>
      WhatsappFlowsAPI.conversationFlows(props.conversationId, { signal })
    );
    if (!response) return;
    flows.value = response.data.payload;
    serverCanReply.value = response.data.can_reply;
  } catch (e) {
    flowError.value = e.response?.data?.error || t(`${prefix}.LOAD_ERROR`);
  }
};
const refresh = async () => {
  isRefreshing.value = true;
  error.value = '';
  try {
    await store.dispatch('inboxes/syncTemplates', props.inbox.id);
    isRefreshing.value = false;
    if (hasFlows.value) await loadFlows();
  } catch (e) {
    error.value = e.response?.data?.error || t(`${prefix}.LOAD_ERROR`);
  } finally {
    isRefreshing.value = false;
  }
};
const sendTemplatePayload = async payload => {
  if (!canSend.value) return;
  isSending.value = true;
  error.value = '';
  try {
    if ((await props.sendTemplate(payload)) !== false) emit('close');
  } catch (e) {
    error.value = e.response?.data?.error || t(`${prefix}.SEND_ERROR`);
  } finally {
    isSending.value = false;
  }
};
const submit = async () => {
  attempted.value = true;
  if (!canSend.value) {
    await nextTick();
    const field = centerBody.value?.querySelector(
      '[data-template-field][aria-invalid="true"]'
    );
    field?.scrollIntoView?.({ block: 'center', inline: 'nearest' });
    field?.focus();
    return;
  }
  if (selected.value.type === 'template') {
    parser.value.sendMessage();
    return;
  }
  isSending.value = true;
  error.value = '';
  try {
    await WhatsappFlowsAPI.sendToConversation(
      props.conversationId,
      flowDetail.value.payload
    );
    emit('close');
  } catch (e) {
    error.value = e.response?.data?.error || t(`${prefix}.SEND_ERROR`);
  } finally {
    isSending.value = false;
  }
};
watch(tab, value => {
  if (hasFlows.value) lastSendCenterTab.value = value;
});
const handleEscape = event => {
  if (!flowDetail.value?.customizing) return;
  event.preventDefault();
  event.stopPropagation();
  flowDetail.value.closeCustomization();
};
watch(filtered, list => {
  if (!list.some(row => row.key === selectedKey.value))
    selectedKey.value = list[0]?.key || '';
});
watch(
  () => [props.show, props.conversationId, props.inbox.id],
  async () => {
    abort();
    flows.value = [];
    error.value = '';
    flowError.value = '';
    if (!props.show) {
      dialog.value?.close();
      return;
    }
    tab.value = hasFlows.value ? lastSendCenterTab.value : 0;
    tabStates.value = [newTabState(), newTabState()];
    selectedKey.value = filtered.value[0]?.key || '';
    await nextTick();
    dialog.value.open();
    if (hasFlows.value) await loadFlows();
  },
  { immediate: true }
);
const previewMessages = preview => [
  ...new Set(
    ['header', 'body'].flatMap(section =>
      bodySegments(preview[`${section}Text`] || '')
        .filter(part => part.key)
        .map(part => preview[`${section}Message`]?.(part.key))
        .filter(Boolean)
    )
  ),
];
const overlayTitleId = useId();
const overlayDescriptionId = useId();
</script>

<template>
  <Dialog
    ref="dialog"
    :aria-labelledby="overlayTitleId"
    :aria-describedby="overlayDescriptionId"
    width="sendCenter"
    body-scroll
    :show-confirm-button="false"
    :show-cancel-button="false"
    @close="close"
  >
    <div
      ref="centerBody"
      class="flex max-md:h-auto md:h-[min(40rem,calc(90dvh-11rem))] min-h-0 flex-col gap-4"
      data-columns="2"
      data-testid="center-body"
      @keydown.esc="handleEscape"
    >
      <div class="flex shrink-0 justify-between items-start gap-3">
        <div>
          <h2
            :id="overlayTitleId"
            class="flex items-center gap-2 text-lg font-semibold text-n-slate-12"
          >
            <Icon
              :icon="sendCenterIcon(inbox)"
              class="size-6 text-n-teal-11"
            />{{
              $t(
                `${prefix}.${sendCenterIcon(inbox) === 'i-woot-whatsapp' ? 'TITLE' : 'TEMPLATE_TITLE'}`
              )
            }}
          </h2>
          <p :id="overlayDescriptionId" class="mt-1 text-sm text-n-slate-11">
            {{
              $t(
                `${prefix}.${hasFlows ? 'DESCRIPTION' : 'TEMPLATE_DESCRIPTION'}`
              )
            }}
          </p>
        </div>
        <Button
          icon="i-lucide-x"
          ghost
          slate
          sm
          :disabled="isSending"
          :aria-label="$t(`${prefix}.CLOSE`)"
          @click="close"
        />
      </div>
      <p
        class="sr-only"
        aria-live="polite"
        aria-atomic="true"
        data-testid="center-selection"
      >
        {{
          selected
            ? $t(
                `${prefix}.${selected.type === 'flow' ? 'FLOW_SELECTED' : 'TEMPLATE_SELECTED'}`,
                { name: selected.name }
              )
            : ''
        }}
      </p>
      <div
        class="grid min-h-0 flex-1 gap-6 grid-cols-1 md:grid-cols-[minmax(0,5fr)_minmax(0,7fr)]"
        data-testid="center-columns"
      >
        <section
          class="flex min-h-0 min-w-0 flex-col gap-2 md:border-e md:border-n-weak md:pe-6"
        >
          <div class="flex flex-col gap-2" data-testid="center-controls">
            <div
              class="flex items-center justify-between gap-2"
              data-testid="center-toolbar"
            >
              <TabBar
                :tabs="tabs"
                :initial-active-tab="tab"
                @tab-changed="tab = $event.index"
              />
              <Button
                intent="tertiary"
                size="sm"
                icon="i-lucide-refresh-cw"
                :title="$t(`${prefix}.REFRESH`)"
                :aria-label="$t(`${prefix}.REFRESH`)"
                :is-loading="activeLoading"
                :disabled="isSending || isRefreshing || isPending"
                data-testid="center-refresh"
                @click="refresh"
              />
            </div>
            <SendCenterFilters
              :key="`${show}-${conversationId}-${inbox.id}`"
              v-model:query="query"
              v-model:category="category"
              v-model:status="status"
              :is-flow="tab === 1"
              :category-options="categoryOptions"
              :status-options="statusOptions"
              :category-groups="categoryGroups"
              :status-groups="statusGroups"
            />
            <p
              class="min-h-4 text-xs text-n-slate-11"
              aria-live="polite"
              aria-atomic="true"
              data-testid="center-count"
            >
              {{ resultsLabel }}
            </p>
            <p v-if="activeLoading" class="text-xs text-n-slate-11">
              {{ $t(`${prefix}.LOADING`) }}
            </p>
          </div>
          <div
            v-if="tab === 1 && flowError"
            class="flex flex-col gap-2"
            data-testid="center-flow-error"
          >
            <p role="alert" class="text-sm text-n-ruby-11">{{ flowError }}</p>
            <Button
              intent="secondary"
              size="sm"
              :label="$t(`${prefix}.RETRY`)"
              :disabled="isPending"
              @click="loadFlows"
            />
          </div>
          <div
            ref="listElement"
            class="min-h-0 flex-1 overflow-y-auto overscroll-contain flex flex-col gap-1"
            role="list"
            data-testid="center-list"
          >
            <button
              v-for="row in filtered"
              :key="row.key"
              type="button"
              class="w-full min-w-0 rounded-lg border-s-[0.1875rem] px-3 py-3 text-start shrink-0 transition-colors duration-150 motion-reduce:transition-none focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
              :class="
                row.key === selectedKey
                  ? 'border-n-brand bg-n-alpha-2'
                  : 'border-transparent hover:bg-n-alpha-1'
              "
              :disabled="isSending"
              :aria-pressed="row.key === selectedKey"
              :data-testid="`center-row-${row.key}`"
              @click="selectedKey = row.key"
            >
              <div class="flex items-start justify-between gap-2">
                <p
                  class="min-w-0 [overflow-wrap:anywhere] text-sm font-semibold text-n-slate-12"
                  :title="row.name"
                >
                  <template
                    v-for="(part, index) in row.name.split('_')"
                    :key="index"
                  >
                    <wbr v-if="index" />{{ part
                    }}{{ index < row.name.split('_').length - 1 ? '_' : '' }}
                  </template>
                </p>
                <div
                  class="flex shrink-0 flex-wrap justify-end items-center gap-1"
                >
                  <CategoryChip
                    v-if="row.type === 'template'"
                    :category="row.data.category"
                  />
                  <span
                    v-if="row.data.language"
                    class="rounded bg-n-alpha-2 px-1.5 py-0.5 text-xxs text-n-slate-11"
                  >
                    {{ languageChip(row.data.language) }}
                  </span>
                </div>
              </div>
              <p class="mt-1 line-clamp-2 text-xs leading-5 text-n-slate-11">
                <WhatsAppText
                  v-if="row.type === 'template'"
                  :text="snippet(row)"
                  compact
                />
                <template v-else>{{ snippet(row) }}</template>
              </p>
              <span
                v-if="row.reason"
                class="mt-2 block text-xs text-n-amber-11"
              >
                <span>{{ statusLabel(row.status) }}</span>
                <span class="ms-1">{{ reasonLabel(row.reason) }}</span>
              </span>
            </button>
            <div
              v-if="
                !filtered.length && !activeLoading && !(tab === 1 && flowError)
              "
              class="flex flex-col items-center gap-3 px-4 py-10 text-center"
            >
              <Icon
                :icon="
                  catalogEmpty ? 'i-lucide-layout-template' : 'i-lucide-search'
                "
                class="size-8 text-n-slate-10"
              />
              <p class="text-sm font-semibold text-n-slate-12">
                {{
                  $t(`${prefix}.${catalogEmpty ? 'EMPTY_CATALOG' : 'EMPTY'}`)
                }}
              </p>
              <p class="text-xs text-n-slate-11">
                {{
                  $t(
                    `${prefix}.${catalogEmpty ? 'EMPTY_CATALOG_HELP' : 'EMPTY_HELP'}`
                  )
                }}
              </p>
              <Button
                intent="secondary"
                size="sm"
                :label="
                  $t(
                    `${prefix}.${catalogEmpty ? 'REFRESH' : 'CLEAR_SEARCH_FILTERS'}`
                  )
                "
                @click="catalogEmpty ? refresh() : clearFilters()"
              />
            </div>
          </div>
        </section>
        <section
          v-if="selected"
          class="min-h-0 min-w-0 overflow-y-auto overscroll-contain flex flex-col gap-3"
          data-testid="center-detail"
          :aria-label="selected.name"
        >
          <FlowDetail
            v-if="selected.type === 'flow'"
            :key="selected.key"
            ref="flowDetail"
            :flow="selected.data"
            :readonly="!!selected.reason"
          />
          <template v-else-if="!selected.reason">
            <component
              :is="content ? ContentTemplateParser : WhatsAppTemplateParser"
              :key="selected.key"
              ref="parser"
              class="flex min-h-0 min-w-0 flex-1 flex-col gap-3 [&>[data-template-preview]]:flex [&>[data-template-preview]]:min-h-0 [&>[data-template-preview]]:flex-1 [&>[data-template-fields]:empty]:hidden [&>[data-template-fields]:not(:empty)]:max-h-40 [&>[data-template-fields]]:shrink-0 [&>[data-template-fields]]:overflow-y-auto"
              v-bind="parserProps"
              @send-message="sendTemplatePayload"
            >
              <template #preview="preview">
                <ChatPreview
                  :key="selected.key"
                  :messages="previewMessages(preview)"
                  :field-hint="fieldHint"
                  :header="preview.header"
                  :body="preview.body"
                  :footer="footer"
                  :buttons="buttons"
                  :header-media="headerMedia"
                >
                  <template #header>
                    <EditableBody
                      v-if="preview.headerText"
                      ref="editableHeader"
                      class="font-semibold"
                      :text="preview.headerText"
                      :values="preview.headerValues"
                      :attempted="attempted"
                      :expressions="parser?.processedParams?.header"
                      :label-for="fieldLabel"
                      :variable-filter="preview.variableFilter"
                      :system-variables="systemVariables"
                      :variables-status="variablesStatus"
                      @change="preview.setHeaderValue"
                      @select="
                        (key, expression) =>
                          selectVariable(preview, 'header', key, expression)
                      "
                      @advance="focusNextData"
                      @hint="fieldHint = $event"
                    />
                  </template>
                  <EditableBody
                    v-if="preview.bodyText"
                    ref="editableBody"
                    :text="preview.bodyText"
                    :values="preview.bodyValues"
                    :expressions="
                      content
                        ? parser?.processedParams
                        : parser?.processedParams?.body
                    "
                    :invalid-keys="preview.invalidBodyKeys"
                    :attempted="attempted"
                    :label-for="fieldLabel"
                    :examples="bodyExamples"
                    :variable-filter="preview.variableFilter"
                    :system-variables="systemVariables"
                    :variables-status="variablesStatus"
                    @change="preview.setBodyValue"
                    @select="
                      (key, expression) =>
                        selectVariable(preview, 'body', key, expression)
                    "
                    @advance="focusNextData"
                    @hint="fieldHint = $event"
                  />
                </ChatPreview>
              </template>
              <template #header-fields />
              <template #body-fields />
              <template #actions />
            </component>
          </template>
          <ChatPreview
            v-else
            :header="header"
            :body="body"
            :footer="footer"
            :buttons="buttons"
            :header-media="headerMedia"
          />
        </section>
        <p v-else class="text-sm text-n-slate-11">
          {{ $t(`${prefix}.NO_SELECTION`) }}
        </p>
      </div>
    </div>
    <template #footer>
      <div
        class="flex items-center justify-between gap-3 [&>button:disabled]:opacity-100 [&>button:disabled]:bg-n-alpha-2 [&>button:disabled]:text-n-slate-11"
        data-testid="center-footer"
        @keydown.esc="handleEscape"
      >
        <div class="min-w-0">
          <p v-if="error" role="alert" class="text-sm text-n-ruby-11">
            {{ error }}
          </p>
          <p
            v-else-if="
              selected?.type === 'template' &&
              !selected.reason &&
              parser?.isFormInvalid
            "
            role="status"
            class="flex items-center gap-2 text-sm text-n-ruby-11"
            data-testid="center-invalid-reason"
          >
            <Icon icon="i-lucide-triangle-alert" class="size-4 shrink-0" />
            {{ missingSummary }}
          </p>
          <p
            v-else-if="selected?.type === 'flow' && flowDetail?.invalidReason"
            class="text-xs text-n-ruby-11"
            role="status"
            data-testid="center-invalid-reason"
          >
            {{ flowDetail.invalidReason }}
          </p>
          <p
            v-else-if="selected?.reason"
            class="flex gap-2 items-start text-sm text-n-slate-12"
            data-testid="center-reason"
          >
            <Icon
              icon="i-lucide-lock-keyhole"
              class="size-4 mt-0.5 shrink-0"
            />{{ reasonLabel(selected.reason) }}
          </p>
          <p
            v-else-if="canSend"
            role="status"
            class="flex items-center gap-2 text-sm text-n-slate-11"
            data-testid="center-ready"
          >
            <Icon
              icon="i-lucide-circle-check"
              class="size-4 shrink-0 text-n-teal-11"
            />
            {{ $t(`${prefix}.READY`) }}
          </p>
        </div>
        <Button
          ref="sendButton"
          intent="primary"
          class="shrink-0"
          :label="$t(`${prefix}.SEND`)"
          icon="i-lucide-send"
          :disabled="
            !selected ||
            Boolean(selected.reason) ||
            isSending ||
            (selected.type === 'flow' && !canSend)
          "
          :is-loading="isSending"
          data-testid="center-send"
          @click="submit"
        />
      </div>
    </template>
  </Dialog>
</template>
