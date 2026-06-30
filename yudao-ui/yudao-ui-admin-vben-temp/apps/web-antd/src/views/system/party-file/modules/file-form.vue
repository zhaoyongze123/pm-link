<script lang="ts" setup>
import type { InfraFileApi } from '#/api/infra/file';
import type { SystemDeptApi } from '#/api/system/dept';
import type { SystemPartyFileApi } from '#/api/system/party-file';
import type { SystemRoleApi } from '#/api/system/role';
import type { SystemUserApi } from '#/api/system/user';

import { computed, onMounted, ref } from 'vue';

import { useVbenModal } from '@vben/common-ui';

import { Button, Divider, Input, Select, TreeSelect, message } from 'ant-design-vue';

import { useVbenForm } from '#/adapter/form';
import { getFileListByUrls } from '#/api/infra/file';
import {
  createPartyFile,
  getPartyFile,
  updatePartyFile,
} from '#/api/system/party-file';
import { $t } from '#/locales';

import { buildTargetSelectOptions, usePartyFileFormSchema } from '../data';

type TargetRow = {
  targetType: number;
  targetId?: number;
};

const emit = defineEmits(['success']);
const formData = ref<SystemPartyFileApi.PartyFile>();
const attachmentUrls = ref<string[] | string>('');
const targets = ref<TargetRow[]>([{ targetType: 1 }]);
const users = ref<SystemUserApi.User[]>([]);
const depts = ref<SystemDeptApi.Dept[]>([]);
const roles = ref<SystemRoleApi.Role[]>([]);

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

function resolveAttachmentUrls(files?: Array<{ url?: string }>) {
  return (files || []).map((item) => item.url).filter(Boolean) as string[];
}

function appendTarget() {
  targets.value.push({ targetType: 2 });
}

function removeTarget(index: number) {
  targets.value.splice(index, 1);
  if (targets.value.length === 0) {
    targets.value = [{ targetType: 1 }];
  }
}

function handleTargetTypeChange(index: number, value: number) {
  targets.value[index] = { targetType: value };
  if (value === 1) {
    targets.value = [{ targetType: 1 }];
  }
}

function getTargetOptions(targetType: number) {
  if (targetType === 2) {
    return users.value.map((item) => ({ label: item.nickname, value: item.id }));
  }
  if (targetType === 4) {
    return roles.value.map((item) => ({ label: item.name, value: item.id }));
  }
  return [];
}

const getTitle = computed(() =>
  formData.value?.id ? $t('ui.actionTitle.edit', ['党务文件']) : $t('ui.actionTitle.create', ['党务文件']),
);

const [FormRender, formApi] = useVbenForm({
  commonConfig: {
    componentProps: { class: 'w-full' },
    formItemClass: 'col-span-2',
    labelWidth: 90,
  },
  layout: 'horizontal',
  schema: usePartyFileFormSchema(),
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
    if (!targets.value.length) {
      message.error('请至少配置一个分发对象');
      return;
    }
    if (targets.value.some((item) => item.targetType !== 1 && !item.targetId)) {
      message.error('请补充分发对象');
      return;
    }
    modalApi.lock();
    try {
      const data = (await formApi.getValues()) as SystemPartyFileApi.PartyFile;
      data.attachmentFileIds = await resolveAttachmentFileIds(attachmentUrls.value);
      data.targets = targets.value as SystemPartyFileApi.PartyFileTarget[];
      await (formData.value?.id ? updatePartyFile(data) : createPartyFile(data));
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
      targets.value = [{ targetType: 1 }];
      await formApi.resetForm();
      return;
    }
    const data = modalApi.getData<SystemPartyFileApi.PartyFile>();
    if (!data?.id) {
      formData.value = undefined;
      attachmentUrls.value = '';
      targets.value = [{ targetType: 1 }];
      await formApi.setValues({
        publishTime: new Date().toISOString().slice(0, 19).replace('T', ' '),
        status: 0,
      });
      return;
    }
    modalApi.lock();
    try {
      formData.value = await getPartyFile(data.id);
      attachmentUrls.value = resolveAttachmentUrls(formData.value.attachments);
      targets.value = (formData.value.targets || []).map((item) => ({
        targetType: item.targetType,
        targetId: item.targetId,
      }));
      await formApi.setValues({
        ...formData.value,
        attachmentFileIds: attachmentUrls.value,
      });
    } finally {
      modalApi.unlock();
    }
  },
});

onMounted(async () => {
  const options = await buildTargetSelectOptions();
  users.value = options.users;
  depts.value = options.depts as SystemDeptApi.Dept[];
  roles.value = options.roles;
});
</script>

<template>
  <Modal :title="getTitle" class="w-[960px]">
    <div class="mx-4">
      <FormRender />
      <Divider orientation="left">分发对象</Divider>
      <div class="space-y-3">
        <div
          v-for="(item, index) in targets"
          :key="index"
          class="flex items-center gap-3"
        >
          <Select
            :value="item.targetType"
            class="w-40"
            @update:value="handleTargetTypeChange(index, Number($event))"
          >
            <Select.Option :value="1">全员</Select.Option>
            <Select.Option :value="2">指定用户</Select.Option>
            <Select.Option :value="3">指定部门</Select.Option>
            <Select.Option :value="4">指定角色</Select.Option>
          </Select>
          <TreeSelect
            v-if="item.targetType === 3"
            v-model:value="item.targetId"
            class="flex-1"
            :tree-data="depts"
            :field-names="{ children: 'children', label: 'name', value: 'id' }"
            tree-default-expand-all
            placeholder="请选择部门"
          />
          <Select
            v-else-if="item.targetType !== 1"
            v-model:value="item.targetId"
            class="flex-1"
            :options="getTargetOptions(item.targetType)"
            placeholder="请选择对象"
            show-search
            option-filter-prop="label"
          />
          <Input
            v-else
            value="全员可见"
            class="flex-1"
            disabled
          />
          <Button
            v-if="item.targetType !== 1"
            danger
            @click="removeTarget(index)"
          >
            删除
          </Button>
        </div>
      </div>
      <div class="mt-3">
        <Button
          type="dashed"
          :disabled="targets.length === 1 && targets[0]?.targetType === 1"
          @click="appendTarget"
        >
          新增分发对象
        </Button>
      </div>
    </div>
  </Modal>
</template>
