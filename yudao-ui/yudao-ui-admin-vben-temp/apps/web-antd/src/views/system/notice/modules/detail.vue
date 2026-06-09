<script lang="ts" setup>
import type { SystemNoticeApi } from '#/api/system/notice';

import { computed, ref } from 'vue';

import { useVbenModal } from '@vben/common-ui';
import { formatDateTime } from '@vben/utils';

import { Button, Empty, Tag } from 'ant-design-vue';

import { getNotice, readNotice } from '#/api/system/notice';

const notice = ref<SystemNoticeApi.Notice>();

const [Modal, modalApi] = useVbenModal({
  async onOpenChange(isOpen: boolean) {
    if (!isOpen) {
      notice.value = undefined;
      return;
    }
    const row = modalApi.getData<SystemNoticeApi.Notice>();
    if (!row?.id) {
      return;
    }
    modalApi.lock();
    try {
      await readNotice(row.id);
      notice.value = await getNotice(row.id);
    } finally {
      modalApi.unlock();
    }
  },
});

const attachmentCount = computed(() => notice.value?.attachments?.length || 0);

const formattedCreateTime = computed(() =>
  notice.value?.createTime ? formatDateTime(notice.value.createTime) : '-',
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

function handleBatchDownload() {
  notice.value?.attachments?.forEach((item) => handleDownload(item.url));
}

function formatReadTime(value?: Date | string) {
  return value ? formatDateTime(value) : '-';
}
</script>

<template>
  <Modal title="公告详情" class="w-[860px]">
    <div v-if="notice" class="notice-detail">
      <header class="notice-detail__header">
        <div>
          <h2>{{ notice.title }}</h2>
          <p>{{ notice.publishTarget || '全体后台用户' }}</p>
        </div>
        <Tag :color="notice.pinned ? 'blue' : 'default'">
          {{ notice.pinned ? '置顶' : '未置顶' }}
        </Tag>
      </header>

      <section class="notice-detail__section">
        <h3>通知基本信息</h3>
        <dl class="notice-detail__meta">
          <div>
            <dt>发布对象</dt>
            <dd>{{ notice.publishTarget || '全体后台用户' }}</dd>
          </div>
          <div>
            <dt>发布人</dt>
            <dd>{{ notice.creator || '-' }}</dd>
          </div>
          <div>
            <dt>发布/创建时间</dt>
            <dd>{{ formattedCreateTime }}</dd>
          </div>
          <div>
            <dt>置顶状态</dt>
            <dd>{{ notice.pinned ? '置顶' : '否' }}</dd>
          </div>
        </dl>
      </section>

      <section class="notice-detail__section">
        <h3>公告正文</h3>
        <div class="notice-detail__content" v-html="notice.content"></div>
      </section>

      <section class="notice-detail__section">
        <div class="notice-detail__section-head">
          <h3>附件信息</h3>
          <Button
            v-if="attachmentCount > 1"
            size="small"
            type="link"
            @click="handleBatchDownload"
          >
            批量下载
          </Button>
        </div>
        <div v-if="attachmentCount" class="notice-detail__attachments">
          <div
            v-for="item in notice.attachments"
            :key="item.id"
            class="notice-detail__attachment"
          >
            <div>
              <strong>{{ item.name }}</strong>
              <p>{{ item.type || '未知类型' }}</p>
            </div>
            <div class="notice-detail__attachment-actions">
              <Button size="small" type="link" @click="handlePreview(item.url)">
                预览
              </Button>
              <Button size="small" type="link" @click="handleDownload(item.url)">
                下载
              </Button>
            </div>
          </div>
        </div>
        <Empty v-else :image="Empty.PRESENTED_IMAGE_SIMPLE" description="暂无附件" />
      </section>

      <section class="notice-detail__section">
        <h3>阅读情况</h3>
        <p class="notice-detail__read-summary">
          系统统计显示：已有 {{ notice.readCount || 0 }} 人浏览了该通知。
        </p>
        <div v-if="notice.readList?.length" class="notice-detail__read-list">
          <div
            v-for="item in notice.readList"
            :key="`${item.userId}-${item.readTime}`"
            class="notice-detail__read-item"
          >
            <span>{{ item.userNickname }}</span>
            <time>{{ formatReadTime(item.readTime) }}</time>
          </div>
        </div>
        <Empty v-else :image="Empty.PRESENTED_IMAGE_SIMPLE" description="暂无阅读记录" />
      </section>
    </div>
  </Modal>
</template>

<style scoped>
.notice-detail {
  display: flex;
  flex-direction: column;
  gap: 24px;
}

.notice-detail__header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
  padding-bottom: 16px;
  border-bottom: 1px solid rgb(15 23 42 / 10%);
}

.notice-detail__header h2 {
  margin: 0;
  font-size: 24px;
  line-height: 1.3;
}

.notice-detail__header p {
  margin: 8px 0 0;
  color: rgb(100 116 139);
}

.notice-detail__section {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.notice-detail__section h3 {
  margin: 0;
  font-size: 15px;
  font-weight: 600;
}

.notice-detail__section-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.notice-detail__meta {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 12px 24px;
  margin: 0;
}

.notice-detail__meta div {
  padding-bottom: 10px;
  border-bottom: 1px solid rgb(15 23 42 / 8%);
}

.notice-detail__meta dt {
  margin-bottom: 4px;
  color: rgb(100 116 139);
  font-size: 12px;
}

.notice-detail__meta dd {
  margin: 0;
  color: rgb(15 23 42);
}

.notice-detail__content {
  line-height: 1.8;
  color: rgb(15 23 42);
}

.notice-detail__attachments,
.notice-detail__read-list {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.notice-detail__attachment,
.notice-detail__read-item {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding: 12px 0;
  border-bottom: 1px solid rgb(15 23 42 / 8%);
}

.notice-detail__attachment p,
.notice-detail__read-summary {
  margin: 0;
  color: rgb(100 116 139);
}

.notice-detail__attachment-actions {
  display: flex;
  gap: 8px;
}
</style>
