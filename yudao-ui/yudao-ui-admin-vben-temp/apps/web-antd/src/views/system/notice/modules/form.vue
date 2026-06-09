<script lang="ts" setup>
import type { InfraFileApi } from '#/api/infra/file';
import type { SystemNoticeApi } from '#/api/system/notice';

import { computed, ref } from 'vue';

import { useVbenModal } from '@vben/common-ui';

import { message } from 'ant-design-vue';

import { useVbenForm } from '#/adapter/form';
import { getFileListByUrls } from '#/api/infra/file';
import { createNotice, getNotice, updateNotice } from '#/api/system/notice';
import { $t } from '#/locales';

import { useFormSchema } from '../data';

const emit = defineEmits(['success']);
const formData = ref<SystemNoticeApi.Notice>();
const attachmentUrls = ref<string[] | string>('');

function normalizeUrlList(value?: string | string[]) {
  if (!value) {
    return [];
  }
  return (Array.isArray(value) ? value : value.split(','))
    .map((item) => item.trim())
    .filter(Boolean);
}

async function resolveAttachmentFileIds(value: string | string[]) {
  const urls = normalizeUrlList(value);
  if (urls.length === 0) {
    return '';
  }
  const files = await getFileListByUrls(urls);
  const idMap = new Map(files.map((item) => [item.url, item.id]));
  return urls
    .map((url) => idMap.get(url))
    .filter((id): id is number => typeof id === 'number')
    .join(',');
}

function resolveAttachmentUrls(files?: InfraFileApi.File[]) {
  return (files || [])
    .map((item) => item.url)
    .filter((item): item is string => Boolean(item));
}

const getTitle = computed(() => {
  return formData.value?.id
    ? $t('ui.actionTitle.edit', ['公告'])
    : $t('ui.actionTitle.create', ['公告']);
});

const [Form, formApi] = useVbenForm({
  commonConfig: {
    componentProps: {
      class: 'w-full',
    },
    formItemClass: 'col-span-2',
    labelWidth: 80,
  },
  layout: 'horizontal',
  schema: useFormSchema(),
  showDefaultActions: false,
});

formApi.updateSchema([
  {
    fieldName: 'attachmentFileIds',
    componentProps: {
      maxNumber: 10,
      multiple: true,
      showDescription: true,
      modelValue: attachmentUrls.value,
      'onUpdate:modelValue': (value: string | string[]) => {
        attachmentUrls.value = value;
      },
    },
  },
]);

const [Modal, modalApi] = useVbenModal({
  async onConfirm() {
    const { valid } = await formApi.validate();
    if (!valid) {
      return;
    }
    modalApi.lock();
    // 提交表单
    const data = (await formApi.getValues()) as SystemNoticeApi.Notice;
    try {
      data.attachmentFileIds = await resolveAttachmentFileIds(attachmentUrls.value);
      await (formData.value?.id ? updateNotice(data) : createNotice(data));
      // 关闭并提示
      await modalApi.close();
      emit('success');
      message.success($t('ui.actionMessage.operationSuccess'));
    } finally {
      modalApi.unlock();
    }
  },
  async onOpenChange(isOpen: boolean) {
    if (!isOpen) {
      formData.value = undefined;
      attachmentUrls.value = '';
      return;
    }
    // 加载数据
    const data = modalApi.getData<SystemNoticeApi.Notice>();
    if (!data || !data.id) {
      attachmentUrls.value = '';
      await formApi.setValues({ attachmentFileIds: '' });
      return;
    }
    modalApi.lock();
    try {
      formData.value = await getNotice(data.id);
      attachmentUrls.value = resolveAttachmentUrls(formData.value.attachments);
      // 设置到 values
      await formApi.setValues({
        ...formData.value,
        attachmentFileIds: attachmentUrls.value,
      });
    } finally {
      modalApi.unlock();
    }
  },
});
</script>

<template>
  <Modal :title="getTitle" class="w-1/2">
    <Form class="mx-4" />
  </Modal>
</template>
