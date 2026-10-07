<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useTemplateBindings } from 'dashboard/composables/useTemplateBindings';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import WhatsappFlowsAPI from 'dashboard/api/whatsappFlows';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import WhatsAppTemplateParser from '../WhatsAppTemplateParser.vue';
import ContentTemplateParser from 'dashboard/components-next/content-templates/ContentTemplateParser.vue';
import FlowDetail from './FlowDetail.vue';
import MessagePreview from './MessagePreview.vue';
import {
  supportsFlows,
  usesContentTemplates,
  sendCenterIcon,
  templateReason,
  flowReason,
  flowState,
  TEMPLATE_CATEGORIES,
  TEMPLATE_STATUSES,
  FLOW_STATUSES,
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
const { defaultValues } = useTemplateBindings('message');
const chat = useMapGetter('getSelectedChat');
const agent = useMapGetter('getCurrentUser');
const resolveContext = computed(() => ({
  contact: chat.value?.meta?.sender,
  conversation: chat.value,
  agent: agent.value,
}));
const dialog = ref(null);
const parser = ref(null);
const flowDetail = ref(null);
const flows = ref([]);
const serverCanReply = ref(true);
const isSending = ref(false);
const error = ref('');
const query = ref('');
const category = ref('ALL');
const status = ref('ALL');
const tab = ref(0);
const selectedKey = ref('');
const { run, abort, isPending } = useAbortableRequest();
const hasFlows = computed(() => supportsFlows(props.inbox));
const content = computed(() => usesContentTemplates(props.inbox));
const tabs = computed(() => [
  { label: t(`${prefix}.ALL`), index: 0 },
  { label: t(`${prefix}.TEMPLATES`), index: 1 },
  ...(hasFlows.value ? [{ label: t(`${prefix}.FLOWS`), index: 2 }] : []),
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
const filtered = computed(() =>
  rows.value.filter(
    row =>
      (tab.value === 0 ||
        row.type === (tab.value === 1 ? 'template' : 'flow')) &&
      (category.value === 'ALL' || row.categories.includes(category.value)) &&
      (status.value === 'ALL' || row.status === status.value) &&
      `${row.name} ${row.data.body || ''} ${(row.data.components || []).map(c => c.text || '').join(' ')}`
        .toLocaleLowerCase()
        .includes(query.value.toLocaleLowerCase())
  )
);
const selected = computed(() =>
  filtered.value.find(row => row.key === selectedKey.value)
);
const categoryGroups = computed(() => [
  { key: 'templates', label: t(`${prefix}.CATEGORY_GROUP`) },
  ...(hasFlows.value
    ? [{ key: 'flows', label: t(`${prefix}.FLOW_CATEGORY_GROUP`) }]
    : []),
]);
const categoryOptions = computed(() => [
  { value: 'ALL', label: t(`${prefix}.ALL_CATEGORIES`) },
  ...TEMPLATE_CATEGORIES.map(value => ({
    value: `template:${value}`,
    label: categoryLabel(value),
    group: 'templates',
  })),
  ...[...new Set(flows.value.flatMap(flow => flow.categories))].map(value => ({
    value: `flow:${value}`,
    label: t(`WHATSAPP_FLOWS.CATEGORIES.${value}`),
    group: 'flows',
  })),
]);
const statusOptions = computed(() => [
  { value: 'ALL', label: t(`${prefix}.ALL_STATUSES`) },
  ...TEMPLATE_STATUSES.map(value => ({
    value,
    label: statusLabel(value),
    group: 'templates',
  })),
  ...(hasFlows.value
    ? FLOW_STATUSES.map(value => ({
        value,
        label: statusLabel(value),
        group: 'flows',
      }))
    : []),
]);
const statusGroups = computed(() => [
  { key: 'templates', label: t(`${prefix}.STATUS_GROUP`) },
  ...(hasFlows.value
    ? [{ key: 'flows', label: t(`${prefix}.FLOW_STATUS_GROUP`) }]
    : []),
]);
const component = type =>
  selected.value?.data.components?.find(c => c.type === type);
const header = computed(() => component('HEADER')?.text || '');
const body = computed(
  () => component('BODY')?.text || selected.value?.data.body || ''
);
const footer = computed(() => component('FOOTER')?.text || '');
const buttons = computed(
  () => component('BUTTONS')?.buttons?.map(button => button.text) || []
);
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
  if (!isSending.value) emit('close');
};
const loadFlows = async () => {
  error.value = '';
  try {
    const response = await run(signal =>
      WhatsappFlowsAPI.conversationFlows(props.conversationId, { signal })
    );
    if (!response) return;
    flows.value = response.data.payload;
    serverCanReply.value = response.data.can_reply;
  } catch (e) {
    error.value = e.response?.data?.error || t(`${prefix}.LOAD_ERROR`);
  }
};
const refresh = async () => {
  error.value = '';
  try {
    await store.dispatch('inboxes/syncTemplates', props.inbox.id);
    if (hasFlows.value) await loadFlows();
  } catch (e) {
    error.value = e.response?.data?.error || t(`${prefix}.LOAD_ERROR`);
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
  if (!canSend.value) return;
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
    if (!props.show) {
      dialog.value?.close();
      return;
    }
    tab.value = 0;
    query.value = '';
    category.value = 'ALL';
    status.value = 'ALL';
    selectedKey.value = '';
    selectedKey.value = filtered.value[0]?.key || '';
    await nextTick();
    dialog.value.open();
    if (hasFlows.value) await loadFlows();
  },
  { immediate: true }
);
</script>

<template>
  <Dialog
    ref="dialog"
    width="3xl"
    body-scroll
    :show-confirm-button="false"
    :show-cancel-button="false"
    @close="close"
  >
    <div class="flex flex-col gap-4">
      <div class="flex justify-between items-start gap-3">
        <div>
          <h2
            class="flex items-center gap-2 text-lg font-semibold text-n-slate-12"
          >
            <Icon
              :icon="sendCenterIcon(inbox)"
              class="size-6 text-n-teal-11"
            />{{
              $t(
                `${prefix}.${sendCenterIcon(inbox) === 'i-ph-whatsapp-logo' ? 'TITLE' : 'TEMPLATE_TITLE'}`
              )
            }}
          </h2>
          <p class="mt-1 text-sm text-n-slate-11">
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
      <TabBar
        :tabs="tabs"
        :initial-active-tab="tab"
        @tab-changed="tab = $event.index"
      />
      <div class="grid gap-5 sm:grid-cols-[17rem_1fr]">
        <section class="flex flex-col min-w-0 gap-3">
          <div class="flex gap-2">
            <Input
              v-model="query"
              type="search"
              size="sm"
              class="flex-1"
              :placeholder="$t(`${prefix}.SEARCH`)"
              :aria-label="$t(`${prefix}.SEARCH`)"
              data-testid="center-search"
            /><Button
              icon="i-lucide-refresh-cw"
              ghost
              slate
              sm
              :is-loading="isPending"
              :disabled="isSending"
              :aria-label="$t(`${prefix}.REFRESH`)"
              @click="refresh"
            />
          </div>
          <ComboBox
            v-model="category"
            :options="categoryOptions"
            :groups="categoryGroups"
            :allow-deselect="false"
            teleport
            :aria-label="$t(`${prefix}.ALL_CATEGORIES`)"
          >
            <template #footer="{ close: closeMenu }">
              <Button
                :label="$t(`${prefix}.RESET_FILTER`)"
                ghost
                slate
                sm
                class="w-full"
                @click="
                  category = 'ALL';
                  closeMenu();
                "
              />
            </template>
          </ComboBox>
          <ComboBox
            v-model="status"
            :options="statusOptions"
            :groups="statusGroups"
            :allow-deselect="false"
            teleport
            :aria-label="$t(`${prefix}.ALL_STATUSES`)"
          />
          <p v-if="isPending" class="text-xs text-n-slate-11">
            {{ $t(`${prefix}.LOADING`) }}
          </p>
          <div
            class="overflow-y-auto max-h-[21rem] flex flex-col gap-1"
            role="list"
            data-testid="center-list"
          >
            <Button
              v-for="row in filtered"
              :key="row.key"
              type="button"
              ghost
              slate
              class="!h-auto !p-2 !justify-start text-start"
              :class="
                row.key === selectedKey
                  ? '!bg-n-blue-3 outline outline-1 !outline-n-blue-6'
                  : ''
              "
              :disabled="isSending"
              :aria-pressed="row.key === selectedKey"
              :data-testid="`center-row-${row.key}`"
              @click="selectedKey = row.key"
            >
              <span class="flex flex-col gap-1 w-full min-w-0"
                ><span class="flex gap-2 justify-between items-center"
                  ><span
                    class="truncate text-xs font-semibold text-n-slate-12"
                    >{{ row.name }}</span
                  ><Icon
                    :icon="
                      row.type === 'flow'
                        ? 'i-lucide-workflow'
                        : 'i-lucide-layout-template'
                    "
                    class="size-4 shrink-0 text-n-slate-10" /></span
                ><span
                  class="text-xs"
                  :class="row.reason ? 'text-n-amber-11' : 'text-n-teal-11'"
                  >{{ statusLabel(row.status) }}</span
                ><span
                  v-if="row.reason"
                  class="text-xs font-normal whitespace-normal text-n-slate-11"
                  >{{ reasonLabel(row.reason) }}</span
                ></span
              >
            </Button>
            <p
              v-if="!filtered.length && !isPending"
              class="p-4 text-sm text-n-slate-11"
            >
              {{ $t(`${prefix}.EMPTY`) }}
            </p>
          </div>
        </section>
        <section
          v-if="selected"
          class="min-w-0 sm:border-s border-n-weak sm:ps-5 flex flex-col gap-4"
          data-testid="center-detail"
        >
          <div>
            <div class="flex items-start justify-between gap-2">
              <h3 class="text-sm font-semibold break-words text-n-slate-12">
                {{ selected.name }}
              </h3>
              <span
                class="shrink-0 rounded px-2 py-1 text-xs"
                :class="
                  selected.reason
                    ? 'bg-n-amber-3 text-n-amber-11'
                    : 'bg-n-teal-3 text-n-teal-11'
                "
                >{{ statusLabel(selected.status) }}</span
              >
            </div>
            <p class="text-xs mt-1 text-n-slate-11">
              {{
                selected.type === 'flow'
                  ? $t(`${prefix}.SCREENS`, { count: selected.data.screens })
                  : `${categoryLabel(selected.data.category?.toUpperCase())} · ${selected.data.language}`
              }}
            </p>
          </div>
          <FlowDetail
            v-if="selected.type === 'flow'"
            :key="selected.key"
            ref="flowDetail"
            :flow="selected.data"
          />
          <template v-else-if="!selected.reason">
            <ContentTemplateParser
              v-if="content"
              :key="selected.key"
              ref="parser"
              :template="selected.data"
              @send-message="sendTemplatePayload"
            >
              <template #actions />
            </ContentTemplateParser>
            <WhatsAppTemplateParser
              v-else
              :key="selected.key"
              ref="parser"
              :template="selected.data"
              :media-inbox-id="inbox.id"
              :send-rendered-content="inbox.channel_type === 'Channel::Api'"
              :default-values="defaultValues"
              :resolve-context="resolveContext"
              @send-message="sendTemplatePayload"
            >
              <template #preview="preview">
                <MessagePreview
                  :header="preview.header"
                  :body="preview.body"
                  :footer="footer"
                  :buttons="buttons"
                /> </template
              ><template #actions />
            </WhatsAppTemplateParser>
          </template>
          <MessagePreview
            v-else
            :header="header"
            :body="body"
            :footer="footer"
            :buttons="buttons"
          />
          <p
            v-if="selected.reason"
            class="flex gap-2 items-start text-sm text-n-slate-12"
            data-testid="center-reason"
          >
            <Icon
              icon="i-lucide-lock-keyhole"
              class="size-4 mt-0.5 shrink-0"
            />{{ reasonLabel(selected.reason) }}
          </p>
        </section>
        <p v-else class="text-sm text-n-slate-11">
          {{ $t(`${prefix}.NO_SELECTION`) }}
        </p>
      </div>
    </div>
    <template #footer>
      <div class="flex items-center justify-between gap-3">
        <div class="min-w-0">
          <p v-if="error" role="alert" class="text-sm text-n-ruby-11">
            {{ error }}
          </p>
          <p v-else class="text-xs text-n-slate-11">
            {{ $t(`${prefix}.${canSend ? 'READY' : 'UNAVAILABLE'}`) }}
          </p>
        </div>
        <Button
          :label="$t(`${prefix}.SEND`)"
          icon="i-lucide-send"
          :disabled="!canSend"
          :is-loading="isSending"
          data-testid="center-send"
          @click="submit"
        />
      </div>
    </template>
  </Dialog>
</template>
