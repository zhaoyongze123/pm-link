package cn.iocoder.yudao.module.system.service.notice;

import cn.hutool.core.collection.CollUtil;
import cn.hutool.core.util.StrUtil;
import cn.iocoder.yudao.framework.common.pojo.PageResult;
import cn.iocoder.yudao.framework.common.util.object.BeanUtils;
import cn.iocoder.yudao.module.infra.dal.dataobject.file.FileDO;
import cn.iocoder.yudao.module.infra.service.file.FileService;
import cn.iocoder.yudao.module.system.controller.admin.notice.vo.NoticeAttachmentRespVO;
import cn.iocoder.yudao.module.system.controller.admin.notice.vo.NoticePageReqVO;
import cn.iocoder.yudao.module.system.controller.admin.notice.vo.NoticeReadRespVO;
import cn.iocoder.yudao.module.system.controller.admin.notice.vo.NoticeRespVO;
import cn.iocoder.yudao.module.system.controller.admin.notice.vo.NoticeSaveReqVO;
import cn.iocoder.yudao.module.system.dal.dataobject.notice.NoticeDO;
import cn.iocoder.yudao.module.system.dal.dataobject.notice.NoticeReadDO;
import cn.iocoder.yudao.module.system.dal.mysql.notice.NoticeMapper;
import cn.iocoder.yudao.module.system.dal.mysql.notice.NoticeReadMapper;
import com.google.common.annotations.VisibleForTesting;
import org.springframework.stereotype.Service;

import javax.annotation.Resource;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Objects;
import java.util.stream.Collectors;

import static cn.iocoder.yudao.framework.common.exception.util.ServiceExceptionUtil.exception;
import static cn.iocoder.yudao.module.system.enums.ErrorCodeConstants.NOTICE_NOT_FOUND;

/**
 * 通知公告 Service 实现类
 *
 * @author 芋道源码
 */
@Service
public class NoticeServiceImpl implements NoticeService {

    @Resource
    private NoticeMapper noticeMapper;

    @Resource
    private NoticeReadMapper noticeReadMapper;

    @Resource
    private FileService fileService;

    @Override
    public Long createNotice(NoticeSaveReqVO createReqVO) {
        NoticeDO notice = BeanUtils.toBean(createReqVO, NoticeDO.class);
        noticeMapper.insert(notice);
        return notice.getId();
    }

    @Override
    public void updateNotice(NoticeSaveReqVO updateReqVO) {
        // 校验是否存在
        validateNoticeExists(updateReqVO.getId());
        // 更新通知公告
        NoticeDO updateObj = BeanUtils.toBean(updateReqVO, NoticeDO.class);
        noticeMapper.updateById(updateObj);
    }

    @Override
    public void deleteNotice(Long id) {
        // 校验是否存在
        validateNoticeExists(id);
        // 删除通知公告
        noticeMapper.deleteById(id);
    }

    @Override
    public void deleteNoticeList(List<Long> ids) {
        noticeMapper.deleteByIds(ids);
    }

    @Override
    public PageResult<NoticeDO> getNoticePage(NoticePageReqVO reqVO) {
        return noticeMapper.selectPage(reqVO);
    }

    @Override
    public NoticeDO getNotice(Long id) {
        return noticeMapper.selectById(id);
    }

    @Override
    public NoticeRespVO getNoticeDetail(Long id) {
        NoticeDO notice = getNotice(id);
        if (notice == null) {
            return null;
        }
        NoticeRespVO detail = BeanUtils.toBean(notice, NoticeRespVO.class);
        List<NoticeReadDO> readList = noticeReadMapper.selectListByNoticeId(id);
        detail.setReadCount((long) readList.size());
        detail.setReadList(readList.stream().map(item -> {
            NoticeReadRespVO read = new NoticeReadRespVO();
            read.setUserId(item.getUserId());
            read.setUserNickname(item.getUserNickname());
            read.setReadTime(item.getReadTime());
            return read;
        }).collect(Collectors.toList()));
        detail.setAttachments(buildAttachments(notice.getAttachmentFileIds()));
        return detail;
    }

    @Override
    public void markNoticeRead(Long id, Long userId, String userNickname) {
        validateNoticeExists(id);
        if (userId == null) {
            return;
        }
        NoticeReadDO existed = noticeReadMapper.selectByNoticeIdAndUserId(id, userId);
        if (existed != null) {
            existed.setReadTime(LocalDateTime.now());
            existed.setUserNickname(StrUtil.blankToDefault(userNickname, existed.getUserNickname()));
            noticeReadMapper.updateById(existed);
            return;
        }
        NoticeReadDO readDO = new NoticeReadDO();
        readDO.setNoticeId(id);
        readDO.setUserId(userId);
        readDO.setUserNickname(StrUtil.blankToDefault(userNickname, "未命名用户"));
        readDO.setReadTime(LocalDateTime.now());
        noticeReadMapper.insert(readDO);
    }

    private List<NoticeAttachmentRespVO> buildAttachments(String attachmentFileIds) {
        List<Long> fileIds = parseFileIds(attachmentFileIds);
        if (CollUtil.isEmpty(fileIds)) {
            return Collections.emptyList();
        }
        List<NoticeAttachmentRespVO> attachments = new ArrayList<>();
        for (Long fileId : fileIds) {
            FileDO file = fileService.getFile(fileId);
            if (file == null) {
                continue;
            }
            NoticeAttachmentRespVO attachment = new NoticeAttachmentRespVO();
            attachment.setId(file.getId());
            attachment.setName(file.getName());
            attachment.setUrl(file.getUrl());
            attachment.setType(file.getType());
            attachment.setSize(file.getSize());
            attachments.add(attachment);
        }
        return attachments;
    }

    private List<Long> parseFileIds(String attachmentFileIds) {
        if (StrUtil.isBlank(attachmentFileIds)) {
            return Collections.emptyList();
        }
        return StrUtil.splitTrim(attachmentFileIds, ',').stream()
                .map(item -> StrUtil.isBlank(item) ? null : Long.valueOf(item))
                .filter(Objects::nonNull)
                .collect(Collectors.toList());
    }

    @VisibleForTesting
    public void validateNoticeExists(Long id) {
        if (id == null) {
            return;
        }
        NoticeDO notice = noticeMapper.selectById(id);
        if (notice == null) {
            throw exception(NOTICE_NOT_FOUND);
        }
    }

}
