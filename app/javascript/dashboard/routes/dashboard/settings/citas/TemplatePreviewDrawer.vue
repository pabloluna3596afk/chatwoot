<script setup>
import { computed, nextTick, ref } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import SidePanel from 'dashboard/components-next/side-panel/SidePanel.vue';
import WhatsAppBubble from 'dashboard/components-next/whatsapp/WhatsAppBubble.vue';
import { fillExamples, exampleSegments } from './calendarTemplatePreview';

const emit = defineEmits(['correct']);
const panel = ref(null);
const trigger = ref(null);
const activeTemplate = ref(null);
const currentName = computed(() => activeTemplate.value?.title || '');
const open = async (element, template) => {
  trigger.value = element;
  activeTemplate.value = template;
  await nextTick();
  panel.value?.open();
};
const close = () => panel.value?.close();
const restoreFocus = () => trigger.value?.focus({ preventScroll: true });
defineExpose({ open, close });
</script>

<template>
  <SidePanel
    ref="panel"
    width="md"
    full-screen-on-mobile
    :title="currentName"
    :description="$t('CITAS_SCREEN.PREVIEW_HINT')"
    @close="restoreFocus"
  >
    <div v-if="activeTemplate" class="flex flex-col gap-4">
      <div class="flex items-center gap-2">
        <span
          class="size-2 shrink-0 rounded-full"
          :class="
            activeTemplate.color === 'ruby'
              ? 'bg-n-ruby-9'
              : activeTemplate.color === 'amber'
                ? 'bg-n-amber-9'
                : activeTemplate.color === 'teal'
                  ? 'bg-n-teal-9'
                  : 'bg-n-slate-8'
          "
          aria-hidden="true"
        />
        <span class="text-body-main text-n-slate-12">{{
          activeTemplate.statusLabel
        }}</span>
      </div>
      <p v-if="activeTemplate.reason" class="m-0 text-body-main text-n-ruby-11">
        {{
          $t('CITAS_SCREEN.REJECT_REASON', { reason: activeTemplate.reason })
        }}
      </p>
      <WhatsAppBubble
        :body="
          fillExamples(
            activeTemplate.preview?.body || '',
            activeTemplate.language || 'es'
          )
        "
        :body-segments="
          exampleSegments(
            activeTemplate.preview?.body || '',
            activeTemplate.language || 'es'
          )
        "
        :buttons="activeTemplate.preview?.buttons || []"
      />
      <Button
        v-if="activeTemplate.reason"
        intent="secondary"
        :label="$t('CITAS_SCREEN.PREVIEW_FIX')"
        @click="emit('correct', activeTemplate.draftId)"
      />
    </div>
  </SidePanel>
</template>
