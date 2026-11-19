<script setup>
import Message from '../Message.vue';
import receipt from '../../../../../../spec/assets/attachments_demo/receipt.png';
import samplePdf from '../../../../../../spec/assets/sample.pdf';

import simpleEmail from '../fixtures/simpleEmail.js';
import fullConversation from '../fixtures/emailConversation.js';
import newsletterEmail from '../fixtures/newsletterEmail.js';

const failedEmail = {
  ...simpleEmail[0],
  status: 'failed',
  senderId: 1,
  senderType: 'User',
  contentAttributes: {
    ...simpleEmail[0].contentAttributes,
    externalError: 'Failed to send email',
  },
};
const inlineEmail = {
  ...simpleEmail[0],
  contentType: 'incoming_email',
  contentAttributes: {
    email: {
      subject: 'Inline receipt and three files',
      htmlContent: {
        full: `<p>Inline receipt and three documents.</p><img src="${receipt}" alt="Receipt">`,
      },
      textContent: { full: 'Inline receipt and three documents.' },
    },
  },
  attachments: [
    {
      id: 1,
      fileType: 'file',
      contentType: 'application/pdf',
      extension: 'pdf',
      dataUrl: samplePdf,
      fileName: 'Quotation_March_final_version.pdf',
      fileSize: 1258291,
    },
    {
      id: 2,
      fileType: 'file',
      extension: 'docx',
      dataUrl: '/contract.docx',
      fileSize: 235520,
    },
    {
      id: 3,
      fileType: 'file',
      extension: 'xlsx',
      dataUrl: '/prices.xlsx',
      fileSize: 86016,
    },
  ],
};
</script>

<template>
  <Story
    title="Components/Messages/Email"
    :layout="{ type: 'grid', width: '800px' }"
  >
    <Variant title="Inline image and three documents (demo)">
      <div class="p-4 bg-n-background rounded-lg w-full min-w-0">
        <Message :current-user-id="1" is-email-inbox v-bind="inlineEmail" />
      </div>
    </Variant>
    <Variant title="Simple Email">
      <div class="p-4 bg-n-background rounded-lg w-full min-w-5xl grid">
        <template v-for="message in fullConversation" :key="message.id">
          <Message :current-user-id="1" is-email-inbox v-bind="message" />
        </template>
      </div>
    </Variant>
    <Variant title="Newsletter">
      <div class="p-4 bg-n-background rounded-lg w-full min-w-5xl grid">
        <template v-for="message in newsletterEmail" :key="message.id">
          <Message :current-user-id="1" is-email-inbox v-bind="message" />
        </template>
      </div>
    </Variant>
    <Variant title="Failed Email">
      <div class="p-4 bg-n-background rounded-lg w-full min-w-5xl grid">
        <Message :current-user-id="1" is-email-inbox v-bind="failedEmail" />
      </div>
    </Variant>
  </Story>
</template>
