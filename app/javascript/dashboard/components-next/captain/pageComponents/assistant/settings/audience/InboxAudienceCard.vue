<script setup>
import { computed, ref, watch, useTemplateRef, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import FilterSelect from 'dashboard/components-next/filter/inputs/FilterSelect.vue';
import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';
import AudienceGroup from './AudienceGroup.vue';
import { useAudienceTree } from './useAudienceTree';
import { cleanLines, listError, listKeyForInbox } from './inboxAudience';

const props = defineProps({
  inbox: { type: Object, required: true },
  assistantId: { type: Number, required: true },
  canEdit: { type: Boolean, default: false },
  filterTypes: { type: Array, required: true },
  warnings: { type: Array, default: () => [] },
});

const { t } = useI18n();
const store = useStore();
const filterTypes = computed(() => props.filterTypes);
const { defaultRoot, hydrateRoot, serializeNode } =
  useAudienceTree(filterTypes);
const open = ref(false);
const saving = ref(false);
const saved = ref(false);
const error = ref('');
const mode = ref('inherit');
const listMode = ref('none');
const text = ref('');
const scope = ref('all');
const tree = ref(defaultRoot());
const advanced = ref(false);
const groupRef = useTemplateRef('groupRef');
const listKey = computed(() => listKeyForInbox(props.inbox));
const entries = computed(() => cleanLines(text.value));
const validationError = computed(() =>
  mode.value === 'custom' && listMode.value !== 'none'
    ? listError(entries.value)
    : ''
);
const modes = computed(() => [
  {
    value: 'inherit',
    label: t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX.MODE_INHERIT'),
  },
  {
    value: 'everyone',
    label: t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX.MODE_EVERYONE'),
  },
  {
    value: 'custom',
    label: t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX.MODE_CUSTOM'),
  },
]);
const segmentModes = computed(() => [
  {
    value: 'inherit',
    label: t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX.MODE_INHERIT_SHORT'),
  },
  {
    value: 'everyone',
    label: t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX.MODE_EVERYONE_SHORT'),
  },
  {
    value: 'custom',
    label: t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX.MODE_CUSTOM_SHORT'),
  },
]);
const listModes = computed(() => [
  {
    value: 'none',
    label: t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX.LIST_NONE'),
  },
  {
    value: 'allow',
    label: t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX.LIST_ALLOW'),
  },
  {
    value: 'deny',
    label: t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX.LIST_DENY'),
  },
]);
const scopes = computed(() => [
  {
    value: 'all',
    label: t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX.SCOPE_ALL'),
  },
  {
    value: 'new',
    label: t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX.SCOPE_NEW'),
  },
  {
    value: 'returning',
    label: t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX.SCOPE_RETURNING'),
  },
]);
const listLabel = computed(() => {
  const channel =
    props.inbox.channel_type === 'Channel::Instagram'
      ? 'Instagram'
      : 'Messenger';
  return {
    phones: t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX.LABEL_PHONES'),
    channel_ids: t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX.LABEL_CHANNEL_IDS', {
      channel,
    }),
    emails: t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX.LABEL_EMAILS'),
  }[listKey.value];
});
const typeLabel = count =>
  ({
    phones: t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX.TYPE_PHONES', count),
    channel_ids: t(
      'CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX.TYPE_CHANNEL_IDS',
      count
    ),
    emails: t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX.TYPE_EMAILS', count),
  })[listKey.value];
const help = computed(() => {
  const params = {
    count: entries.value.length,
    type: typeLabel(entries.value.length),
    data: {
      phones: t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX.DATA_PHONES'),
      channel_ids: t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX.DATA_CHANNEL_IDS'),
      emails: t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX.DATA_EMAILS'),
    }[listKey.value],
  };
  return listMode.value === 'allow'
    ? t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX.HELP_ALLOW', params)
    : t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX.HELP_DENY', params);
});
const summary = computed(() => {
  const currentMode = props.inbox.audience_mode;
  if (currentMode !== 'custom') {
    return currentMode === 'everyone'
      ? t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX.SUMMARY_EVERYONE')
      : t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX.SUMMARY_INHERIT');
  }
  const rules = props.inbox.audience_rules || {};
  const parts = [t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX.SUMMARY_CUSTOM')];
  const list = rules[listKey.value];
  if (list) {
    const params = {
      count: list.list.length,
      type: typeLabel(list.list.length),
    };
    parts.push(
      list.mode === 'allow'
        ? t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX.SUMMARY_ALLOW', params)
        : t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX.SUMMARY_DENY', params)
    );
  }
  if (rules.contact_scope && rules.contact_scope !== 'all') {
    parts.push(
      scopes.value.find(option => option.value === rules.contact_scope).label
    );
  }
  return parts.join(' · ');
});
const showWarning = computed(
  () =>
    (open.value ? mode.value : props.inbox.audience_mode || 'inherit') ===
      'inherit' && props.warnings.length > 0
);

const reset = () => {
  const rules = props.inbox.audience_rules || {};
  mode.value = props.inbox.audience_mode || 'inherit';
  listMode.value = rules[listKey.value]?.mode || 'none';
  text.value = (rules[listKey.value]?.list || []).join('\n');
  scope.value = rules.contact_scope || 'all';
  tree.value = hydrateRoot(rules.tree);
  advanced.value = false;
  error.value = '';
};
watch(() => props.inbox, reset, { immediate: true });

const cancel = () => {
  reset();
  open.value = false;
};
const toggle = () => {
  if (saving.value) return;
  if (open.value) cancel();
  else {
    reset();
    open.value = true;
  }
};
const save = async () => {
  if (!props.canEdit || saving.value || validationError.value) return;
  if (mode.value === 'custom' && tree.value.conditions.length) {
    advanced.value = true;
    // Validate the same condition editor used by the assistant's base rule.
    await nextTick();
    if (!groupRef.value.validate()) return;
  }
  const rules = { ...props.inbox.audience_rules };
  if (mode.value === 'custom') {
    if (listKey.value) {
      delete rules[listKey.value];
      if (listMode.value !== 'none') {
        rules[listKey.value] = { mode: listMode.value, list: entries.value };
      }
    }
    rules.contact_scope = scope.value;
    delete rules.tree;
    if (tree.value.conditions.length) rules.tree = serializeNode(tree.value);
  }
  saving.value = true;
  error.value = '';
  saved.value = false;
  try {
    await store.dispatch('captainInboxes/setAudience', {
      assistantId: props.assistantId,
      inboxId: props.inbox.id,
      audienceMode: mode.value,
      audienceRules: rules,
    });
    open.value = false;
    saved.value = true;
  } catch (failure) {
    error.value =
      failure.response?.data?.message ||
      t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX.SAVE_ERROR');
  } finally {
    saving.value = false;
  }
};
</script>

<template>
  <section class="min-w-0 rounded-xl border border-n-weak bg-n-solid-1">
    <button
      type="button"
      class="flex w-full items-start gap-3 p-4 text-start"
      :aria-expanded="open"
      :aria-controls="`inbox-audience-${inbox.id}`"
      @click="toggle"
    >
      <ChannelIcon
        :inbox="inbox"
        class="mt-0.5 size-5 shrink-0 text-n-slate-11"
      />
      <span
        class="flex min-w-0 flex-1 flex-col gap-1 sm:flex-row sm:justify-between sm:gap-4"
      >
        <span class="break-words text-heading-3 text-n-slate-12">{{
          inbox.name
        }}</span>
        <span
          v-if="!open"
          class="flex items-center gap-2 text-sm text-n-slate-11"
        >
          <span
            v-if="showWarning"
            class="i-lucide-triangle-alert size-4 shrink-0 text-n-amber-11"
            :aria-label="t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX.WARNING')"
          />
          <span class="break-words">{{ summary }}</span>
        </span>
      </span>
      <span
        class="mt-0.5 size-4 shrink-0 text-n-slate-11"
        :class="open ? 'i-lucide-chevron-down' : 'i-lucide-chevron-right'"
      />
    </button>
    <p v-if="saved" role="status" class="px-4 pb-3 text-sm text-n-teal-11">
      {{ t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX.SAVED') }}
    </p>
    <div
      v-if="open"
      :id="`inbox-audience-${inbox.id}`"
      class="flex min-w-0 flex-col gap-4 px-4 pb-4"
    >
      <p class="text-body-main text-n-slate-12">
        {{ t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX.ATTENDS') }}
      </p>
      <div
        v-if="canEdit"
        role="radiogroup"
        :aria-label="t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX.ATTENDS')"
        data-testid="inbox-audience-mode"
        class="grid h-8 grid-cols-3 gap-0.5 rounded-lg bg-n-alpha-1 p-0.5 max-sm:h-11"
      >
        <button
          v-for="option in segmentModes"
          :key="option.value"
          type="button"
          role="radio"
          :aria-checked="mode === option.value"
          :data-testid="`inbox-audience-mode-${option.value}`"
          :disabled="saving"
          class="min-w-0 rounded-md px-3 text-xs font-medium transition-colors sm:text-sm"
          :class="
            mode === option.value
              ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
              : 'text-n-slate-11 hover:bg-n-alpha-2'
          "
          @click="mode = option.value"
        >
          <span class="-mx-1 block whitespace-nowrap">{{ option.label }}</span>
        </button>
      </div>
      <p v-else class="text-body-main text-n-slate-11">
        {{ modes.find(option => option.value === mode).label }}
      </p>
      <Banner
        v-for="warning in showWarning ? warnings : []"
        :key="warning"
        color="amber"
        role="status"
      >
        {{ warning }}
      </Banner>
      <div v-if="mode === 'custom'" class="flex min-w-0 flex-col gap-4">
        <fieldset
          :disabled="!canEdit || saving"
          class="flex min-w-0 flex-col gap-4"
        >
          <template v-if="listKey">
            <div class="flex flex-wrap items-center justify-between gap-2">
              <span class="text-body-main text-n-slate-12">{{
                listLabel
              }}</span>
              <FilterSelect
                v-if="canEdit"
                v-model="listMode"
                :options="listModes"
              />
              <span v-else class="text-body-main text-n-slate-11">{{
                listModes.find(option => option.value === listMode).label
              }}</span>
            </div>
            <template v-if="listMode !== 'none'">
              <TextArea
                :id="`audience-list-${inbox.id}`"
                v-model="text"
                :aria-label="listLabel"
                :disabled="!canEdit || saving"
                custom-text-area-class="min-h-28"
              />
              <p class="text-sm text-n-slate-11">{{ help }}</p>
              <p
                v-if="validationError"
                role="alert"
                class="text-sm text-n-ruby-11"
              >
                {{
                  validationError === 'TOO_MANY'
                    ? t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX.TOO_MANY')
                    : t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX.TOO_LONG')
                }}
              </p>
            </template>
          </template>
          <div class="flex flex-wrap items-center justify-between gap-2">
            <span class="text-body-main text-n-slate-12">{{
              t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX.CLIENTS')
            }}</span>
            <FilterSelect v-if="canEdit" v-model="scope" :options="scopes" />
            <span v-else class="text-body-main text-n-slate-11">{{
              scopes.find(option => option.value === scope).label
            }}</span>
          </div>
        </fieldset>
        <Button
          ghost
          slate
          :label="t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX.ADVANCED')"
          :icon="advanced ? 'i-lucide-chevron-down' : 'i-lucide-chevron-right'"
          :aria-expanded="advanced"
          class="self-start"
          @click="advanced = !advanced"
        />
        <fieldset
          v-if="advanced"
          :disabled="!canEdit || saving"
          class="min-w-0"
        >
          <AudienceGroup
            ref="groupRef"
            v-model="tree"
            is-root
            :filter-types="filterTypes"
          />
        </fieldset>
      </div>
      <p v-if="error" role="alert" class="break-words text-sm text-n-ruby-11">
        {{ error }}
      </p>
      <div v-if="canEdit" class="flex flex-wrap justify-end gap-2">
        <Button
          ghost
          slate
          :label="t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX.CANCEL')"
          :disabled="saving"
          @click="cancel"
        />
        <Button
          :label="t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX.SAVE')"
          :disabled="saving || !!validationError"
          :is-loading="saving"
          @click="save"
        />
      </div>
    </div>
  </section>
</template>
