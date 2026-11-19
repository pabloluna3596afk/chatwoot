<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useTemplateBindings } from 'dashboard/composables/useTemplateBindings';
import { useTemplateVariables } from 'dashboard/components-next/captain/pageComponents/assistant/settings/useTemplateVariables';
import InboxesAPI from 'dashboard/api/inboxes';
import SidePanel from 'dashboard/components-next/side-panel/SidePanel.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import VariablePicker from 'dashboard/components-next/variable-picker/VariablePicker.vue';
import WhatsAppBubble from 'dashboard/components-next/whatsapp/WhatsAppBubble.vue';
import {
  bubbleFromTemplate,
  variablesFromTemplate,
} from 'dashboard/components-next/whatsapp/bubbleFromTemplate';
import {
  templateDataEligible,
  templateVariables,
  variableTokens,
} from './templateData';

const props = defineProps({ template: { type: Object, default: null } });
const emit = defineEmits(['saved']);
const { t, te } = useI18n();
const store = useStore();
const { isAdmin } = useAdmin();
const { bindings } = useTemplateBindings('message');
const { previewValues } = useTemplateVariables({ appointment: false });
const panel = ref(null);
const draft = ref({});
const changedAliases = ref([]);
const suggestions = ref({});
const isLoading = ref(false);
const saveError = ref('');
const variables = computed(() => templateVariables(props.template));
const approved = computed(() => templateDataEligible(props.template));
const bindingFor = path =>
  bindings.value.find(
    binding => binding.key === path || binding.legacyPaths.includes(path)
  );
const pickerValue = token => bindingFor(draft.value[token])?.id || '';
const choose = (token, id) => {
  const binding = bindings.value.find(item => item.id === id);
  draft.value[token] = binding?.key || '';
};
const automatic = item =>
  item.source === 'alias' && !changedAliases.value.includes(item.token);
const labelFor = path => {
  const binding = bindingFor(path);
  const key = `VARIABLE_PICKER.LABELS.${binding?.name}`;
  return te(key) ? t(key) : binding?.label || path;
};
const preview = computed(() => {
  const values = Object.fromEntries(
    variables.value.map(item => {
      const path = automatic(item) ? item.path : draft.value[item.token];
      return [
        item.token,
        previewValues.value[path] ||
          (path ? labelFor(path) : `{{${item.token}}}`),
      ];
    })
  );
  return props.template ? bubbleFromTemplate(props.template, values) : {};
});
const parts = text => (text || '').split(/(\{\{[^}]+\}\})/g);
const open = template => {
  draft.value = {};
  changedAliases.value = [];
  suggestions.value = {};
  saveError.value = '';
  const examples = variablesFromTemplate(template);
  templateVariables(template).forEach(item => {
    if (item.source === 'binding') draft.value[item.token] = item.path;
    if (item.source !== 'missing') return;
    const example = String(examples[item.token] || '');
    if (/^\S+@\S+\.\S+$/.test(example)) {
      draft.value[item.token] = 'contact.email';
      suggestions.value[item.token] = 'SUGGESTED_EMAIL';
    } else if (/^\+?[\d\s()-]{7,}$/.test(example)) {
      draft.value[item.token] = 'contact.phone';
      suggestions.value[item.token] = 'SUGGESTED_PHONE';
    }
  });
  panel.value?.open();
};
const save = async () => {
  if (!isAdmin.value || !approved.value || isLoading.value) return;
  isLoading.value = true;
  saveError.value = '';
  const variable_bindings = Object.fromEntries(
    Object.entries(draft.value).filter(([, value]) => value)
  );
  try {
    await props.template.inboxes.reduce(async (previous, inbox) => {
      await previous;
      try {
        // Bindings are local to each channel; this endpoint never submits content to Meta.
        await InboxesAPI.updateWhatsappTemplateVariableBindings(inbox.id, {
          name: props.template.name,
          variable_bindings,
        });
      } catch {
        saveError.value = t(
          'WHATSAPP_TEMPLATE_MGMT.VARIABLES_DRAWER.SAVE_ERROR',
          { inbox: inbox.name }
        );
        throw new Error(saveError.value);
      }
    }, Promise.resolve());
    await store.dispatch('inboxes/get', { force: true });
    emit('saved');
    panel.value?.close();
  } catch {
    saveError.value ||= t('WHATSAPP_TEMPLATE_MGMT.FETCH_ERROR');
  } finally {
    isLoading.value = false;
  }
};
defineExpose({ open });
</script>

<template>
  <SidePanel
    ref="panel"
    width="md"
    full-screen-on-mobile
    :title="
      t('WHATSAPP_TEMPLATE_MGMT.VARIABLES_DRAWER.TITLE', {
        name: template?.name || '',
      })
    "
  >
    <div v-if="template" class="flex flex-col gap-4">
      <p
        v-if="!approved"
        role="alert"
        class="rounded-lg bg-n-amber-3 p-3 text-sm text-n-amber-11"
      >
        {{ t('WHATSAPP_TEMPLATE_MGMT.VARIABLES_DRAWER.NOT_APPROVED') }}
      </p>
      <WhatsAppBubble v-bind="preview">
        <template v-for="group in ['header', 'body']" :key="group" #[group]>
          <p
            class="whitespace-pre-wrap"
            :class="{ 'font-semibold': group === 'header' }"
          >
            <span
              v-for="(part, index) in parts(preview[group])"
              :key="index"
              :class="
                part.startsWith('{{')
                  ? 'rounded bg-n-amber-3 px-1 text-n-amber-11'
                  : ''
              "
              >{{ part }}</span
            >
          </p>
        </template>
      </WhatsAppBubble>
      <div
        v-for="item in variables"
        :key="`${item.group}:${item.token}`"
        class="grid grid-cols-[4.5rem_minmax(0,1fr)] gap-2"
      >
        <span class="pt-2 font-mono text-sm text-n-slate-11">{{
          variableTokens([item.token])
        }}</span>
        <div class="min-w-0">
          <div
            v-if="automatic(item)"
            class="flex items-center justify-between gap-2 rounded-lg border border-n-weak px-3 py-1.5 text-sm"
          >
            <span>{{
              t('WHATSAPP_TEMPLATE_MGMT.VARIABLES_DRAWER.AUTO', {
                label: labelFor(item.path),
              })
            }}</span>
            <Button
              intent="secondary"
              sm
              :label="t('WHATSAPP_TEMPLATE_MGMT.VARIABLES_DRAWER.CHANGE')"
              :disabled="isLoading || !isAdmin"
              @click="
                changedAliases.push(item.token);
                draft[item.token] = item.path;
              "
            />
          </div>
          <p v-if="automatic(item)" class="mb-0 mt-1 text-xs text-n-slate-11">
            {{
              t('WHATSAPP_TEMPLATE_MGMT.VARIABLES_DRAWER.AUTO_HINT', {
                token: item.token,
              })
            }}
          </p>
          <VariablePicker
            v-if="!automatic(item)"
            value-format="id"
            mode="read"
            allow-none
            :model-value="pickerValue(item.token)"
            :has-error="!draft[item.token]"
            :disabled="isLoading || !approved || !isAdmin"
            :aria-label="'{{' + item.token + '}}'"
            @update:model-value="choose(item.token, $event)"
          />
          <p
            v-if="!automatic(item) && !draft[item.token]"
            class="mb-0 mt-1 text-xs text-n-amber-11"
          >
            {{ t('WHATSAPP_TEMPLATE_MGMT.VARIABLES_DRAWER.MISSING_HINT') }}
          </p>
          <p
            v-if="suggestions[item.token]"
            class="mb-0 mt-1 text-xs text-n-slate-11"
          >
            {{
              t(
                `WHATSAPP_TEMPLATE_MGMT.VARIABLES_DRAWER.${suggestions[item.token]}`
              )
            }}
          </p>
        </div>
      </div>
      <div class="rounded-lg bg-n-alpha-2 p-3 text-xs text-n-slate-11">
        <p>{{ t('WHATSAPP_TEMPLATE_MGMT.VARIABLES_DRAWER.APPLIES_TO') }}</p>
        <p v-for="inbox in template.inboxes" :key="inbox.id">
          {{ inbox.name }} {{ inbox.phone_number }}
        </p>
        <p>{{ t('WHATSAPP_TEMPLATE_MGMT.VARIABLES_DRAWER.WARNING') }}</p>
      </div>
      <p v-if="saveError" role="alert" class="text-sm text-n-ruby-11">
        {{ saveError }}
      </p>
    </div>
    <template #footer>
      <div class="flex justify-end gap-2">
        <Button
          intent="secondary"
          :label="t('WHATSAPP_TEMPLATE_MGMT.VARIABLES_DRAWER.CANCEL')"
          :disabled="isLoading"
          @click="panel.close()"
        />
        <Button
          intent="primary"
          :label="t('WHATSAPP_TEMPLATE_MGMT.VARIABLES_DRAWER.SAVE')"
          :disabled="!approved || !isAdmin || isLoading"
          :is-loading="isLoading"
          @click="save"
        />
      </div>
    </template>
  </SidePanel>
</template>
