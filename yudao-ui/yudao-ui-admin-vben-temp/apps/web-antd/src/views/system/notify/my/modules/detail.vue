<script lang="ts" setup>
import type { SystemNotifyMessageApi } from '#/api/system/notify/message';
import type { SystemNoticeApi } from '#/api/system/notice';

import { computed, ref } from 'vue';

import { useVbenModal } from '@vben/common-ui';
import { formatDateTime } from '@vben/utils';

import { Button, Empty, Modal, Tag } from 'ant-design-vue';

import {
  extractNoticeId,
} from '#/api/system/notify/message';
import { getNotice } from '#/api/system/notice';

const messageData = ref<SystemNotifyMessageApi.NotifyMessage>();
const noticeDetail = ref<SystemNoticeApi.Notice>();
const isNoticeMessage = computed(() => !!extractNoticeId(messageData.value));

const [ModalApi, modalApi] = useVbenModal({
  async onOpenChange(isOpen: boolean) {
    if (!isOpen) {
      messageData.value = undefined;
      noticeDetail.value = undefined;
      return;
    }
    const data = modalApi.getData<SystemNotifyMessageApi.NotifyMessage>();
    if (!data?.id) {
      return;
    }
    modalApi.lock();
    try {
      messageData.value = data;
      const noticeId = extractNoticeId(data);
      noticeDetail.value = noticeId ? await getNotice(noticeId) : undefined;
    } finally {
      modalApi.unlock();
    }
  },
});

const formattedSendTime = computed(() =>
  messageData.value?.createTime ? formatDateTime(messageData.value.createTime) : '-',
);

const formattedReadTime = computed(() =>
  messageData.value?.readTime ? formatDateTime(messageData.value.readTime) : '-',
);

function handlePreview(url?: string) {
  if (!url) {
    return;
  }
  window.open(url, '_blank', 'noopener,noreferrer');
}

function handleDownload(url?: string) {
  if (!url) {
    return;
  }
  window.open(url, '_blank', 'noopener,noreferrer');
}
</script>

<template>
  <ModalApi
    title="通知详情"
    class="w-[860px]"
    :show-cancel-button="false"
    :show-confirm-button="false"
  >
    <template v-if="messageData">
      <div class="notify-detail">
        <div class="notify-detail__meta">
          <div class="notify-detail__row">
            <span class="label">发送人</span>
            <span>{{ messageData.templateNickname }}</span>
          </div>
          <div class="notify-detail__row">
            <span class="label">状态</span>
            <Tag :color="messageData.readStatus ? 'default' : 'processing'">
              {{ messageData.readStatus ? '已读' : '未读' }}
            </Tag>
          </div>
          <div class="notify-detail__row">
            <span class="label">发送时间</span>
            <span>{{ formattedSendTime }}</span>
          </div>
          <div class="notify-detail__row" v-if="messageData.readTime">
            <span class="label">阅读时间</span>
            <span>{{ formattedReadTime }}</span>
          </div>
        </div>

        <template v-if="isNoticeMessage && noticeDetail">
          <div class="notify-detail__notice">
            <div class="notify-detail__heading">
              <h3>{{ noticeDetail.title }}</h3>
              <Tag :color="noticeDetail.pinned ? 'blue' : 'default'">
                {{ noticeDetail.pinned ? '置顶' : '未置顶' }}
              </Tag>
            </div>
            <div class="notify-detail__summary">
              <span>发布对象：{{ noticeDetail.publishTarget || '全体后台用户' }}</span>
              <span>发布时间：{{ formatDateTime(noticeDetail.createTime) }}</span>
            </div>
            <div class="notify-detail__content" v-html="noticeDetail.content"></div>

            <section class="notify-detail__attachments">
              <div class="notify-detail__attachments-head">
                <h4>附件</h4>
              </div>
              <div
                v-if="noticeDetail.attachments && noticeDetail.attachments.length"
                class="notify-detail__attachment-list"
              >
                <div
                  v-for="item in noticeDetail.attachments"
                  :key="item.id"
                  class="notify-detail__attachment-item"
                >
                  <div>
                    <strong>{{ item.name }}</strong>
                    <p>{{ item.type || '未知类型' }}</p>
                  </div>
                  <div class="notify-detail__attachment-actions">
                    <Button type="link" size="small" @click="handlePreview(item.url)">
                      预览
                    </Button>
                    <Button type="link" size="small" @click="handleDownload(item.url)">
                      下载
                    </Button>
                  </div>
                </div>
              </div>
              <Empty
                v-else
                :image="Empty.PRESENTED_IMAGE_SIMPLE"
                description="暂无附件"
              />
            </section>
          </div>
        </template>

        <div v-else class="notify-detail__plain">
          {{ messageData.templateContent }}
        </div>
      </div>
    </template>
  </ModalApi>
</template>

<style scoped>
.notify-detail {
  display: flex;
  flex-direction: column;
  gap: 20px;
}

.notify-detail__meta {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 12px 24px;
  padding-bottom: 16px;
  border-bottom: 1px solid rgb(15 23 42 / 10%);
}

.notify-detail__row {
  display: flex;
  align-items: center;
  gap: 12px;
}

.notify-detail__row .label {
  min-width: 72px;
  color: rgb(100 116 139);
}

.notify-detail__heading {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
}

.notify-detail__heading h3 {
  margin: 0;
  font-size: 28px;
  line-height: 1.3;
}

.notify-detail__summary {
  display: flex;
  gap: 20px;
  margin-top: 10px;
  color: rgb(100 116 139);
  font-size: 13px;
}

.notify-detail__content {
  margin-top: 18px;
  color: rgb(15 23 42);
  line-height: 1.85;
}

.notify-detail__attachments {
  margin-top: 24px;
  padding-top: 18px;
  border-top: 1px solid rgb(15 23 42 / 10%);
}

.notify-detail__attachments-head h4 {
  margin: 0 0 12px;
  font-size: 15px;
}

.notify-detail__attachment-list {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.notify-detail__attachment-item {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding: 12px 0;
  border-bottom: 1px solid rgb(15 23 42 / 8%);
}

.notify-detail__attachment-item p {
  margin: 4px 0 0;
  color: rgb(100 116 139);
}

.notify-detail__attachment-actions {
  display: flex;
  gap: 8px;
}

.notify-detail__plain {
  line-height: 1.8;
  color: rgb(15 23 42);
  white-space: pre-wrap;
}
</style>
